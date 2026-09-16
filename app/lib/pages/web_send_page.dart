import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:localsend_app/config/theme.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/cross_file.dart';
import 'package:localsend_app/model/state/send/web/web_send_session.dart';
import 'package:localsend_app/pages/qr_pairing_scanner_page.dart';
import 'package:localsend_app/provider/local_ip_provider.dart';
import 'package:localsend_app/provider/network/send_provider.dart';
import 'package:localsend_app/provider/network/server/server_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/util/file_size_helper.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_app/util/ui/snackbar.dart';
import 'package:localsend_app/widget/custom_basic_appbar.dart';
import 'package:localsend_app/widget/dialogs/pin_dialog.dart';
import 'package:localsend_app/widget/dialogs/qr_dialog.dart';
import 'package:localsend_app/widget/dialogs/zoom_dialog.dart';
import 'package:localsend_app/widget/file_thumbnail.dart';
import 'package:localsend_app/widget/responsive_list_view.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/util/sleep.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

enum _ServerState { initializing, running, error, stopping }

/// A handful of new UI strings introduced by this screen's redesign
/// (direct QR display, quick scan, network/file info cards) that have no
/// entry yet in the generated Slang translations. Regenerating
/// `gen/strings*.g.dart` requires a Flutter/Dart toolchain that wasn't
/// available when this was written, so these are kept local instead of
/// risking a hand-edit of generated code. Falls back to English for every
/// locale other than French, matching the app's fr/en source files.
String _t({required String fr, required String en}) {
  return LocaleSettings.currentLocale == AppLocale.fr ? fr : en;
}

class WebSendPage extends StatefulWidget {
  final List<CrossFile> files;

  const WebSendPage(this.files);

  @override
  State<WebSendPage> createState() => _WebSendPageState();
}

class _WebSendPageState extends State<WebSendPage> with Refena {
  _ServerState _stateEnum = _ServerState.initializing;
  bool _encrypted = false;
  String? _initializedError;

