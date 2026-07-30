import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/qr_pairing_payload.dart';
import 'package:localsend_app/provider/device_info_provider.dart';
import 'package:localsend_app/provider/http_provider.dart';
import 'package:localsend_app/provider/last_devices.provider.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_app/util/qr_image_decoder.dart';
import 'package:localsend_app/widget/dialogs/error_dialog.dart';
import 'package:localsend_app/widget/dialogs/qr_pairing_confirm_dialog.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/rust/api/model.dart';
import 'package:localsend_isolates/util/rust.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

/// "Récepteur" screen of the Smart QR Code pairing feature.
///
/// Pops with the paired [Device] once the user has scanned (or imported) a
/// valid, non-expired QR code, the target device has been reached and
/// confirmed the pairing, or `null` if the user cancelled.
///
/// On platforms with a supported live camera backend
/// ([checkPlatformHasLiveQrScanner]), a full-screen camera preview is shown.
/// Everywhere else (currently Windows and Linux, where no maintained
/// Flutter plugin exposes live camera scanning), only the "import an image"
/// fallback is offered.
class QrPairingScannerPage extends StatefulWidget with PopsWithResult<Device> {
  const QrPairingScannerPage();

  @override
  State<QrPairingScannerPage> createState() => _QrPairingScannerPageState();
}

class _QrPairingScannerPageState extends State<QrPairingScannerPage> with Refena {
  MobileScannerController? _controller;
  bool _busy = false;
  String? _statusText;

  @override
  void initState() {
    super.initState();
    if (checkPlatformHasLiveQrScanner()) {
      _controller = MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    final raw = capture.barcodes.firstOrNullRawValue;
    if (raw == null) {
      return;
    }
    await _handleScannedText(raw);
  }

  Future<void> _importFromImage() async {
    final raw = await pickAndDecodeQrFromImage();
    if (raw == null) {
      if (mounted) {
        setState(() => _statusText = t.qrPairing.scan.notFoundInImage);
      }
      return;
    }
    await _handleScannedText(raw);
  }

  Future<void> _handleScannedText(String raw) async {
    if (_busy || !mounted) {
      return;
    }
    setState(() {
      _busy = true;
      _statusText = null;
    });
    await _controller?.stop();

    final decodeResult = QrPairingPayload.tryDecode(raw);
    if (!decodeResult.isSuccess) {
      await _resumeWithError(_errorLabel(decodeResult.error!));
      return;
    }

    final payload = decodeResult.payload!;
    await HapticFeedback.mediumImpact();

    Device? resolvedDevice;
    Object? connectionError;
    try {
      final selfInfo = ref.read(deviceFullInfoProvider);
      final response = await ref
          .read(httpProvider)
          .v2
          .register(
            protocol: payload.https ? ProtocolType.https : ProtocolType.http,
            ip: payload.ip,
            port: payload.port,
            payload: selfInfo.toRegisterDto(),
          );
      resolvedDevice = response.body.toDevice(payload.ip, payload.port, payload.https, HttpDiscovery(ip: payload.ip));
    } catch (e) {
      connectionError = e;
    }

    if (!mounted) {
      return;
    }

    if (resolvedDevice == null) {
      await _resumeWithError(t.qrPairing.scan.unreachable);
      if (connectionError != null && mounted) {
        // Offer details on demand instead of dumping a raw exception on the scan screen.
        unawaited(
          showDialog(
            context: context,
            builder: (_) => ErrorDialog(error: connectionError.toString()),
          ),
        );
      }
      return;
    }

    // The fingerprint returned by the *live* handshake is the actual trust
    // anchor (see [QrPairingPayload] doc). If it does not match what the QR
    // code claimed, the device that answered is not the one that generated
    // the code: never silently trust it, but let the user make the final
    // call with a clear warning (e.g. legitimate cert rotation vs. spoofing).
    final fingerprintMismatch = resolvedDevice.fingerprint != payload.fingerprint;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => QrPairingConfirmDialog(
        device: resolvedDevice!,
        fingerprintMismatch: fingerprintMismatch,
      ),
    );

    if (!mounted) {
      return;
    }

    if (confirmed == true) {
      ref.redux(lastDevicesProvider).dispatch(AddLastDeviceAction(resolvedDevice));
      widget.popWithResult(context, resolvedDevice);
      return;
    }

    setState(() => _busy = false);
    await _controller?.start();
  }

  Future<void> _resumeWithError(String message) async {
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      _statusText = message;
    });
    await _controller?.start();
  }

  String _errorLabel(QrPairingError error) {
    switch (error) {
      case QrPairingError.expired:
        return t.qrPairing.scan.errorExpired;
      case QrPairingError.unsupportedVersion:
        return t.qrPairing.scan.errorUnsupportedVersion;
      case QrPairingError.malformed:
        return t.qrPairing.scan.errorMalformed;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasLiveScanner = _controller != null;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (hasLiveScanner)
            MobileScanner(
              controller: _controller,
              onDetect: _onDetect,
              errorBuilder: (context, error) => _CameraError(error: error),
            )
          else
            const ColoredBox(color: Colors.black),
          if (hasLiveScanner) const _ScannerOverlay(),
          SafeArea(
            child: Column(
              children: [
                _TopBar(onTorchTap: hasLiveScanner ? () => _controller!.toggleTorch() : null),
                const Spacer(),
                if (_statusText != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    child: _StatusBanner(text: _statusText!),
                  ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 40, top: 10),
                  child: Column(
                    children: [
                      if (!hasLiveScanner) ...[
                        const Icon(Icons.desktop_windows_outlined, color: Colors.white70, size: 40),
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Text(
                            t.qrPairing.scan.noCameraOnPlatform,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ),
                        const SizedBox(height: 20),
                      ] else
                        Text(
                          t.qrPairing.scan.hint,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      const SizedBox(height: 16),
                      FilledButton.tonalIcon(
                        onPressed: _busy ? null : _importFromImage,
                        icon: const Icon(Icons.image_outlined),
                        label: Text(t.qrPairing.scan.importImage),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_busy)
            const ColoredBox(
              color: Colors.black45,
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final VoidCallback? onTorchTap;

  const _TopBar({required this.onTorchTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => context.pop(),
          ),
          const Spacer(),
          Text(t.qrPairing.scan.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          const Spacer(),
          if (onTorchTap != null)
            IconButton(
              icon: const Icon(Icons.flash_on_outlined, color: Colors.white),
              onPressed: onTorchTap,
            )
          else
            const SizedBox(width: 48),
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final String text;

  const _StatusBanner({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24),
      ),
      child: Text(text, style: const TextStyle(color: Colors.white), textAlign: TextAlign.center),
    );
  }
}

class _CameraError extends StatelessWidget {
  final MobileScannerException error;

  const _CameraError({required this.error});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography_outlined, color: Colors.white70, size: 40),
              const SizedBox(height: 12),
              Text(
                t.qrPairing.scan.cameraUnavailable,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Rounded scan-window overlay. Purely decorative (mobile_scanner still
/// scans the whole frame): it gives the classic "aim here" affordance
/// without restricting detection to an exact rectangle, which would make
/// scanning slower/less reliable on lower-end devices.
class _ScannerOverlay extends StatelessWidget {
  const _ScannerOverlay();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: AspectRatio(
          aspectRatio: 1,
          child: FractionallySizedBox(
            widthFactor: 0.72,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Colors.white.withValues(alpha: 0.85), width: 3),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

extension on List<Barcode> {
  String? get firstOrNullRawValue {
    for (final barcode in this) {
      final value = barcode.rawValue;
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }
}
