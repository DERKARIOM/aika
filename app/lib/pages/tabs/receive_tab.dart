import 'dart:async';

import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/qr_pairing_payload.dart';
import 'package:localsend_app/pages/qr_pairing_display_page.dart';
import 'package:localsend_app/pages/receive_history_page.dart';
import 'package:localsend_app/pages/tabs/receive_tab_vm.dart';
import 'package:localsend_app/provider/animation_provider.dart';
import 'package:localsend_app/provider/device_info_provider.dart';
import 'package:localsend_app/util/ip_helper.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_isolates/constants.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

/// Local strings of this screen (French + English fallback), following the
/// same approach as `web_send_page.dart` until they move to the Slang files.
String _t({required String fr, required String en}) {
  return LocaleSettings.currentLocale == AppLocale.fr ? fr : en;
}

/// The "Recevoir" tab: this device's QR code, front and center.
///
/// The QR code is the exact same Smart QR pairing code as the
/// "Mon QR Code" page ([QrPairingPayload], scanned by [QrPairingScannerPage]
/// on the other device): alias, local IP, port, protocol and certificate
/// fingerprint, valid for a short time. Here it is renewed automatically
/// before it expires and whenever the network or server settings change, so
/// the code shown is always scannable.
class ReceiveTab extends StatelessWidget {
  const ReceiveTab();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch(receiveTabVmProvider);

    return Stack(
      children: [
        // Makes the top part draggable on macOS (no native title bar).
        if (checkPlatform([TargetPlatform.macOS])) SizedBox(height: 50, child: MoveWindow()),
        SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                children: [
                  const _Header(),
                  const SizedBox(height: 20),
                  _MyQrCard(vm: vm),
                  const SizedBox(height: 16),
                  _ShareLinkCard(onTap: () async => vm.onCreateShareLink(context)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t.receiveTab.title,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
              ),
              const SizedBox(height: 4),
              Text(
                _t(
                  fr: 'Scannez ce code QR pour vous connecter à mon appareil',
                  en: 'Scan this QR code to connect to my device',
                ),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          tooltip: _t(fr: 'Historique', en: 'History'),
          onPressed: () async => context.push(() => const ReceiveHistoryPage()),
          icon: const Icon(Icons.history_rounded),
        ),
      ],
    );
  }
}

/// The QR code card: readiness, the code itself, this device's identity and
/// local network details.
class _MyQrCard extends StatefulWidget {
  final ReceiveTabVm vm;

  const _MyQrCard({required this.vm});

  @override
  State<_MyQrCard> createState() => _MyQrCardState();
}

class _MyQrCardState extends State<_MyQrCard> with Refena {
  /// A code is renewed this long before it expires, so the one on screen is
  /// always valid for at least this long when someone scans it.
  static const _renewMargin = Duration(seconds: 30);

  QrPairingPayload? _payload;
  Timer? _renewTimer;

  @override
  void dispose() {
    _renewTimer?.cancel();
    super.dispose();
  }

  static bool _hasUsableIp(Device device) {
    return device.ip != null && device.ip != '-' && device.port > 0;
  }

  /// Returns a valid code for [device], generating a new one when there is
  /// none yet, when it is about to expire, or when anything it encodes
  /// changed (IP, port, encryption, alias, certificate).
  QrPairingPayload? _currentPayload(Device device) {
    if (!widget.vm.isReceiving || !_hasUsableIp(device)) {
      _renewTimer?.cancel();
      _payload = null;
      return null;
    }

    final current = _payload;
    final upToDate =
        current != null &&
        current.ip == device.ip &&
        current.port == device.port &&
        current.https == device.https &&
        current.alias == device.alias &&
        current.fingerprint == device.fingerprint &&
        current.remaining > _renewMargin;
    if (upToDate) {
      return current;
    }

    // Same payload as the "Mon QR Code" page (regular network: no hotspot
    // credentials), so the existing scanner accepts it unchanged.
    final payload = QrPairingPayload.generate(
      protocolVersion: protocolVersion,
      alias: device.alias,
      deviceModel: device.deviceModel,
      deviceType: device.deviceType,
      ip: device.ip!,
      port: device.port,
      https: device.https,
      fingerprint: device.fingerprint,
    );
    _payload = payload;

    // One timer per code (every few minutes): no periodic polling.
    _renewTimer?.cancel();
    _renewTimer = Timer(payload.remaining - _renewMargin, () {
      if (mounted) {
        setState(() {});
      }
    });
    return payload;
  }

