import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/pages/qr_pairing_scanner_page.dart';
import 'package:localsend_app/pages/send_files_page.dart';
import 'package:localsend_app/provider/animation_provider.dart';
import 'package:localsend_app/provider/favorites_provider.dart';
import 'package:localsend_app/provider/network/nearby_devices_provider.dart';
import 'package:localsend_app/provider/network/scan_facade.dart';
import 'package:localsend_app/provider/network/send_provider.dart';
import 'package:localsend_app/provider/selection/selected_sending_files_provider.dart';
import 'package:localsend_app/util/favorites.dart';
import 'package:localsend_app/util/file_size_helper.dart';
import 'package:localsend_app/widget/custom_icon_button.dart';
import 'package:localsend_app/widget/dialogs/custom_bottom_sheet.dart';
import 'package:localsend_app/widget/list_tile/custom_list_tile.dart';
import 'package:localsend_app/widget/list_tile/device_list_tile.dart';
import 'package:localsend_app/widget/list_tile/device_placeholder_list_tile.dart';
import 'package:localsend_app/widget/rotating_widget.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

String _t({required String fr, required String en}) => LocaleSettings.currentLocale == AppLocale.fr ? fr : en;

/// Popped by [SendTargetSheet] when the user wants to scan a QR code.
const _scanQr = 'scan-qr';

/// Popped by [SendTargetSheet] for the full send screen.
const _moreOptions = 'more-options';

/// Asks where to send the current selection ([selectedSendingFilesProvider])
/// and starts sending, without going through the Send tab:
/// - a nearby device → sent right away;
/// - "Scanner le code QR" → QR pairing scanner, then sent to that device.
///
/// Does nothing when the sheet is dismissed (the selection stays available
/// on the Send tab).
Future<void> pickTargetAndSend(BuildContext context) async {
  final result = await context.pushBottomSheet(() => const SendTargetSheet());
  if (!context.mounted) {
    return;
  }

  final Device? target;
  if (result is Device) {
    target = result;
  } else if (result == _moreOptions) {
    // Full send screen: same selection, more options (text, edit…).
    await context.push(() => const SendFilesPage());
    return;
  } else if (result == _scanQr) {
    // The scanner records the paired device itself (AddLastDeviceAction).
    target = await context.pushWithResult<Device, QrPairingScannerPage>(() => const QrPairingScannerPage());
  } else {
    return;
  }

  if (target == null || !context.mounted) {
    return;
  }
  final ref = context.ref;
  final files = ref.read(selectedSendingFilesProvider);
  if (files.isEmpty) {
    return;
  }
  await ref.notifier(sendProvider).startSession(target: target, files: files, background: false);
}

/// Bottom sheet listing the nearby devices (same discovery as the Send tab)
/// plus a QR-code shortcut. Pops with the chosen [Device] or [_scanQr].
class SendTargetSheet extends StatefulWidget {
  const SendTargetSheet();

  @override
  State<SendTargetSheet> createState() => _SendTargetSheetState();
}

class _SendTargetSheetState extends State<SendTargetSheet> {
  @override
  void initState() {
    super.initState();
    SendScreenVisibility.enter();
    // Same as the Send tab: only scan when nothing is known yet, so opening
    // the sheet stays instant and does not flood the network.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }
      final ref = context.ref;
      if (ref.read(nearbyDevicesProvider).devices.isEmpty) {
        await ref.global.dispatchAsync(StartSmartScan(forceLegacy: false));
      }
    });
  }

  @override
  void dispose() {
    SendScreenVisibility.leave();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ref = context.ref;
    final files = ref.watch(selectedSendingFilesProvider);
    final devices = ref.watch(nearbyDevicesProvider.select((s) => s.allDevices)).values;
    final favorites = ref.watch(favoritesProvider);
    final size = files.fold<int>(0, (sum, f) => sum + f.size).asReadableFileSize;

    return CustomBottomSheet(
      title: _t(fr: 'Envoyer à…', en: 'Send to…'),
      description: _t(
        fr: '${files.length} fichier${files.length > 1 ? 's' : ''} · $size',
        en: '${files.length} file${files.length > 1 ? 's' : ''} · $size',
      ),
      child: ConstrainedBox(
        // The list scrolls inside the sheet instead of pushing it off screen.
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.55),
        child: ListView(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          children: [
            CustomListTile(
              glass: true,
              onTap: () => context.pop(_scanQr),
              icon: const Icon(Icons.qr_code_scanner_rounded, size: 46),
              title: Text(
                _t(fr: 'Scanner le code QR', en: 'Scan the QR code'),
                style: const TextStyle(fontSize: 20),
              ),
              subTitle: Text(
                _t(
                  fr: 'Code de l’onglet « Recevoir » de l’autre appareil',
                  en: 'Code on the other device’s “Receive” tab',
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              trailing: Icon(Icons.chevron_right_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            const _DevicesHeader(),
            const SizedBox(height: 8),
            if (devices.isEmpty)
              const Opacity(opacity: 0.3, child: DevicePlaceholderListTile())
            else
              for (final (device, favorite) in devices.map((d) => (d, favorites.findDevice(d))))
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: DeviceListTile(
                    device: device,
                    nameOverride: favorite?.alias,
                    isFavorite: favorite != null,
                    glass: true,
                    onTap: () => context.pop(device),
                  ),
                ),
            const SizedBox(height: 4),
            Center(
              child: TextButton.icon(
                onPressed: () => context.pop(_moreOptions),
                icon: const Icon(Icons.tune_rounded),
                label: Text(_t(fr: 'Plus d’options d’envoi', en: 'More sending options')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Appareils à proximité" + a refresh button that spins while scanning.
class _DevicesHeader extends StatelessWidget {
  const _DevicesHeader();

  @override
  Widget build(BuildContext context) {
    final ref = context.ref;
    final (scanningFavorites, scanningIps) = ref.watch(nearbyDevicesProvider.select((s) => (s.runningFavoriteScan, s.runningIps)));
    final animations = ref.watch(animationProvider);
    final scanning = scanningFavorites || scanningIps.isNotEmpty;

    return Row(
      children: [
        Expanded(
          child: Text(t.sendTab.nearbyDevices, style: Theme.of(context).textTheme.titleMedium),
        ),
        if (scanning && !animations)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Text(
              _t(fr: 'Recherche…', en: 'Searching…'),
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
        Tooltip(
          message: t.sendTab.scan,
          child: RotatingWidget(
            duration: const Duration(seconds: 2),
            spinning: scanning && animations,
            reverse: true,
            child: CustomIconButton(
              onPressed: () async {
                ref.redux(nearbyDevicesProvider).dispatch(ClearFoundDevicesAction());
                await ref.global.dispatchAsync(StartSmartScan(forceLegacy: true));
              },
              child: const Icon(Icons.sync),
            ),
          ),
        ),
      ],
    );
  }
}