  // Session ids we've already queued a dialog for, so a rebuild never
  // re-queues the same incoming request twice.
  final Set<String> _notifiedSessionIds = {};
  final List<WebSendSession> _pendingRequestDialogQueue = [];
  bool _requestDialogOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _init(encrypted: false);
    });
  }

  void _init({required bool encrypted}) async {
    final settings = ref.read(settingsProvider);
    setState(() {
      _stateEnum = _ServerState.initializing;
      _encrypted = encrypted;
      _initializedError = null;
    });
    await sleepAsync(500);
    try {
      // The auto accept setting and the pin of a previous web send state are kept.
      await ref
          .notifier(serverProvider)
          .restartServerWithWebSend(
            alias: settings.alias,
            port: settings.port,
            https: _encrypted,
            files: widget.files,
          );
      setState(() {
        _stateEnum = _ServerState.running;
      });
    } catch (e) {
      if (context.mounted) {
        setState(() {
          _stateEnum = _ServerState.error;
          _initializedError = e.toString();
        });
      }
    }
  }

  /// Web share uses unencrypted http, so we need to revert to the previous state.
  Future<void> _revertServerState() async {
    await ref.notifier(serverProvider).restartServerFromSettings();
  }

  /// Called on every build with the current sessions: queues a dialog for
  /// any newly-pending request (an incoming request that hasn't been seen
  /// yet), so accepting/rejecting it happens through a dialog the moment it
  /// arrives, instead of the user having to notice and scroll to the
  /// "Requetes" list at the bottom of the page.
  void _handleIncomingRequests(Iterable<WebSendSession> sessions) {
    for (final session in sessions) {
      if (session.pending && _notifiedSessionIds.add(session.sessionId)) {
        _pendingRequestDialogQueue.add(session);
      }
    }
    _maybeShowNextRequestDialog();
  }

  void _maybeShowNextRequestDialog() {
    if (_requestDialogOpen || _pendingRequestDialogQueue.isEmpty || !mounted) {
      return;
    }
    final session = _pendingRequestDialogQueue.removeAt(0);
    _requestDialogOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        _requestDialogOpen = false;
        return;
      }
      final accepted = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _IncomingRequestDialog(session: session),
      );
      if (accepted == true) {
        ref.notifier(serverProvider).acceptWebSendRequest(session.sessionId);
      } else if (accepted == false) {
        ref.notifier(serverProvider).declineWebSendRequest(session.sessionId);
      }
      _requestDialogOpen = false;
      if (mounted) {
        _maybeShowNextRequestDialog();
      }
    });
  }

  /// Builds the plain and pin-carrying URLs for one local IP, exactly like
  /// the per-IP rows always have. Factored out so the new "quick access" QR
  /// (which needs the *same* recommended-IP link) never risks drifting from
  /// the per-IP cards below it.
  (String, String) _urlsFor(String ip, int port, String? pin) {
    final url = '${_encrypted ? 'https' : 'http'}://$ip:$port';
    final urlWithPin = pin == null ? url : '$url/?pin=${Uri.encodeQueryComponent(pin)}';
    return (url, urlWithPin);
  }

  Future<void> _copyUrl(BuildContext context, String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (context.mounted && checkPlatformIsDesktop()) {
      context.showSnackBar(t.general.copiedToClipboard);
    }
  }

  Future<void> _openUrl(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Future<void> _shareUrl(String url) async {
    // Text/URL sharing only: no native platform configuration required.
    await SharePlus.instance.share(ShareParams(text: url));
  }

  Future<void> _onTapScanQr(BuildContext context) async {
    // Reuses the exact same "Smart QR Code" pairing scanner already used
    // from the Send tab (camera framing UI, permission handling, and the
    // Windows/Linux "import an image" fallback are all handled there) —
    // no new camera integration is introduced by this screen.
    final device = await context.pushWithResult<Device, QrPairingScannerPage>(() => const QrPairingScannerPage());
    if (device == null || !context.mounted) {
      return;
    }
    // The web-send link stays active: this just additionally starts a
    // direct peer-to-peer transfer of the same files to the scanned device.
    await ref.notifier(sendProvider).startSession(target: device, files: widget.files, background: false);
    if (context.mounted) {
      context.showSnackBar(t.qrPairing.scan.pairedSnackbar(alias: device.alias));
    }
  }

  Future<void> _showHelpDialog(BuildContext context) async {
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        icon: const Icon(Icons.help_outline_rounded),
        title: Text(t.webSharePage.title),
        content: Text(
          _t(
            fr:
                "Ce lien permet à n'importe qui sur votre réseau local d'ouvrir cette page dans un navigateur "
                'et de télécharger les fichiers sélectionnés, sans avoir besoin d\'installer Aika. '
                'Il reste actif tant que cet écran est ouvert.',
            en:
                'This link lets anyone on your local network open this page in a browser and download the '
                'selected files, without needing to install Aika. It stays active as long as this screen is open.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => context.pop(),
            child: Text(t.general.close),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (_, _) async {
        if (_stateEnum != _ServerState.running) {
          return;
        }

        setState(() {
          _stateEnum = _ServerState.stopping;
        });
        await sleepAsync(250);
        await _revertServerState();
        await sleepAsync(250);

        if (context.mounted) {
          context.pop();
        }
      },
      canPop: false,
      child: Scaffold(
        appBar: basicAikaAppbar(t.webSharePage.title),
        body: Builder(
          builder: (context) {
            if (_stateEnum != _ServerState.running) {
              return Column(
                mainAxisSize: MainAxisSize.max,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (_stateEnum == _ServerState.initializing || _stateEnum == _ServerState.stopping) ...[
                    const CircularProgressIndicator(),
                    const SizedBox(height: 20),
                    Center(
                      child: Text(
                        _stateEnum == _ServerState.initializing ? t.webSharePage.loading : t.webSharePage.stopping,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                  ] else if (_initializedError != null) ...[
                    const Icon(Icons.error_outline, size: 48, color: Colors.red),
                    const SizedBox(height: 10),
                    Center(
                      child: Text(t.webSharePage.error, style: Theme.of(context).textTheme.titleLarge),
                    ),
                    const SizedBox(height: 10),
                    Center(
                      child: SelectableText(_initializedError!, style: Theme.of(context).textTheme.bodyMedium),
                    ),
                  ],
                ],
              );
            }

            final serverState = context.watch(serverProvider);
            final webSendState = serverState?.webSendState;
            if (serverState == null || webSendState == null) {
              // the server is restarting (e.g. because the pin changed)
              return const Center(child: CircularProgressIndicator());
            }
            final networkState = context.watch(localIpProvider);
            final colorScheme = Theme.of(context).colorScheme;
            final localIps = networkState.localIps;
            _handleIncomingRequests(webSendState.sessions.values);

            return ResponsiveListView(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 20),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        _t(fr: 'Vos fichiers sont prêts à être partagés', en: 'Your files are ready to be shared'),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                    ),
                    IconButton(
                      tooltip: _t(fr: 'Aide', en: 'Help'),
                      onPressed: () async => _showHelpDialog(context),
                      icon: const Icon(Icons.help_outline_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (localIps.isEmpty)
                  _InfoBanner(
                    icon: Icons.error_outline,
                    color: colorScheme.error,
                    text: _t(
                      fr: "Aucune adresse réseau locale n'a été trouvée. Connectez-vous à un réseau Wi-Fi ou local pour générer un lien.",
                      en: 'No local network address was found. Connect to a Wi-Fi or local network to generate a link.',
                    ),
                  )
                else ...[
                  _QuickAccessCard(
                    url: _urlsFor(localIps.first, serverState.port, webSendState.pin).$2,
                    onTapScan: () async => _onTapScanQr(context),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _t(fr: 'Liens de partage', en: 'Share links'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 10),
                  ...localIps.map((ip) {
                    final (url, urlWithPin) = _urlsFor(ip, serverState.port, webSendState.pin);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _LinkCard(
                        url: url,
                        onCopy: () async => _copyUrl(context, url),
                        onOpen: () async => _openUrl(url),
                        onShare: () async => _shareUrl(url),
                        onShowQr: () async => showDialog(
                          context: context,
                          builder: (_) => QrDialog(
                            data: urlWithPin,
                            label: url,
                            listenIncomingWebSendRequests: true,
                            pin: webSendState.pin,
                          ),
                        ),
                        onShowZoom: () async => showDialog(
                          context: context,
                          builder: (_) => ZoomDialog(
                            label: url,
                            pin: webSendState.pin,
                            listenIncomingWebSendRequests: true,
                          ),
                        ),
                      ),
                    );
                  }),
                ],
                const SizedBox(height: 20),
                _InfoBanner(
                  icon: Icons.wifi_rounded,
                  color: colorScheme.primary,
                  text: _t(
                    fr:
                        'Les appareils doivent être connectés au même réseau Wi-Fi ou local. Le lien reste actif '
                        'tant que le partage est en cours, fonctionne sans connexion Internet, et vos fichiers '
                        'restent sur votre réseau local.',
                    en:
                        'Devices must be connected to the same Wi-Fi or local network. The link stays active while '
                        'sharing is in progress, works without an Internet connection, and your files stay on your '
                        'local network.',
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  t.sendTab.selection.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 5),
                Text(
                  '${t.sendTab.selection.files(files: widget.files.length)}'
                  '   •   '
                  '${t.sendTab.selection.size(size: widget.files.fold(0, (prev, curr) => prev + curr.size).asReadableFileSize)}',
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 10),
                ...widget.files.map((file) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _FileRow(file: file),
                )),
                const SizedBox(height: 20),
                Text(t.webSharePage.requests, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),
                if (webSendState.sessions.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Text(t.webSharePage.noRequests, style: TextStyle(color: colorScheme.onSurfaceVariant)),
                  ),
                ...webSendState.sessions.entries.map((entry) {
                  final session = entry.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Card(
                      margin: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    session.deviceInfo,
                                    style: Theme.of(context).textTheme.bodyLarge!.copyWith(
                                      color: session.pending ? Theme.of(context).colorScheme.warning : null,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    session.ip,
                                    style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),
                            if (session.pending) ...[
                              TextButton(
                                onPressed: () {
                                  ref.notifier(serverProvider).declineWebSendRequest(session.sessionId);
                                },
                                style: TextButton.styleFrom(
                                  foregroundColor: Theme.of(context).colorScheme.onSurface,
                                ),
                                child: const Icon(Icons.close),
                              ),
                              TextButton(
                                onPressed: () {
                                  ref.notifier(serverProvider).acceptWebSendRequest(session.sessionId);
                                },
                                style: TextButton.styleFrom(
                                  foregroundColor: Theme.of(context).colorScheme.onSurface,
                                ),
                                child: const Icon(Icons.check_circle),
                              ),
                            ] else
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 20),
                                child: Text(
                                  t.general.accepted,
                                  style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                                    color: Theme.of(context).colorScheme.onSecondaryContainer,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 20),
                Text(
                  _t(fr: 'Options de partage', en: 'Sharing options'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                _OptionSwitchRow(
                  title: t.webSharePage.encryption,
                  description: _encrypted
                      ? t.webSharePage.encryptionHint
                      : _t(
                          fr: 'Chiffre la connexion avec un certificat auto-signé.',
                          en: 'Encrypts the connection with a self-signed certificate.',
                        ),
                  value: _encrypted,
                  warning: _encrypted,
                  onChanged: (value) => _init(encrypted: value),
                ),
                _OptionSwitchRow(
                  title: t.webSharePage.autoAccept,
                  description: _t(
                    fr: 'Les demandes de téléchargement sont acceptées sans confirmation.',
                    en: 'Download requests are accepted without confirmation.',
                  ),
                  value: webSendState.autoAccept,
                  onChanged: (value) => ref.notifier(serverProvider).setWebSendAutoAccept(value),
                ),
                _OptionSwitchRow(
                  title: t.webSharePage.requirePin,
                  description: webSendState.pin != null
                      ? t.webSharePage.pinHint(pin: webSendState.pin!)
                      : _t(
                          fr: 'Un code à usage unique doit être saisi pour accéder au lien.',
                          en: 'A one-time code must be entered to access the link.',
                        ),
                  value: webSendState.pin != null,
                  warning: webSendState.pin != null,
                  onChanged: (value) async {
                    if (!value) {
                      await ref.notifier(serverProvider).setWebSendPin(null);
                      return;
                    }
                    final String? newPin = await showDialog<String>(
                      context: context,
                      builder: (_) => const PinDialog(
                        obscureText: false,
                        generateRandom: true,
                      ),
                    );
                    if (newPin != null && newPin.isNotEmpty) {
                      await ref.notifier(serverProvider).setWebSendPin(newPin);
                    }
                  },
                ),
                const SizedBox(height: 20),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Shown automatically the moment a new incoming download request arrives
/// (see [_WebSendPageState._handleIncomingRequests]), so accepting or
/// rejecting it doesn't require noticing and scrolling to the "Requetes"
/// list. That list is kept as-is below as a secondary, always-visible
/// status view (and a fallback if a dialog is ever missed).
class _IncomingRequestDialog extends StatelessWidget {
  final WebSendSession session;

  const _IncomingRequestDialog({required this.session});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AlertDialog(
      icon: Icon(Icons.download_for_offline_outlined, color: colorScheme.primary, size: 36),
      title: Text(_t(fr: 'Nouvelle demande de téléchargement', en: 'New download request')),
      content: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const CircleAvatar(child: Icon(Icons.devices_other)),
        title: Text(session.deviceInfo, style: Theme.of(context).textTheme.titleMedium),
        subtitle: Text(session.ip),
      ),
      actions: [
        TextButton(
          onPressed: () => context.pop(false),
          child: Text(t.general.decline),
        ),
        FilledButton(
          onPressed: () => context.pop(true),
          child: Text(t.general.accept),
        ),
      ],
    );
  }
}

/// The main, always-visible "quick access" card: a live QR code for the
/// recommended link (first entry of [localIpProvider]'s already-ranked
/// [NetworkState.localIps]), plus a shortcut to pair with a nearby Aika
/// device directly instead of using the browser link.
class _QuickAccessCard extends StatelessWidget {
  final String url;
  final VoidCallback onTapScan;

  const _QuickAccessCard({required this.url, required this.onTapScan});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colorScheme.outlineVariant, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Row(
              children: [
                Icon(Icons.link_rounded, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  _t(fr: 'Accès rapide', en: 'Quick access'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _t(
                fr: 'Scannez ce code QR ou ouvrez le lien dans un navigateur.',
                en: 'Scan this QR code or open the link in a browser.',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            LayoutBuilder(
              builder: (context, constraints) {
                final size = constraints.maxWidth.clamp(160.0, 240.0).toDouble();
                return Container(
                  width: size,
                  height: size,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: PrettyQrView.data(
                    errorCorrectLevel: QrErrorCorrectLevel.Q,
                    data: url,
                    decoration: const PrettyQrDecoration(
                      shape: PrettyQrSmoothSymbol(
                        roundFactor: 0,
                        color: Colors.black,
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            Text(
              _t(fr: 'Scannez pour ouvrir le lien', en: 'Scan to open the link'),
              style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: onTapScan,
              icon: const Icon(Icons.qr_code_scanner),
              label: Text(t.qrPairing.scan.buttonTooltip),
            ),
          ],
        ),
      ),
    );
  }
}

/// One local IP's link, as a compact card: address + copy/QR/zoom/open/share.
class _LinkCard extends StatelessWidget {
  final String url;
  final VoidCallback onCopy;
  final VoidCallback onOpen;
  final VoidCallback onShare;
  final VoidCallback onShowQr;
  final VoidCallback onShowZoom;

  const _LinkCard({
    required this.url,
    required this.onCopy,
    required this.onOpen,
    required this.onShare,
    required this.onShowQr,
    required this.onShowZoom,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colorScheme.outlineVariant, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(url, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              children: [
                _LinkActionButton(icon: Icons.content_copy, tooltip: t.general.copy, onTap: onCopy),
                _LinkActionButton(icon: Icons.qr_code, tooltip: t.dialogs.qr.title, onTap: onShowQr),
                _LinkActionButton(icon: Icons.tv, tooltip: 'TV', onTap: onShowZoom),
                _LinkActionButton(icon: Icons.open_in_browser, tooltip: t.general.open, onTap: onOpen),
                _LinkActionButton(icon: Icons.ios_share_outlined, tooltip: _t(fr: 'Partager', en: 'Share'), onTap: onShare),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LinkActionButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _LinkActionButton({required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 18),
        ),
      ),
    );
  }
}

/// A short, dismissible-by-nature info callout (network reminder, or the
/// "no local address" error state).
class _InfoBanner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;

  const _InfoBanner({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: color))),
        ],
      ),
    );
  }
}

/// One shared file: thumbnail/type icon, name, extension and size — reuses
/// the same [SmartFileThumbnail] and [IntFileSize.asReadableFileSize]
/// already used for the file preview strip on the Send screen.
class _FileRow extends StatelessWidget {
  final CrossFile file;

  const _FileRow({required this.file});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final dotIndex = file.name.lastIndexOf('.');
    final extension = dotIndex == -1 || dotIndex == file.name.length - 1 ? null : file.name.substring(dotIndex + 1).toUpperCase();

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colorScheme.outlineVariant, width: 1),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 40,
                height: 40,
                child: SmartFileThumbnail.fromCrossFile(file),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(
                    [
                      ?extension,
                      file.size.asReadableFileSize,
                    ].join(' · '),
                    style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A titled [Switch] row with a short explanation underneath, used for the
/// encryption / auto-accept / require-PIN options.
class _OptionSwitchRow extends StatelessWidget {
  final String title;
  final String description;
  final bool value;
  final bool warning;
  final ValueChanged<bool> onChanged;

  const _OptionSwitchRow({
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
    this.warning = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(color: warning ? colorScheme.warning : colorScheme.onSurfaceVariant, fontSize: 12),
                ),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