  @override
  Widget build(BuildContext context) {
    final device = ref.watch(deviceFullInfoProvider);
    final animations = ref.watch(animationProvider);
    final payload = _currentPayload(device);
    final colorScheme = Theme.of(context).colorScheme;
    final vm = widget.vm;

    final _ReadyState readyState = !vm.isReceiving
        ? _ReadyState.offline
        : payload == null
        ? _ReadyState.noNetwork
        : _ReadyState.ready;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _StatusPill(state: readyState),
              const Spacer(),
              if (payload != null)
                IconButton(
                  tooltip: _t(fr: 'Agrandir', en: 'Enlarge'),
                  onPressed: () async => _showFullScreen(context, payload),
                  icon: const Icon(Icons.open_in_full_rounded, size: 20),
                ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final size = (constraints.maxWidth - 40).clamp(180.0, 280.0).toDouble();
              return AnimatedSwitcher(
                duration: animations ? const Duration(milliseconds: 300) : Duration.zero,
                child: payload != null
                    ? GestureDetector(
                        key: ValueKey(payload.pairId),
                        onTap: () async => _showFullScreen(context, payload),
                        child: _QrImage(data: payload.encode(), size: size),
                      )
                    : _QrPlaceholder(key: ValueKey(readyState), state: readyState, size: size),
              );
            },
          ),
          const SizedBox(height: 18),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              vm.serverState?.alias ?? vm.aliasSettings,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          if (vm.isReceiving && vm.localIps.isNotEmpty) ...[
            const SizedBox(height: 8),
            _NetworkInfo(ips: vm.localIps, port: vm.serverState!.port, https: vm.serverState!.https),
          ],
          const SizedBox(height: 14),
          if (readyState == _ReadyState.ready)
            Text(
              _t(
                fr: 'Code sécurisé, renouvelé automatiquement toutes les ${qrPairingDefaultTtl.inMinutes} minutes.',
                en: 'Secure code, renewed automatically every ${qrPairingDefaultTtl.inMinutes} minutes.',
              ),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
            )
          else if (readyState == _ReadyState.noNetwork)
            FilledButton.tonalIcon(
              // Reuses the full network preparation flow (hotspot on
              // Android, guidance to the settings elsewhere).
              onPressed: () async => context.push(() => const QrPairingDisplayPage()),
              icon: const Icon(Icons.wifi_tethering_rounded),
              label: Text(_t(fr: 'Préparer la connexion', en: 'Prepare the connection')),
            )
          else
            Text(
              t.qrPairing.display.offline,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          if (readyState == _ReadyState.ready)
            TextButton(
              onPressed: () async => context.push(() => const QrPairingDisplayPage()),
              child: Text(_t(fr: 'Options du code QR', en: 'QR code options')),
            ),
        ],
      ),
    );
  }

  Future<void> _showFullScreen(BuildContext context, QrPairingPayload payload) async {
    await showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = constraints.maxWidth.clamp(200.0, 420.0).toDouble();
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _QrImage(data: payload.encode(), size: size),
                  const SizedBox(height: 14),
                  Text(payload.alias, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(
                    '${payload.ip}:${payload.port}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => context.pop(),
                    child: Text(t.general.close),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

enum _ReadyState { ready, noNetwork, offline }

class _StatusPill extends StatelessWidget {
  final _ReadyState state;

  const _StatusPill({required this.state});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final (label, color) = switch (state) {
      _ReadyState.ready => (_t(fr: 'Prêt à recevoir', en: 'Ready to receive'), colorScheme.primary),
      _ReadyState.noNetwork => (_t(fr: 'Aucun réseau local', en: 'No local network'), colorScheme.error),
      _ReadyState.offline => (t.general.offline, colorScheme.onSurfaceVariant),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13)),
        ],
      ),
    );
  }
}

/// The QR code itself, black on white with a quiet zone whatever the theme,
/// square modules and medium error correction: the pairing payload is dense
/// (≈ 360 bytes), and fewer, larger modules scan more reliably on phone
/// cameras than the rounded/high-correction style.
class _QrImage extends StatelessWidget {
  final String data;
  final double size;

  const _QrImage({required this.data, required this.size});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: _t(fr: 'Code QR de connexion à cet appareil', en: 'QR code to connect to this device'),
      image: true,
      child: Container(
        width: size,
        height: size,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: PrettyQrView.data(
          data: data,
          errorCorrectLevel: QrErrorCorrectLevel.M,
          decoration: const PrettyQrDecoration(
            shape: PrettyQrSmoothSymbol(
              roundFactor: 0,
              color: Colors.black,
            ),
          ),
        ),
      ),
    );
  }
}

class _QrPlaceholder extends StatelessWidget {
  final _ReadyState state;
  final double size;

  const _QrPlaceholder({super.key, required this.state, required this.size});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Icon(
        state == _ReadyState.noNetwork ? Icons.wifi_off_rounded : Icons.qr_code_2_rounded,
        size: 64,
        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
      ),
    );
  }
}

/// Local network details: short device ID(s) and the address to type in
/// "manual sending" when scanning is not possible.
class _NetworkInfo extends StatelessWidget {
  final List<String> ips;
  final int port;
  final bool https;

  const _NetworkInfo({required this.ips, required this.port, required this.https});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final ids = ips.map((ip) => ip.visualId).toSet();
    return Column(
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final id in ids)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: Text(
                  '#$id',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()]),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        SelectableText(
          '${ips.first}:$port${https ? '' : ' · HTTP'}',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// "Créer un lien de partage": creates a link and a QR code at once, for
/// devices without Aika, which open it in a browser to send files here.
class _ShareLinkCard extends StatelessWidget {
  final VoidCallback onTap;

  const _ShareLinkCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isFr = LocaleSettings.currentLocale == AppLocale.fr;
    final title = isFr ? 'Créer un lien de partage' : 'Create a share link';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.link_rounded, color: colorScheme.onPrimaryContainer),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text(
                      isFr
                          ? 'Si l’autre appareil n’a pas Aika : il scanne le code QR ou ouvre le lien dans son navigateur pour vous envoyer ses fichiers.'
                          : 'If the other device doesn’t have Aika: it scans the QR code or opens the link in a browser to send you its files.',
                      style: TextStyle(fontSize: 13, height: 1.4, color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: onTap,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            icon: const Icon(Icons.add_link_rounded),
            label: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}
