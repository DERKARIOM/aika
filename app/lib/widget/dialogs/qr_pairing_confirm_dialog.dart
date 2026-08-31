import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/util/device_type_ext.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:routerino/routerino.dart';

/// Confirmation step shown after a QR pairing code has been scanned,
/// decoded and successfully verified against the live device at the
/// claimed address.
///
/// This is the explicit user confirmation required before a pairing is
/// established (a scan can be accidental, e.g. through a chat screenshot).
/// If [fingerprintMismatch] is true, the certificate presented by the
/// device that answered does NOT match the one encoded in the QR code:
/// the dialog makes this very clear and defaults to the safer choice.
class QrPairingConfirmDialog extends StatelessWidget {
  final Device device;
  final bool fingerprintMismatch;

  const QrPairingConfirmDialog({
    required this.device,
    required this.fingerprintMismatch,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      icon: Icon(
        fingerprintMismatch ? Icons.gpp_bad_outlined : Icons.gpp_good_outlined,
        color: fingerprintMismatch ? colorScheme.error : colorScheme.primary,
        size: 36,
      ),
      title: Text(t.qrPairing.confirm.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(child: Icon(device.deviceType.icon)),
            title: Text(device.alias, style: Theme.of(context).textTheme.titleMedium),
            subtitle: Text([if (device.deviceModel != null) device.deviceModel!, '${device.ip}:${device.port}'].join(' · ')),
          ),
          const SizedBox(height: 8),
          if (fingerprintMismatch) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded, color: colorScheme.error, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      t.qrPairing.confirm.fingerprintMismatch,
                      style: TextStyle(color: colorScheme.onErrorContainer),
                    ),
                  ),
                ],
              ),
            ),
          ] else
            Text(
              t.qrPairing.confirm.description,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => context.pop(false),
          child: Text(t.general.cancel),
        ),
        FilledButton(
          style: fingerprintMismatch ? FilledButton.styleFrom(backgroundColor: colorScheme.error) : null,
          onPressed: () => context.pop(true),
          child: Text(fingerprintMismatch ? t.qrPairing.confirm.connectAnyway : t.qrPairing.confirm.connect),
        ),
      ],
    );
  }
}
