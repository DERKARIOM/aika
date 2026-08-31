import 'dart:async';

import 'package:flutter/material.dart';
import 'package:localsend_app/config/theme.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/qr_pairing_payload.dart';
import 'package:localsend_app/model/state/qr_pairing_network_state.dart';
import 'package:localsend_app/provider/device_info_provider.dart';
import 'package:localsend_app/provider/local_ip_provider.dart';
import 'package:localsend_app/util/native/hotspot_helper.dart';
import 'package:localsend_app/widget/custom_basic_appbar.dart';
import 'package:localsend_app/widget/responsive_list_view.dart';
import 'package:localsend_isolates/constants.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// "Émetteur" screen of the Smart QR Code pairing feature.
///
/// Shows a QR code that another Aika device can scan to instantly connect
/// to this device on the local network, without waiting for the automatic
/// (multicast) discovery. The code:
/// - is only valid for a short, user-selectable duration ([qrPairingTtlOptions]),
/// - can be regenerated at any time (e.g. after it expired, or simply to
///   invalidate a code that was shown to someone else),
/// - only encodes local-network connection details plus the certificate
///   fingerprint used to verify the peer once scanned (see
///   [QrPairingPayload] for the full security rationale).
///
/// Before showing the code, this page makes sure the device actually has a
/// usable local network to advertise:
/// - if Wi-Fi/Ethernet is already connected, it behaves exactly as before;
/// - otherwise (Android only) it tries to start a local-only Wi-Fi hotspot
///   automatically ([tryActivateLocalOnlyHotspot]) so two devices can still
///   pair without any pre-existing network;
/// - if automatic activation isn't possible (iOS, unsupported Android
///   version, denied permission, or the platform call failing), it falls
///   back to guiding the user to system Settings and detects their return
///   to the app to re-check connectivity.
///
/// See [QrNetworkPrepState] for the full state machine and
/// `lib/util/native/hotspot_helper.dart` for the platform capability notes.
class QrPairingDisplayPage extends StatefulWidget {
  const QrPairingDisplayPage();

  @override
  State<QrPairingDisplayPage> createState() => _QrPairingDisplayPageState();
}

class _QrPairingDisplayPageState extends State<QrPairingDisplayPage> with Refena, WidgetsBindingObserver {
  /// Maximum time to wait for a usable local IP to show up (after a hotspot
  /// was started, or after the user came back from Settings) before giving
  /// up and falling back to manual guidance. Keeps the flow from blocking
  /// indefinitely if the network never comes up.
  static const _ipWaitTimeout = Duration(seconds: 10);
  static const _ipPollInterval = Duration(milliseconds: 400);

  /// Small pause on a freshly-ready network so the "Your network is ready"
  /// message is actually readable before the QR code replaces it, instead of
  /// flashing by unnoticed.
  static const _readyFlashDuration = Duration(milliseconds: 700);

  Duration _ttl = qrPairingDefaultTtl;
  QrPairingPayload? _payload;
  Timer? _tickTimer;

