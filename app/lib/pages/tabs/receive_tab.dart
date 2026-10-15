import 'dart:async';

import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/qr_pairing_payload.dart';
import 'package:localsend_app/pages/link_download_page.dart';
import 'package:localsend_app/pages/qr_pairing_display_page.dart';
import 'package:localsend_app/pages/receive_history_page.dart';
import 'package:localsend_app/pages/send_files_page.dart';
import 'package:localsend_app/pages/tabs/receive_tab_vm.dart';
import 'package:localsend_app/provider/animation_provider.dart';
import 'package:localsend_app/provider/device_info_provider.dart';
import 'package:localsend_app/provider/selection/selected_sending_files_provider.dart';
import 'package:localsend_app/util/ip_helper.dart';
import 'package:localsend_app/util/native/file_picker.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_app/util/native/storage_info.dart';
import 'package:localsend_app/widget/dialogs/custom_bottom_sheet.dart';
import 'package:localsend_app/widget/dialogs/send_target_sheet.dart';
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

/// The "Recevoir" tab: a compact personal dashboard.
///
/// From top to bottom: the real state of the receive server, this device's
/// QR code and name, the free space of its storage, then the two ways to
/// share (send files, or a share link for devices without Aika).
///
/// The QR code is the exact same Smart QR pairing code as the
/// "Mon QR Code" page ([QrPairingPayload], scanned by [QrPairingScannerPage]
/// on the other device): alias, local IP, port, protocol and certificate
/// fingerprint, valid for a short time. Here it is renewed automatically
/// before it expires and whenever the network or server settings change, so
/// the code shown is always scannable.
class ReceiveTab extends StatefulWidget {
  const ReceiveTab();

  @override
  State<ReceiveTab> createState() => _ReceiveTabState();
}

class _ReceiveTabState extends State<ReceiveTab> with Refena {
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
  QrPairingPayload? _currentPayload(ReceiveTabVm vm, Device device) {
    if (!vm.isReceiving || !_hasUsableIp(device)) {
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
    final vm = context.watch(receiveTabVmProvider);
    final device = ref.watch(deviceFullInfoProvider);
    final payload = _currentPayload(vm, device);

    final _ReadyState state = !vm.isReceiving
        ? _ReadyState.offline
        : payload == null
        ? _ReadyState.noNetwork
        : vm.isSharingLink
        ? _ReadyState.sharing
        : _ReadyState.ready;

    return Stack(
      children: [
        // Makes the top part draggable on macOS (no native title bar).
        if (checkPlatform([TargetPlatform.macOS])) SizedBox(height: 50, child: MoveWindow()),
        SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final qrSize = _qrSizeFor(context, constraints);
                  // Everything fits on one screen on usual phones; very
                  // small screens or large text scroll instead of overflowing.
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Header(state: state),
                        const SizedBox(height: 12),
                        _QrCard(vm: vm, payload: payload, state: state, qrSize: qrSize),
                        const SizedBox(height: 10),
                        _StorageCard(destination: vm.destination, receiving: vm.isReceivingSession),
                        const SizedBox(height: 12),
                        _Actions(onCreateShareLink: () async => vm.onCreateShareLink(context)),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// The QR code takes the height the rest of the page leaves, between a
  /// size phone cameras still read reliably for this dense code (~2.5 px per
  /// module) and a comfortable maximum.
  static double _qrSizeFor(BuildContext context, BoxConstraints constraints) {
    const minSize = 180.0;
    const maxSize = 240.0;
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    // Height of everything but the QR code: paddings, icons and buttons
    // (fixed) plus the text lines (grow with the system text size).
    final rest = 348 + 158 * textScale;
    final byHeight = constraints.maxHeight.isFinite ? constraints.maxHeight - rest : maxSize;
    final byWidth = constraints.maxWidth - 2 * 16 - 2 * 14;
    return byHeight.clamp(minSize, maxSize).clamp(minSize, byWidth.clamp(minSize, maxSize)).toDouble();
  }
}

/// Corner radius of every element of the page.
const _radius = 10.0;
const _shape = RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(_radius)));

/// What the status pill and the QR card show. Always derived from the real
/// server and network state, never set by hand.
enum _ReadyState {
  /// Server running, local network available: the QR code is scannable.
  ready,

  /// Same, and a web share link is open (the server also answers browsers).
  sharing,

  /// Server running but no usable local IP (no Wi-Fi / hotspot).
  noNetwork,

  /// Receive server stopped.
  offline,
}

class _Header extends StatelessWidget {
  final _ReadyState state;

  const _Header({required this.state});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                t.receiveTab.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: _StatusPill(state: state),
              ),
            ),
            const Spacer(),
            IconButton.filledTonal(
              tooltip: _t(fr: 'Historique', en: 'History'),
              style: IconButton.styleFrom(shape: _shape),
              onPressed: () async => context.push(() => const ReceiveHistoryPage()),
              icon: const Icon(Icons.history_rounded),
            ),
          ],
        ),
        Text(
          _t(fr: 'Partagez avec vos autres appareils', en: 'Share with your other devices'),
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  final _ReadyState state;

  const _StatusPill({required this.state});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final animations = context.watch(animationProvider);
    final (label, color) = switch (state) {
      _ReadyState.ready => (_t(fr: 'Prêt à recevoir', en: 'Ready to receive'), colorScheme.primary),
      _ReadyState.sharing => (_t(fr: 'Serveur de partage actif', en: 'Share server active'), colorScheme.primary),
      _ReadyState.noNetwork => (_t(fr: 'Connexion indisponible', en: 'Connection unavailable'), colorScheme.error),
      _ReadyState.offline => (t.general.offline, colorScheme.onSurfaceVariant),
    };
    return Semantics(
      liveRegion: true,
      child: AnimatedSwitcher(
        duration: animations ? const Duration(milliseconds: 250) : Duration.zero,
        child: Container(
          key: ValueKey(state),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(_radius),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 7),
              Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12.5)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Rounded card used by every block of the page.
class _Card extends StatelessWidget {
  final EdgeInsetsGeometry padding;
  final Widget child;

  const _Card({required this.child, this.padding = const EdgeInsets.all(14)});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(_radius),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: child,
    );
  }
}

