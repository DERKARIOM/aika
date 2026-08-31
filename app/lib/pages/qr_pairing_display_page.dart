import 'dart:async';

import 'package:flutter/material.dart';
import 'package:localsend_app/config/theme.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/qr_pairing_payload.dart';
import 'package:localsend_app/provider/device_info_provider.dart';
import 'package:localsend_app/widget/custom_basic_appbar.dart';
import 'package:localsend_app/widget/responsive_list_view.dart';
import 'package:localsend_isolates/constants.dart';
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
class QrPairingDisplayPage extends StatefulWidget {
  const QrPairingDisplayPage();

  @override
  State<QrPairingDisplayPage> createState() => _QrPairingDisplayPageState();
}

class _QrPairingDisplayPageState extends State<QrPairingDisplayPage> with Refena {
  Duration _ttl = qrPairingDefaultTtl;
  QrPairingPayload? _payload;
  Timer? _tickTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _regenerate());
    // Refreshes the countdown label every second and auto-expires the code.
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    super.dispose();
  }

  void _regenerate() {
    final device = ref.read(deviceFullInfoProvider);
    if (device.ip == null || device.ip == '-' || device.port <= 0) {
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
    if (payload != null && (currentInfo.ip != payload.ip || currentInfo.port != payload.port || currentInfo.https != payload.https)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _regenerate());
    }

    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: basicLocalSendAppbar(t.qrPairing.display.title),
      body: SafeArea(
        child: ResponsiveListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          children: [
            if (payload == null) ...[
              const SizedBox(height: 40),
              Icon(Icons.wifi_off_rounded, size: 48, color: colorScheme.warning),
              const SizedBox(height: 16),
              Text(
                t.qrPairing.display.offline,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ] else ...[
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
            ],
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
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