  QrNetworkPrepState _networkState = const QrNetworkPrepState.checking();
  String? _hotspotSsid;
  String? _hotspotPassphrase;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _prepareNetwork());
    // Refreshes the countdown label every second and auto-expires the code.
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tickTimer?.cancel();
    super.dispose();
    // Intentionally NOT calling stopLocalOnlyHotspotIfActive() here: the user
    // may still want the just-created hotspot to stay up (e.g. the other
    // device is still transferring files), so it is left running until the
    // OS reclaims it or the user turns it off manually.
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _networkState.status == QrNetworkPrepStatus.waitingForUserInSettings && mounted) {
      // The user just came back from system Settings: re-check now instead
      // of waiting for a possibly-delayed connectivity event.
      unawaited(_waitForIp(hotspotActive: false));
    }
  }

  /// Entry point of the network-preparation flow, run once when the page
  /// first opens. Reuses the app's existing IP/server state instead of
  /// creating any parallel network stack: the Rust HTTP server already
  /// listens on all interfaces (see `packages/core/src/http/server/mod.rs`),
  /// so nothing needs to be restarted once a usable IP appears.
  Future<void> _prepareNetwork() async {
    setState(() => _networkState = const QrNetworkPrepState.checking());

    if (_hasUsableIp(ref.read(deviceFullInfoProvider))) {
      // Already connected (Wi-Fi/Ethernet/existing hotspot): behave exactly
      // like before this feature existed.
      setState(() => _networkState = const QrNetworkPrepState.ready());
      _regenerate();
      return;
    }

    final hasNetwork = await hasUsableNetworkConnection();
    if (!mounted) {
      return;
    }

    if (hasNetwork) {
      // Wi-Fi/Ethernet is reported as connected but the IP hasn't reached
      // `localIpProvider` yet (e.g. still negotiating DHCP): give it a
      // short, bounded window rather than assuming there is no network.
      await _waitForIp(hotspotActive: false);
    } else {
      await _activateHotspotFlow();
    }
  }

  /// Tries to start a local-only Wi-Fi hotspot automatically (Android only).
  /// Falls back to manual guidance whenever automatic activation isn't
  /// possible or fails, rather than assuming it will always work.
  Future<void> _activateHotspotFlow() async {
    if (!canAutoActivateHotspot) {
      setState(() => _networkState = const QrNetworkPrepState.needsManualAction(reason: 'unsupported_platform'));
      return;
    }

    setState(() => _networkState = const QrNetworkPrepState.activatingHotspot());

    final androidSdkInt = ref.read(deviceRawInfoProvider).androidSdkInt;
    final result = await tryActivateLocalOnlyHotspot(androidSdkInt: androidSdkInt);
    if (!mounted) {
      return;
    }

    if (!result.success) {
      setState(() => _networkState = QrNetworkPrepState.needsManualAction(reason: result.failureReason));
      return;
    }

    _hotspotSsid = result.ssid;
    _hotspotPassphrase = result.passphrase;
    await _waitForIp(hotspotActive: true);
  }

  /// Waits (with a bounded timeout) for `localIpProvider` to report a usable
  /// IP address, forcing an immediate refresh instead of passively trusting
  /// `onConnectivityChanged`, which is not guaranteed to fire promptly right
  /// after a hotspot was started or Settings were changed.
  Future<void> _waitForIp({required bool hotspotActive}) async {
    setState(() => _networkState = const QrNetworkPrepState.waitingForIp());

    unawaited(ref.redux(localIpProvider).dispatchAsync(FetchLocalIpAction()));

    final deadline = DateTime.now().add(_ipWaitTimeout);
    while (mounted && DateTime.now().isBefore(deadline)) {
      if (_hasUsableIp(ref.read(deviceFullInfoProvider))) {
        setState(() => _networkState = const QrNetworkPrepState.readyFlash());
        await Future.delayed(_readyFlashDuration);
        if (!mounted) {
          return;
        }
        setState(() {
          _networkState = hotspotActive
              ? QrNetworkPrepState.hotspotReady(ssid: _hotspotSsid, passphrase: _hotspotPassphrase)
              : const QrNetworkPrepState.ready();
        });
        _regenerate();
        return;
      }
      await Future.delayed(_ipPollInterval);
    }

    if (!mounted) {
      return;
    }

    if (hotspotActive) {
      // The hotspot claimed to start but never yielded a usable IP: nothing
      // more to try automatically.
      setState(() => _networkState = const QrNetworkPrepState.failed());
    } else {
      // Plain "wait and see" attempt timed out: offer manual guidance
      // (Settings) rather than retrying silently forever.
      setState(() => _networkState = const QrNetworkPrepState.needsManualAction());
    }
  }

  /// Opens system Settings (best-effort deep link, see
  /// `openHotspotOrWifiSettings`) and switches to a state that re-checks
  /// connectivity as soon as the user returns to the app.
  Future<void> _openSettingsAndWait() async {
    setState(() => _networkState = const QrNetworkPrepState.waitingForUserInSettings());
    await openHotspotOrWifiSettings();
  }

  bool _hasUsableIp(Device device) {
    return device.ip != null && device.ip != '-' && device.port > 0;
  }

  void _regenerate() {
    final device = ref.read(deviceFullInfoProvider);
    if (!_hasUsableIp(device)) {
      setState(() => _payload = null);
      return;
    }

    setState(() {
      _payload = QrPairingPayload.generate(
        protocolVersion: protocolVersion,
        alias: device.alias,
        deviceModel: device.deviceModel,
        deviceType: device.deviceType,
        ip: device.ip!,
        port: device.port,
        https: device.https,
        fingerprint: device.fingerprint,
        ttl: _ttl,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    // Keep the QR code in sync if the server restarts on a different port/
    // encryption mode, or the local IP changes while this screen is open
    // (e.g. Wi-Fi renewed its DHCP lease). Without this, a stale IP/port
    // could stay baked into the displayed QR code and every scan of it
    // would fail to reach the device.
    final currentInfo = ref.watch(deviceFullInfoProvider);
    final payload = _payload;
    final readyStatus = _networkState.status == QrNetworkPrepStatus.ready || _networkState.status == QrNetworkPrepStatus.hotspotReady;
    if (readyStatus &&
        payload != null &&
        (currentInfo.ip != payload.ip || currentInfo.port != payload.port || currentInfo.https != payload.https)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _regenerate());
    }

    return Scaffold(
      appBar: basicLocalSendAppbar(t.qrPairing.display.title),
      body: SafeArea(
        child: ResponsiveListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          children: _buildBody(context, payload: payload),
        ),
      ),
    );
  }

  List<Widget> _buildBody(BuildContext context, {required QrPairingPayload? payload}) {
    final colorScheme = Theme.of(context).colorScheme;

    switch (_networkState.status) {
      case QrNetworkPrepStatus.checking:
        return _loadingBody(context, message: t.qrPairing.display.preparingNetwork);
      case QrNetworkPrepStatus.activatingHotspot:
        return _loadingBody(context, message: t.qrPairing.display.activatingHotspot);
      case QrNetworkPrepStatus.waitingForIp:
        return _loadingBody(context, message: t.qrPairing.display.waitingForNetwork);
      case QrNetworkPrepStatus.readyFlash:
        return _loadingBody(context, message: t.qrPairing.display.networkReady, icon: Icons.check_circle_outline_rounded);
      case QrNetworkPrepStatus.waitingForUserInSettings:
        return _loadingBody(context, message: t.qrPairing.display.waitingInSettings, icon: Icons.settings_outlined);
      case QrNetworkPrepStatus.needsManualAction:
      case QrNetworkPrepStatus.failed:
        return _manualActionBody(context);
      case QrNetworkPrepStatus.ready:
      case QrNetworkPrepStatus.hotspotReady:
        if (payload == null) {
          // Network is up but e.g. "receiving" isn't active yet: same
          // messaging as before this feature existed.
          return [
            const SizedBox(height: 40),
            Icon(Icons.wifi_off_rounded, size: 48, color: colorScheme.warning),
            const SizedBox(height: 16),
            Text(
              t.qrPairing.display.offline,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ];
        }
        return _qrBody(context, payload: payload);
    }
  }

  List<Widget> _loadingBody(BuildContext context, {required String message, IconData icon = Icons.wifi_find_rounded}) {
    final colorScheme = Theme.of(context).colorScheme;
    return [
      const SizedBox(height: 60),
      Center(
        child: _GlassCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 48,
                height: 48,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const SizedBox(width: 48, height: 48, child: CircularProgressIndicator(strokeWidth: 3)),
                    Icon(icon, size: 22, color: colorScheme.primary),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
      ),
    ];
  }

  List<Widget> _manualActionBody(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isAndroid = canAutoActivateHotspot;
    return [
      const SizedBox(height: 40),
      Icon(Icons.wifi_off_rounded, size: 48, color: colorScheme.warning),
      const SizedBox(height: 16),
      Text(
        t.qrPairing.display.manualActionTitle,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 8),
      Text(
        isAndroid ? t.qrPairing.display.manualActionDescriptionAndroid : t.qrPairing.display.manualActionDescriptionOther,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
      ),
      const SizedBox(height: 24),
      Center(
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.center,
          children: [
            FilledButton.icon(
              onPressed: () => unawaited(_openSettingsAndWait()),
              icon: const Icon(Icons.settings_outlined),
              label: Text(t.qrPairing.display.openSettings),
            ),
            OutlinedButton.icon(
              onPressed: () => unawaited(_prepareNetwork()),
              icon: const Icon(Icons.refresh),
              label: Text(t.qrPairing.display.retry),
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _qrBody(BuildContext context, {required QrPairingPayload payload}) {
    return [
      if (_networkState.status == QrNetworkPrepStatus.hotspotReady) ...[
        const SizedBox(height: 10),
        _HotspotInfoPanel(ssid: _hotspotSsid, passphrase: _hotspotPassphrase),
      ],
      const SizedBox(height: 10),
      Center(
        child: _GlassCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: 220,
                    height: 220,
                    child: PrettyQrView.data(
                      data: payload.encode(),
                      errorCorrectLevel: QrErrorCorrectLevel.Q,
                      decoration: const PrettyQrDecoration(
                        shape: PrettyQrSmoothSymbol(
                          roundFactor: 1,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                payload.alias,
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              Text(
                '${payload.ip}:${payload.port}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              _CountdownChip(payload: payload),
            ],
          ),
        ),
      ),
      const SizedBox(height: 24),
      Text(t.qrPairing.display.expiration, style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: qrPairingTtlOptions.map((duration) {
          final selected = duration == _ttl;
          return ChoiceChip(
            label: Text(duration.qrPairingLabel),
            selected: selected,
            onSelected: (_) {
              setState(() => _ttl = duration);
              _regenerate();
            },
          );
        }).toList(),
      ),
      const SizedBox(height: 24),
      Center(
        child: FilledButton.tonalIcon(
          onPressed: _regenerate,
          icon: const Icon(Icons.refresh),
          label: Text(t.qrPairing.display.regenerate),
        ),
      ),
      const SizedBox(height: 24),
      _SecurityNote(),
      const SizedBox(height: 30),
    ];
  }
}

class _CountdownChip extends StatelessWidget {
  final QrPairingPayload payload;

  const _CountdownChip({required this.payload});

  @override
  Widget build(BuildContext context) {
    final remaining = payload.remaining;
    final expired = remaining == Duration.zero;
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: (expired ? colorScheme.error : colorScheme.primary).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            expired ? Icons.timer_off_rounded : Icons.timer_outlined,
            size: 16,
            color: expired ? colorScheme.error : colorScheme.primary,
          ),
          const SizedBox(width: 6),
          Text(
            expired ? t.qrPairing.display.expired : t.qrPairing.display.expiresIn(duration: remaining.qrPairingLabel),
            style: TextStyle(color: expired ? colorScheme.error : colorScheme.primary, fontWeight: FontWeight.w600, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _SecurityNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.shield_outlined, size: 18, color: Theme.of(context).colorScheme.secondary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            t.qrPairing.display.securityNote,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

class _HotspotInfoPanel extends StatelessWidget {
  final String? ssid;
  final String? passphrase;

  const _HotspotInfoPanel({required this.ssid, required this.passphrase});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.wifi_tethering_rounded, size: 20, color: colorScheme.primary),
              const SizedBox(width: 8),
              Text(t.qrPairing.display.hotspotPanelTitle, style: Theme.of(context).textTheme.titleSmall),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            t.qrPairing.display.hotspotPanelInstructions,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
          if (ssid != null) ...[
            const SizedBox(height: 12),
            _HotspotInfoRow(label: t.qrPairing.display.hotspotSsidLabel, value: ssid!),
          ],
          if (passphrase != null) ...[
            const SizedBox(height: 6),
            _HotspotInfoRow(label: t.qrPairing.display.hotspotPasswordLabel, value: passphrase!),
          ],
        ],
      ),
    );
  }
}

class _HotspotInfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _HotspotInfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Text('$label: ', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
        Expanded(
          child: SelectableText(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

class _GlassCard extends StatelessWidget {
  final Widget child;

  const _GlassCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: colorScheme.outlineVariant,
            width: 1,
          ),
        ),
        child: child,
      ),
    );
  }
}

extension on Duration {
  /// Compact human-readable label ("5 min", "1 h", "32 s") for the TTL
  /// chips and the countdown. Kept locale-agnostic on purpose (no i18n
  /// plural rules needed for a small numeric badge).
  String get qrPairingLabel {
    if (inHours >= 1 && inMinutes % 60 == 0) {
      return '$inHours h';
    }
    if (inMinutes >= 1) {
      return '$inMinutes min';
    }
    return '$inSeconds s';
  }
}