/// "Votre QR Code": the code, this device's character name and short ID.
class _QrCard extends StatelessWidget {
  final ReceiveTabVm vm;
  final QrPairingPayload? payload;
  final _ReadyState state;
  final double qrSize;

  const _QrCard({required this.vm, required this.payload, required this.state, required this.qrSize});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final animations = context.watch(animationProvider);
    final payload = this.payload;
    final ids = vm.isReceiving ? vm.localIps.map((ip) => ip.visualId).toSet() : const <String>{};

    return _Card(
      padding: const EdgeInsets.fromLTRB(14, 2, 4, 12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _t(fr: 'Votre QR Code', en: 'Your QR code'),
                  style: theme.textTheme.titleSmall?.copyWith(color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: _t(fr: 'Options du code QR', en: 'QR code options'),
                style: IconButton.styleFrom(shape: _shape),
                onPressed: () async => context.push(() => const QrPairingDisplayPage()),
                icon: const Icon(Icons.tune_rounded, size: 20),
              ),
              if (payload != null)
                IconButton(
                  tooltip: _t(fr: 'Agrandir le QR Code', en: 'Enlarge the QR code'),
                  style: IconButton.styleFrom(shape: _shape),
                  onPressed: () async => _showFullScreen(context, payload),
                  icon: const Icon(Icons.open_in_full_rounded, size: 20),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Column(
              children: [
                AnimatedSwitcher(
                  duration: animations ? const Duration(milliseconds: 300) : Duration.zero,
                  child: payload != null
                      ? GestureDetector(
                          key: ValueKey(payload.pairId),
                          onTap: () async => _showFullScreen(context, payload),
                          child: _QrImage(data: payload.encode(), size: qrSize),
                        )
                      : _QrPlaceholder(key: ValueKey(state), state: state, size: qrSize),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        vm.serverState?.alias ?? vm.aliasSettings,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    for (final id in ids) ...[
                      const SizedBox(width: 8),
                      _IdChip(id: id),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                if (state == _ReadyState.noNetwork)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(shape: _shape),
                      // Reuses the full network preparation flow (hotspot on
                      // Android, guidance to the settings elsewhere).
                      onPressed: () async => context.push(() => const QrPairingDisplayPage()),
                      icon: const Icon(Icons.wifi_tethering_rounded),
                      label: Text(_t(fr: 'Préparer la connexion', en: 'Prepare the connection')),
                    ),
                  )
                else
                  Text(
                    state == _ReadyState.offline
                        ? t.qrPairing.display.offline
                        : _t(fr: 'Scannez pour vous connecter', en: 'Scan to connect'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showFullScreen(BuildContext context, QrPairingPayload payload) async {
    await showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: _shape,
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
                    _t(
                      fr: 'Code sécurisé, renouvelé automatiquement toutes les ${qrPairingDefaultTtl.inMinutes} minutes.',
                      en: 'Secure code, renewed automatically every ${qrPairingDefaultTtl.inMinutes} minutes.',
                    ),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
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

/// Short device ID (end of the local IP), as on the other devices' lists.
class _IdChip extends StatelessWidget {
  final String id;

  const _IdChip({required this.id});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_radius),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Text(
        '#$id',
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 13,
          color: colorScheme.onSurfaceVariant,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
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
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(_radius),
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
    final noNetwork = state == _ReadyState.noNetwork;
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(_radius),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            noNetwork ? Icons.wifi_off_rounded : Icons.qr_code_2_rounded,
            size: 48,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
          ),
          if (noNetwork) ...[
            const SizedBox(height: 10),
            Text(
              _t(fr: 'Aucun réseau local détecté', en: 'No local network detected'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

/// "Stockage de l'appareil": real free / used / total space of the volume
/// received files go to. Hidden when the platform cannot report it reliably.
class _StorageCard extends StatefulWidget {
  final String? destination;

  /// A transfer is being received: the space is read again when it ends.
  final bool receiving;

  const _StorageCard({required this.destination, required this.receiving});

  @override
  State<_StorageCard> createState() => _StorageCardState();
}

class _StorageCardState extends State<_StorageCard> with WidgetsBindingObserver {
  StorageInfo? _info;
  bool _loaded = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didUpdateWidget(_StorageCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final transferEnded = oldWidget.receiving && !widget.receiving;
    if (transferEnded || oldWidget.destination != widget.destination) {
      unawaited(_load());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Files may have been added or deleted while Aika was in the background.
    if (state == AppLifecycleState.resumed) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final info = await readStorageInfo(destination: widget.destination);
    if (mounted && generation == _generation) {
      setState(() {
        _info = info;
        _loaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    final animations = context.watch(animationProvider);
    return AnimatedSize(
      duration: animations ? const Duration(milliseconds: 250) : Duration.zero,
      alignment: Alignment.topCenter,
      child: !_loaded || info == null ? const SizedBox(width: double.infinity) : _StorageContent(info: info),
    );
  }
}

class _StorageContent extends StatelessWidget {
  final StorageInfo info;

  const _StorageContent({required this.info});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final total = info.totalBytes;
    final used = info.usedBytes;
    final fraction = info.usedFraction;
    final free = _t(fr: '${formatStorageSize(info.freeBytes)} libres', en: '${formatStorageSize(info.freeBytes)} free');

    return _Card(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(_radius),
                ),
                child: Icon(Icons.sd_storage_outlined, size: 16, color: colorScheme.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _t(fr: 'Stockage de l’appareil', en: 'Device storage'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Text(free, style: TextStyle(fontWeight: FontWeight.w800, color: colorScheme.primary)),
            ],
          ),
          if (fraction != null && total != null && used != null) ...[
            const SizedBox(height: 8),
            Semantics(
              label: _t(fr: 'Stockage utilisé', en: 'Storage used'),
              value: '${(fraction * 100).round()} %',
              child: ClipRRect(
                borderRadius: BorderRadius.circular(_radius),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: fraction),
                  duration: context.watch(animationProvider) ? const Duration(milliseconds: 600) : Duration.zero,
                  curve: Curves.easeOutCubic,
                  builder: (context, value, _) => LinearProgressIndicator(
                    value: value,
                    minHeight: 6,
                    backgroundColor: colorScheme.onSurface.withValues(alpha: 0.08),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _t(
                fr: '${formatStorageSize(used)} utilisés sur ${formatStorageSize(total)}',
                en: '${formatStorageSize(used)} used of ${formatStorageSize(total)}',
              ),
              style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

/// Bytes as "86 Go" / "4,2 Go" / "512 Mo" (French) or "86 GB" (English).
/// Decimal units, as phones and file managers display storage.
@visibleForTesting
String formatStorageSize(int bytes) {
  final fr = LocaleSettings.currentLocale == AppLocale.fr;
  const units = [('o', 'B'), ('Ko', 'KB'), ('Mo', 'MB'), ('Go', 'GB'), ('To', 'TB')];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1000 && unit < units.length - 1) {
    value /= 1000;
    unit++;
  }
  var text = value >= 100 || unit == 0 ? value.round().toString() : value.toStringAsFixed(1);
  if (text.endsWith('.0')) {
    text = text.substring(0, text.length - 2);
  }
  if (fr) {
    text = text.replaceAll('.', ',');
  }
  final (frUnit, enUnit) = units[unit];
  return '$text ${fr ? frUnit : enUnit}';
}

/// Quick actions: send, share link, download from a link.
class _Actions extends StatelessWidget {
  final Future<void> Function() onCreateShareLink;

  const _Actions({required this.onCreateShareLink});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: () async => _sendFiles(context),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
            shape: _shape,
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          icon: const Icon(Icons.send_rounded),
          label: Text(_t(fr: 'Envoyer des fichiers', en: 'Send files')),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: onCreateShareLink,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            shape: _shape,
            textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          icon: const Icon(Icons.link_rounded),
          label: Text(_t(fr: 'Créer un lien de partage', en: 'Create a share link')),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () async => context.push(() => const LinkDownloadPage()),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            shape: _shape,
            textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          icon: const Icon(Icons.download_rounded),
          label: Text(_t(fr: 'Télécharger depuis un lien', en: 'Download from a link')),
        ),
      ],
    );
  }

  /// Same pickers as the Send tab; once something is selected, a second
  /// sheet lists the nearby devices (and the QR scanner) so the transfer
  /// starts from here, without opening the Send tab.
  Future<void> _sendFiles(BuildContext context) async {
    final option = await context.pushBottomSheet(() => const _SendSourceSheet());
    if (option == _moreOptions && context.mounted) {
      await context.push(() => const SendFilesPage());
      return;
    }
    if (option is! FilePickerOption || !context.mounted) {
      return;
    }
    final ref = context.ref;
    final before = ref.read(selectedSendingFilesProvider).length;
    await ref.global.dispatchAsync(PickFileAction(option: option, context: context));
    if (!context.mounted || ref.read(selectedSendingFilesProvider).length <= before) {
      return;
    }
    await pickTargetAndSend(context);
  }
}

/// Bottom sheet listing what can be sent, in the platform's usual order.
/// Pops with the chosen [FilePickerOption], or nothing when dismissed.
/// Popped by [_SendSourceSheet] for the full send screen.
const _moreOptions = 'more-options';

class _SendSourceSheet extends StatelessWidget {
  const _SendSourceSheet();

  @override
  Widget build(BuildContext context) {
    final options = FilePickerOption.getOptionsForPlatform();
    return CustomBottomSheet(
      title: _t(fr: 'Envoyer…', en: 'Send…'),
      description: _t(
        fr: 'Choisissez ce que vous voulez envoyer, puis l’appareil destinataire.',
        en: 'Choose what to send, then the receiving device.',
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Fixed-height tiles, two per row: the height never depends on
          // the width, so the sheet fits on wide desktop windows too.
          const spacing = 10.0;
          final tileWidth = (constraints.maxWidth - spacing) / 2;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  for (final option in options)
                    SizedBox(
                      width: tileWidth,
                      height: 64,
                      child: _SourceTile(option: option),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              TextButton.icon(
                onPressed: () => context.pop(_moreOptions),
                icon: const Icon(Icons.tune_rounded),
                label: Text(_t(fr: 'Plus d’options d’envoi', en: 'More sending options')),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  final FilePickerOption option;

  const _SourceTile({required this.option});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_radius),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.pop(option),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Icon(option.icon, color: colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  option.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
