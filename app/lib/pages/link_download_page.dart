import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/provider/github_account_provider.dart';
import 'package:localsend_app/provider/link_download_provider.dart';
import 'package:localsend_app/util/link_download/browser_bridge.dart';
import 'package:localsend_app/util/link_download/file_naming.dart';
import 'package:localsend_app/util/link_download/link_http.dart';
import 'package:localsend_app/util/link_download/link_problem.dart';
import 'package:localsend_app/util/link_download/link_sources.dart';
import 'package:localsend_app/util/link_download/url_policy.dart';
import 'package:localsend_app/util/native/directories.dart';
import 'package:localsend_app/util/native/open_file.dart';
import 'package:localsend_app/util/native/open_folder.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_app/util/ui/snackbar.dart';
import 'package:localsend_app/widget/custom_basic_appbar.dart';
import 'package:localsend_isolates/model/file_type.dart';
import 'package:path/path.dart' as p;
import 'package:refena_flutter/refena_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

String _t({required String fr, required String en}) => LocaleSettings.currentLocale == AppLocale.fr ? fr : en;

const _radius = 10.0;
const _shape = RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(_radius)));

/// "Télécharger depuis un lien": paste a link, Aika checks that it really
/// serves a file, then downloads it to the device.
///
/// The download button only appears once a file has been verified; links
/// to web pages or to platforms without an authorized download get a clear
/// explanation and "Ouvrir dans le navigateur" instead.
class LinkDownloadPage extends StatefulWidget {
  /// Link to analyse right away (shared from another app).
  final String? initialUrl;

  const LinkDownloadPage({this.initialUrl});

  @override
  State<LinkDownloadPage> createState() => _LinkDownloadPageState();
}

class _LinkDownloadPageState extends State<LinkDownloadPage> {
  final _controller = TextEditingController();

  /// Bumped for each analysis so a slow, outdated answer is ignored.
  int _generation = 0;
  bool _analyzing = false;
  Uri? _uri;
  DirectFileInfo? _info;
  LinkDownloadException? _error;
  String? _taskId;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialUrl;
    if (initial != null && initial.trim().isNotEmpty) {
      _controller.text = initial.trim();
      WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_analyze()));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (!mounted) {
      return;
    }
    if (text == null || text.isEmpty) {
      context.showSnackBar(_t(fr: 'Le presse-papiers est vide.', en: 'The clipboard is empty.'));
      return;
    }
    _controller.text = text;
    await _analyze();
  }

  void _clear() {
    _generation++;
    _controller.clear();
    setState(() {
      _analyzing = false;
      _uri = null;
      _info = null;
      _error = null;
      _taskId = null;
    });
  }

  Future<void> _analyze() async {
    FocusScope.of(context).unfocus();
    final generation = ++_generation;
    setState(() {
      _analyzing = true;
      _info = null;
      _error = null;
      _taskId = null;
    });

    Uri? uri;
    DirectFileInfo? info;
    LinkDownloadException? error;
    try {
      uri = parseUserLink(_controller.text);
      final platform = knownPlatformOf(uri);
      if (platform != null) {
        // Known platform: no request needed to know the answer.
        throw LinkDownloadException(LinkProblem.unsupportedPlatform, platform: platform.name);
      }
      info = await context.ref.notifier(linkDownloadProvider).analyze(uri);
    } on LinkDownloadException catch (e) {
      error = e;
    } catch (_) {
      error = const LinkDownloadException(LinkProblem.network);
    }

    if (!mounted || generation != _generation) {
      return;
    }
    setState(() {
      _analyzing = false;
      _uri = uri;
      _info = info;
      _error = error;
      _taskId = info == null ? null : context.ref.read(linkDownloadProvider).unfinishedFor(info.sourceUri)?.id;
    });
  }

  Future<void> _download(DirectFileInfo info) async {
    final service = context.ref.notifier(linkDownloadProvider);
    final size = info.size;
    var allowLarge = false;
    if (size != null && size > largeDownloadBytes) {
      allowLarge = await _confirmLarge(size);
      if (!allowLarge || !mounted) {
        return;
      }
    }
    final spaceProblem = await service.checkSpace(info);
    if (!mounted) {
      return;
    }
    if (spaceProblem != null) {
      setState(() => _error = LinkDownloadException(spaceProblem));
      return;
    }
    setState(() {
      _error = null;
      _taskId = service.start(info, allowLarge: allowLarge);
    });
  }

  /// "Plusieurs liens": one link per line, each analysed then queued.
  Future<void> _addSeveral() async {
    final text = await showDialog<String>(context: context, builder: (_) => const _SeveralLinksDialog());
    if (text == null || !mounted) {
      return;
    }
    final links = <Uri>{};
    var refused = 0;
    for (final line in text.split(RegExp(r'[\r\n]+'))) {
      if (line.trim().isEmpty) {
        continue;
      }
      try {
        final uri = parseUserLink(line);
        if (knownPlatformOf(uri) == null) {
          links.add(uri);
        } else {
          refused++;
        }
      } on LinkDownloadException {
        refused++;
      }
    }
    if (links.isEmpty) {
      context.showSnackBar(_t(fr: 'Aucun lien valide.', en: 'No valid link.'));
      return;
    }

    context.showSnackBar(_t(fr: 'Analyse de ${links.length} lien(s)…', en: 'Analysing ${links.length} link(s)…'));
    final service = context.ref.notifier(linkDownloadProvider);
    var added = 0;
    // A few at a time: fast without flooding the network.
    final pending = links.toList();
    Future<void> worker() async {
      while (pending.isNotEmpty) {
        final uri = pending.removeLast();
        try {
          final info = await service.analyze(uri);
          if (await service.checkSpace(info) == null) {
            service.start(info, allowLarge: true);
            added++;
          } else {
            refused++;
          }
        } on LinkDownloadException {
          refused++;
        } catch (_) {
          refused++;
        }
      }
    }

    await Future.wait([for (var i = 0; i < 3; i++) worker()]);
    if (!mounted) {
      return;
    }
    context.showSnackBar(
      refused == 0
          ? _t(fr: '$added téléchargement(s) ajouté(s).', en: '$added download(s) added.')
          : _t(fr: '$added ajouté(s) · $refused ignoré(s) (pas un fichier ou lien refusé).', en: '$added added · $refused skipped (not a file or refused link).'),
    );
  }

  Future<bool> _confirmLarge(int size) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_t(fr: 'Fichier volumineux', en: 'Large file')),
        content: Text(
          _t(
            fr: 'Ce fichier fait ${formatBytes(size)}. Le téléchargement peut être long et utiliser beaucoup de données.',
            en: 'This file is ${formatBytes(size)}. The download may take a while and use a lot of data.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(_t(fr: 'Annuler', en: 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(_t(fr: 'Télécharger', en: 'Download'))),
        ],
      ),
    );
    return confirmed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.ref.watch(linkDownloadProvider);
    final task = _taskId == null ? null : state.taskById(_taskId!);
    final info = _info;
    final previous = info == null || task != null ? null : state.previousDownloadOf(info.sourceUri);
    final others = state.tasks
        .where((t) => t.id != _taskId && t.status != LinkDownloadStatus.completed && t.status != LinkDownloadStatus.cancelled)
        .toList();
    final service = context.ref.notifier(linkDownloadProvider);
    final anyPaused = others.any((t) => t.status == LinkDownloadStatus.paused);
    final anyActive = others.any((t) => t.isActive);

    return Scaffold(
      appBar: basicAikaAppbar(_t(fr: 'Télécharger depuis un lien', en: 'Download from a link')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            _LinkField(controller: _controller, onPaste: _paste, onClear: _clear, onSubmit: _analyze),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _analyzing ? null : _analyze,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                shape: _shape,
                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              icon: _analyzing
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.4, strokeCap: StrokeCap.round))
                  : const Icon(Icons.travel_explore_rounded),
              label: Text(_analyzing ? _t(fr: 'Analyse…', en: 'Analysing…') : _t(fr: 'Analyser le lien', en: 'Analyse the link')),
            ),
            const SizedBox(height: 8),
            Text(
              _t(
                fr: 'Images, vidéos, PDF et autres fichiers accessibles directement par un lien.',
                en: 'Images, videos, PDFs and other files directly reachable through a link.',
              ),
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              children: [
                TextButton.icon(
                  onPressed: () async => _addSeveral(),
                  icon: const Icon(Icons.playlist_add_rounded, size: 20),
                  label: Text(_t(fr: 'Plusieurs liens', en: 'Several links')),
                ),
                TextButton.icon(
                  onPressed: () async => showDialog<void>(context: context, builder: (_) => const _OptionsDialog()),
                  icon: const Icon(Icons.tune_rounded, size: 20),
                  label: Text(_t(fr: 'Options', en: 'Options')),
                ),
              ],
            ),
            const SizedBox(height: 10),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _error != null && info == null
                  ? _ProblemCard(key: ValueKey(_error), error: _error!, uri: _uri, onRetry: _analyze)
                  : info != null
                  ? _FileCard(
                      key: ValueKey(info.sourceUri),
                      info: info,
                      task: task,
                      previous: previous,
                      error: _error,
                      onDownload: () async => _download(info),
                      onCancel: () => context.ref.notifier(linkDownloadProvider).cancel(_taskId!),
                    )
                  : const SizedBox.shrink(),
            ),
            if (others.isNotEmpty) ...[
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(child: _SectionTitle(_t(fr: 'Téléchargements', en: 'Downloads'))),
                  if (anyPaused)
                    TextButton(onPressed: service.resumeAll, child: Text(_t(fr: 'Tout reprendre', en: 'Resume all')))
                  else if (anyActive)
                    TextButton(onPressed: service.pauseAll, child: Text(_t(fr: 'Tout mettre en pause', en: 'Pause all'))),
                ],
              ),
              for (final other in others) _TaskRow(task: other),
            ],
            if (state.history.isNotEmpty) ...[
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(child: _SectionTitle(_t(fr: 'Téléchargements récents', en: 'Recent downloads'))),
                  TextButton(
                    onPressed: () async => context.ref.notifier(linkDownloadProvider).clearHistory(),
                    child: Text(_t(fr: 'Effacer', en: 'Clear')),
                  ),
                ],
              ),
              for (final record in state.history.take(20)) _HistoryRow(record: record),
            ],
          ],
        ),
      ),
    );
  }
}

class _LinkField extends StatelessWidget {
  final TextEditingController controller;
  final Future<void> Function() onPaste;
  final VoidCallback onClear;
  final Future<void> Function() onSubmit;

  const _LinkField({required this.controller, required this.onPaste, required this.onClear, required this.onSubmit});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(_radius),
      borderSide: BorderSide(color: colorScheme.outlineVariant),
    );
    return TextField(
      controller: controller,
      keyboardType: TextInputType.url,
      textInputAction: TextInputAction.go,
      autocorrect: false,
      enableSuggestions: false,
      maxLines: 1,
      onSubmitted: (_) async => onSubmit(),
      decoration: InputDecoration(
        hintText: 'https://…',
        filled: true,
        fillColor: colorScheme.surfaceContainerHigh,
        prefixIcon: const Icon(Icons.link_rounded),
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) => value.text.isEmpty
              ? IconButton(
                  tooltip: _t(fr: 'Coller', en: 'Paste'),
                  icon: Icon(Icons.content_paste_rounded, color: colorScheme.primary),
                  onPressed: onPaste,
                )
              : IconButton(
                  tooltip: _t(fr: 'Effacer', en: 'Clear'),
                  icon: const Icon(Icons.close_rounded),
                  onPressed: onClear,
                ),
        ),
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(borderSide: BorderSide(color: colorScheme.primary, width: 1.5)),
      ),
    );
  }
}

/// Rounded card used by every block of the page.
class _Card extends StatelessWidget {
  final Widget child;
  final Color? borderColor;

  const _Card({required this.child, this.borderColor});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(_radius),
        border: Border.all(color: borderColor ?? colorScheme.outlineVariant),
      ),
      child: child,
    );
  }
}

class _FileCard extends StatelessWidget {
  final DirectFileInfo info;
  final LinkDownloadTask? task;
  final LinkDownloadRecord? previous;
  final LinkDownloadException? error;
  final VoidCallback onDownload;
  final VoidCallback onCancel;

  const _FileCard({
    required this.info,
    required this.task,
    required this.previous,
    required this.error,
    required this.onDownload,
    required this.onCancel,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final task = this.task;
    final details = [
      _kindLabel(info.kind, info.fileName),
      if (info.size != null) formatBytes(info.size!),
      info.fileUri.host,
    ].join(' · ');

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _KindIcon(kind: info.kind, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(info.fileName, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(details, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: _Pill(
              icon: Icons.verified_rounded,
              label: _t(fr: 'Fichier vérifié', en: 'Verified file'),
              color: colorScheme.primary,
            ),
          ),
          if (previous != null) ...[
            const SizedBox(height: 10),
            Text(
              _t(
                fr: 'Déjà téléchargé le ${_formatDate(previous!.completedAt)}.',
                en: 'Already downloaded on ${_formatDate(previous!.completedAt)}.',
              ),
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: 10),
            Text(_problemMessage(error!), style: TextStyle(color: colorScheme.error)),
          ],
          const SizedBox(height: 12),
          if (task == null) ..._idleActions(context) else ..._taskContent(context, task),
        ],
      ),
    );
  }

  List<Widget> _idleActions(BuildContext context) {
    final previous = this.previous;
    if (previous == null) {
      return [
        _DownloadButton(label: _t(fr: 'Télécharger', en: 'Download'), onPressed: onDownload),
      ];
    }
    return [
      Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () async => _openRecord(context, previous),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48), shape: _shape),
              child: Text(_t(fr: 'Ouvrir', en: 'Open')),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _DownloadButton(label: _t(fr: 'Télécharger à nouveau', en: 'Download again'), onPressed: onDownload),
          ),
        ],
      ),
    ];
  }

  List<Widget> _taskContent(BuildContext context, LinkDownloadTask task) {
    final colorScheme = Theme.of(context).colorScheme;
    switch (task.status) {
      case LinkDownloadStatus.running:
      case LinkDownloadStatus.queued:
      case LinkDownloadStatus.paused:
        final service = context.ref.notifier(linkDownloadProvider);
        final running = task.status == LinkDownloadStatus.running;
        return [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: running ? task.progress : task.progress ?? 0,
              minHeight: 8,
              color: running ? null : colorScheme.outline,
            ),
          ),
          const SizedBox(height: 8),
          Text(_statusLine(task), style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13)),
          if (task.retry > 0) ...[
            const SizedBox(height: 4),
            Text(
              _t(
                fr: 'Connexion perdue, nouvelle tentative (${task.retry}/3)…',
                en: 'Connection lost, retrying (${task.retry}/3)…',
              ),
              style: TextStyle(color: colorScheme.tertiary, fontSize: 13),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: task.status == LinkDownloadStatus.paused
                    ? FilledButton.icon(
                        onPressed: () => service.resume(task.id),
                        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48), shape: _shape),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: Text(_t(fr: 'Reprendre', en: 'Resume')),
                      )
                    : OutlinedButton.icon(
                        onPressed: () => service.pause(task.id),
                        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48), shape: _shape),
                        icon: const Icon(Icons.pause_rounded),
                        label: Text(_t(fr: 'Pause', en: 'Pause')),
                      ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: onCancel,
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48), shape: _shape),
                  child: Text(_t(fr: 'Annuler', en: 'Cancel')),
                ),
              ),
            ],
          ),
        ];
      case LinkDownloadStatus.completed:
        return [
          Row(
            children: [
              Icon(Icons.check_circle_rounded, color: colorScheme.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _t(fr: 'Enregistré dans ${_folderLabel(task.savedFolder)}', en: 'Saved to ${_folderLabel(task.savedFolder)}'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () async => _openPath(context, task.savedPath!, info.kind, info.mimeType),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48), shape: _shape),
                  child: Text(_t(fr: 'Ouvrir', en: 'Open')),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () async => openFolder(folderPath: task.savedFolder!, fileName: p.basename(task.savedPath!)),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48), shape: _shape),
                  child: Text(_t(fr: 'Afficher le dossier', en: 'Show folder')),
                ),
              ),
            ],
          ),
        ];
      case LinkDownloadStatus.failed:
        return [
          Text(_problemMessage(LinkDownloadException(task.problem ?? LinkProblem.network)), style: TextStyle(color: colorScheme.error)),
          const SizedBox(height: 10),
          _DownloadButton(label: _t(fr: 'Réessayer', en: 'Retry'), onPressed: onDownload),
        ];
      case LinkDownloadStatus.cancelled:
        return [
          Text(_t(fr: 'Téléchargement annulé.', en: 'Download cancelled.'), style: TextStyle(color: colorScheme.onSurfaceVariant)),
          const SizedBox(height: 10),
          _DownloadButton(label: _t(fr: 'Télécharger', en: 'Download'), onPressed: onDownload),
        ];
    }
  }
}

class _DownloadButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _DownloadButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        shape: _shape,
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
      icon: const Icon(Icons.download_rounded),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}

class _ProblemCard extends StatelessWidget {
  final LinkDownloadException error;
  final Uri? uri;
  final Future<void> Function() onRetry;

  const _ProblemCard({required this.error, required this.uri, required this.onRetry, super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final uri = this.uri;
    final canOpen =
        uri != null &&
        const {
          LinkProblem.unsupportedPlatform,
          LinkProblem.webPageWithoutMedia,
          LinkProblem.requiresAuth,
          LinkProblem.notFound,
          LinkProblem.githubSignInRequired,
          LinkProblem.githubTokenInvalid,
          LinkProblem.githubNoAccess,
          LinkProblem.expired,
        }.contains(error.problem);
    final canConnectGitHub = const {
      LinkProblem.githubSignInRequired,
      LinkProblem.githubTokenInvalid,
      LinkProblem.githubNoAccess,
    }.contains(error.problem);
    final hasGitHubToken = error.problem != LinkProblem.githubSignInRequired;
    final canRetry = error.isTransient;
    final platform = error.platform == null ? null : knownPlatforms.where((pl) => pl.name == error.platform).firstOrNull;

    return _Card(
      borderColor: colorScheme.tertiary.withValues(alpha: 0.6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, color: colorScheme.tertiary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _problemTitle(error.problem),
                  style: TextStyle(fontWeight: FontWeight.w700, color: colorScheme.onSurface),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(_problemMessage(error), style: TextStyle(color: colorScheme.onSurfaceVariant)),
          if (platform != null && platform.hasOwnSaveFeature) ...[
            const SizedBox(height: 6),
            Text(
              _t(
                fr: 'Astuce : utilisez « Enregistrer » dans l’app ${platform.name} si le créateur l’autorise, puis partagez le fichier avec Aika.',
                en: 'Tip: use “Save” in the ${platform.name} app if the creator allows it, then share the file with Aika.',
              ),
              style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
            ),
          ],
          if (canConnectGitHub) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () async {
                final connected = await showGitHubTokenDialog(context);
                if (connected) {
                  await onRetry();
                }
              },
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46), shape: _shape),
              icon: const Icon(Icons.key_rounded),
              label: Text(
                hasGitHubToken ? _t(fr: 'Changer de jeton', en: 'Change token') : _t(fr: 'Connecter GitHub', en: 'Connect GitHub'),
              ),
            ),
          ],
          if (canOpen) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async => launchUrl(uri, mode: LaunchMode.externalApplication),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46), shape: _shape),
              icon: const Icon(Icons.open_in_new_rounded),
              label: Text(_t(fr: 'Ouvrir dans le navigateur', en: 'Open in browser')),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: uri.toString()));
                if (context.mounted) {
                  context.showSnackBar(_t(fr: 'Lien copié', en: 'Link copied'));
                }
              },
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46), shape: _shape),
              icon: const Icon(Icons.copy_rounded),
              label: Text(_t(fr: 'Copier le lien', en: 'Copy link')),
            ),
          ],
          if (canRetry) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46), shape: _shape),
              icon: const Icon(Icons.refresh_rounded),
              label: Text(_t(fr: 'Réessayer', en: 'Retry')),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

/// One download of the list: progress, status and the matching actions.
class _TaskRow extends StatelessWidget {
  final LinkDownloadTask task;

  const _TaskRow({required this.task});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final service = context.ref.notifier(linkDownloadProvider);
    final failed = task.status == LinkDownloadStatus.failed;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _Card(
        child: Row(
          children: [
            _KindIcon(kind: task.info.kind, size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(task.info.fileName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: task.status == LinkDownloadStatus.running ? task.progress : task.progress ?? 0,
                      minHeight: 5,
                      color: task.status == LinkDownloadStatus.running ? null : (failed ? colorScheme.error : colorScheme.outline),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    failed ? _problemMessage(LinkDownloadException(task.problem ?? LinkProblem.network)) : _statusLine(task),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: failed ? colorScheme.error : colorScheme.onSurfaceVariant, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (task.canResume)
              IconButton(
                tooltip: failed ? _t(fr: 'Réessayer', en: 'Retry') : _t(fr: 'Reprendre', en: 'Resume'),
                icon: Icon(failed ? Icons.refresh_rounded : Icons.play_arrow_rounded),
                onPressed: () => service.resume(task.id),
              )
            else
              IconButton(
                tooltip: _t(fr: 'Pause', en: 'Pause'),
                icon: const Icon(Icons.pause_rounded),
                onPressed: () => service.pause(task.id),
              ),
            IconButton(
              tooltip: task.isActive ? _t(fr: 'Annuler', en: 'Cancel') : _t(fr: 'Retirer', en: 'Remove'),
              icon: const Icon(Icons.close_rounded),
              onPressed: () => task.isActive ? service.cancel(task.id) : service.dismiss(task.id),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final LinkDownloadRecord record;

  const _HistoryRow({required this.record});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: colorScheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radius),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () async => _openRecord(context, record),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            child: Row(
              children: [
                _KindIcon(kind: record.kind, size: 36),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(record.fileName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(
                        '${formatBytes(record.size)} · ${_formatDate(record.completedAt)}',
                        style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<int>(
                  icon: const Icon(Icons.more_vert_rounded),
                  onSelected: (value) async {
                    switch (value) {
                      case 0:
                        await openFolder(folderPath: record.savedFolder, fileName: p.basename(record.savedPath));
                      case 1:
                        await Clipboard.setData(ClipboardData(text: record.url));
                        if (context.mounted) {
                          context.showSnackBar(_t(fr: 'Lien copié', en: 'Link copied'));
                        }
                      case 2:
                        await context.ref.notifier(linkDownloadProvider).removeFromHistory(record.id);
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 0, child: Text(_t(fr: 'Afficher le dossier', en: 'Show folder'))),
                    PopupMenuItem(value: 1, child: Text(_t(fr: 'Copier le lien', en: 'Copy link'))),
                    PopupMenuItem(value: 2, child: Text(_t(fr: 'Retirer de l’historique', en: 'Remove from history'))),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _KindIcon extends StatelessWidget {
  final LinkMediaKind kind;
  final double size;

  const _KindIcon({required this.kind, required this.size});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(_radius),
      ),
      child: Icon(_kindIcon(kind), color: colorScheme.onPrimaryContainer, size: size * 0.55),
    );
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _Pill({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(_radius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

Future<void> _openRecord(BuildContext context, LinkDownloadRecord record) {
  return _openPath(context, record.savedPath, record.kind, record.mimeType);
}

/// Opens the file with the system app. Never done automatically: only
/// when the user taps "Ouvrir".
Future<void> _openPath(BuildContext context, String path, LinkMediaKind kind, String? mimeType) {
  return openFile(context, _fileTypeOf(kind, mimeType, path), path);
}

FileType _fileTypeOf(LinkMediaKind kind, String? mimeType, String path) {
  switch (kind) {
    case LinkMediaKind.image:
      return FileType.image;
    case LinkMediaKind.video:
      return FileType.video;
    case LinkMediaKind.audio:
    case LinkMediaKind.archive:
    case LinkMediaKind.other:
      return path.toLowerCase().endsWith('.apk') || mimeType == 'application/vnd.android.package-archive' ? FileType.apk : FileType.other;
    case LinkMediaKind.document:
      if (mimeType == 'application/pdf' || path.toLowerCase().endsWith('.pdf')) {
        return FileType.pdf;
      }
      return mimeType != null && mimeType.startsWith('text/') ? FileType.text : FileType.other;
  }
}

IconData _kindIcon(LinkMediaKind kind) {
  switch (kind) {
    case LinkMediaKind.image:
      return Icons.image_rounded;
    case LinkMediaKind.video:
      return Icons.movie_rounded;
    case LinkMediaKind.audio:
      return Icons.audiotrack_rounded;
    case LinkMediaKind.document:
      return Icons.description_rounded;
    case LinkMediaKind.archive:
      return Icons.folder_zip_rounded;
    case LinkMediaKind.other:
      return Icons.insert_drive_file_rounded;
  }
}

String _kindLabel(LinkMediaKind kind, String fileName) {
  final dot = fileName.lastIndexOf('.');
  final ext = dot > 0 && dot < fileName.length - 1 ? fileName.substring(dot + 1).toUpperCase() : null;
  final label = switch (kind) {
    LinkMediaKind.image => 'Image',
    LinkMediaKind.video => _t(fr: 'Vidéo', en: 'Video'),
    LinkMediaKind.audio => 'Audio',
    LinkMediaKind.document => 'Document',
    LinkMediaKind.archive => 'Archive',
    LinkMediaKind.other => _t(fr: 'Fichier', en: 'File'),
  };
  return ext == null || ext.length > 5 ? label : '$label $ext';
}

String _folderLabel(String? folder) {
  if (folder == null || folder == kAndroidDefaultDownloadsMarker) {
    return _t(fr: 'Téléchargements/$linkDownloadFolderName', en: 'Downloads/$linkDownloadFolderName');
  }
  return folder;
}

/// "En attente", "En pause · 92 Mo / 148 Mo" or the live progress.
String _statusLine(LinkDownloadTask task) {
  switch (task.status) {
    case LinkDownloadStatus.queued:
      return _t(fr: 'En attente', en: 'Queued');
    case LinkDownloadStatus.paused:
      final total = task.total;
      final amount = total == null ? formatBytes(task.received) : '${formatBytes(task.received)} / ${formatBytes(total)}';
      return _t(fr: 'En pause · $amount', en: 'Paused · $amount');
    case LinkDownloadStatus.running:
      if (task.received == 0 && task.bytesPerSecond == 0) {
        return _t(fr: 'Connexion…', en: 'Connecting…');
      }
      final connections = task.connections > 1 ? _t(fr: ' · ${task.connections} connexions', en: ' · ${task.connections} connections') : '';
      return '${_progressLabel(task)}$connections';
    case LinkDownloadStatus.completed:
    case LinkDownloadStatus.failed:
    case LinkDownloadStatus.cancelled:
      return _progressLabel(task);
  }
}

String _progressLabel(LinkDownloadTask task) {
  final total = task.total;
  final parts = <String>[
    total == null ? formatBytes(task.received) : '${formatBytes(task.received)} / ${formatBytes(total)}',
    if (task.bytesPerSecond > 0) '${formatBytes(task.bytesPerSecond.round())}/s',
    if (task.bytesPerSecond > 0 && total != null) '≈ ${_formatDuration(((total - task.received) / task.bytesPerSecond).round())}',
  ];
  return parts.join(' · ');
}

String _formatDuration(int seconds) {
  if (seconds < 60) {
    return '$seconds s';
  }
  if (seconds < 3600) {
    return '${seconds ~/ 60} min';
  }
  return '${seconds ~/ 3600} h ${(seconds % 3600) ~/ 60} min';
}

String _formatDate(DateTime date) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(date.day)}/${two(date.month)}/${date.year}';
}

/// Size in the user's language: `148 Mo`, `2,4 Go` / `148 MB`, `2.4 GB`.
String formatBytes(int bytes) {
  final fr = LocaleSettings.currentLocale == AppLocale.fr;
  const units = [('o', 'B'), ('Ko', 'KB'), ('Mo', 'MB'), ('Go', 'GB'), ('To', 'TB')];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  var text = unit == 0 || value >= 100 ? value.round().toString() : value.toStringAsFixed(1);
  if (text.endsWith('.0')) {
    text = text.substring(0, text.length - 2);
  }
  if (fr) {
    text = text.replaceAll('.', ',');
  }
  final (frUnit, enUnit) = units[unit];
  return '$text ${fr ? frUnit : enUnit}';
}

String _problemTitle(LinkProblem problem) {
  switch (problem) {
    case LinkProblem.unsupportedPlatform:
      return _t(fr: 'Le téléchargement direct n’est pas disponible pour cette source.', en: 'Direct download is not available for this source.');
    case LinkProblem.webPageWithoutMedia:
      return _t(fr: 'Aucun fichier téléchargeable', en: 'No downloadable file');
    case LinkProblem.requiresAuth:
      return _t(fr: 'Connexion requise', en: 'Sign-in required');
    case LinkProblem.notFound:
      return _t(fr: 'Contenu introuvable', en: 'Content not found');
    case LinkProblem.githubSignInRequired:
    case LinkProblem.githubTokenInvalid:
      return _t(fr: 'Connexion GitHub requise', en: 'GitHub sign-in required');
    case LinkProblem.githubNoAccess:
      return _t(fr: 'Accès refusé par GitHub', en: 'Access denied by GitHub');
    case LinkProblem.expired:
      return _t(fr: 'Contenu expiré', en: 'Content expired');
    case LinkProblem.network:
    case LinkProblem.timeout:
    case LinkProblem.serverError:
      return _t(fr: 'Analyse impossible pour le moment', en: 'Could not analyse the link right now');
    default:
      return _t(fr: 'Lien refusé', en: 'Link refused');
  }
}

String _problemMessage(LinkDownloadException error) {
  final platform = error.platform ?? '';
  switch (error.problem) {
    case LinkProblem.empty:
      return _t(fr: 'Collez ou saisissez un lien pour commencer.', en: 'Paste or type a link to start.');
    case LinkProblem.malformed:
      return _t(fr: 'Ce lien n’est pas valide.', en: 'This link is not valid.');
    case LinkProblem.unsupportedScheme:
      return _t(fr: 'Seuls les liens http et https sont acceptés.', en: 'Only http and https links are accepted.');
    case LinkProblem.credentialsInUrl:
      return _t(
        fr: 'Par sécurité, les liens contenant un identifiant ou un mot de passe sont refusés.',
        en: 'For security, links containing a user name or password are refused.',
      );
    case LinkProblem.localAddress:
      return _t(
        fr: 'Par sécurité, Aika ne télécharge pas depuis cet appareil, le réseau local ou une adresse réservée.',
        en: 'For security, Aika does not download from this device, the local network or a reserved address.',
      );
    case LinkProblem.unsupportedPlatform:
      final known = knownPlatforms.where((k) => k.name == platform).firstOrNull;
      return switch (known?.limit) {
        PlatformLimit.termsForbid => _t(
          fr: 'Les conditions d’utilisation de $platform n’autorisent pas le téléchargement par des applications tierces.',
          en: '$platform’s terms of service do not allow downloads by third-party apps.',
        ),
        PlatformLimit.noPublicApi => _t(
          fr: '$platform ne propose pas de téléchargement autorisé pour les applications tierces.',
          en: '$platform offers no authorized download for third-party apps.',
        ),
        PlatformLimit.requiresApprovedApp => _t(
          fr: '$platform réserve l’accès à ses médias aux applications validées, après connexion à un compte. Ce lien n’est pas encore pris en charge.',
          en: '$platform only gives its media to approved apps, after signing in to an account. This link is not supported yet.',
        ),
        null => _t(fr: 'Ce lien n’est pas encore pris en charge.', en: 'This link is not supported yet.'),
      };
    case LinkProblem.webPageWithoutMedia:
      return _t(
        fr: 'Ce lien ouvre une page web, pas un fichier. Ouvrez-le dans le navigateur pour voir son contenu.',
        en: 'This link opens a web page, not a file. Open it in the browser to see its content.',
      );
    case LinkProblem.requiresAuth:
      return _t(fr: 'Ce contenu nécessite une authentification sur la plateforme.', en: 'This content requires signing in on the platform.');
    case LinkProblem.notFound:
      return _t(fr: 'Ce contenu n’existe plus, a expiré ou est privé.', en: 'This content no longer exists, has expired or is private.');
    case LinkProblem.tooManyRedirects:
      return _t(fr: 'Trop de redirections : le lien semble incorrect.', en: 'Too many redirects: the link looks wrong.');
    case LinkProblem.insecureRedirect:
      return _t(
        fr: 'Le lien redirige vers une adresse non sécurisée (http). Téléchargement refusé.',
        en: 'The link redirects to an insecure (http) address. Download refused.',
      );
    case LinkProblem.serverError:
      final code = error.statusCode == null ? '' : ' (${error.statusCode})';
      return _t(fr: 'Le serveur a répondu par une erreur$code. Réessayez plus tard.', en: 'The server answered with an error$code. Try again later.');
    case LinkProblem.network:
      return _t(fr: 'Connexion impossible. Vérifiez votre accès à Internet.', en: 'Could not connect. Check your Internet access.');
    case LinkProblem.timeout:
      return _t(fr: 'Le serveur ne répond pas.', en: 'The server is not responding.');
    case LinkProblem.tooLarge:
      return _t(
        fr: 'Fichier trop volumineux : sa taille n’est pas annoncée et dépasse 2 Go.',
        en: 'File too large: its size is not announced and exceeds 2 GB.',
      );
    case LinkProblem.notEnoughSpace:
      return _t(fr: 'Espace de stockage insuffisant sur l’appareil.', en: 'Not enough storage space on the device.');
    case LinkProblem.storage:
      return _t(fr: 'Impossible d’enregistrer le fichier.', en: 'Could not save the file.');
    case LinkProblem.githubSignInRequired:
      return _t(
        fr: 'GitHub ne donne les artefacts d’Actions qu’à un compte connecté. Connectez votre compte GitHub (jeton d’accès), ou ouvrez le lien dans le navigateur.',
        en: 'GitHub only serves Actions artifacts to a signed-in account. Connect your GitHub account (access token), or open the link in the browser.',
      );
    case LinkProblem.githubTokenInvalid:
      return _t(
        fr: 'GitHub a refusé votre jeton (révoqué ou expiré). Ajoutez un nouveau jeton.',
        en: 'GitHub refused your token (revoked or expired). Add a new token.',
      );
    case LinkProblem.githubNoAccess:
      return _t(
        fr: 'Votre jeton GitHub ne permet pas de lire les artefacts de ce dépôt. Donnez-lui l’accès « Actions : lecture » à ce dépôt.',
        en: 'Your GitHub token cannot read this repository’s artifacts. Give it “Actions: read” access to this repository.',
      );
    case LinkProblem.expired:
      return _t(
        fr: 'Ce contenu a expiré (un artefact GitHub est supprimé après sa durée de conservation).',
        en: 'This content has expired (a GitHub artifact is deleted after its retention period).',
      );
  }
}

class _SeveralLinksDialog extends StatefulWidget {
  const _SeveralLinksDialog();

  @override
  State<_SeveralLinksDialog> createState() => _SeveralLinksDialogState();
}

class _SeveralLinksDialogState extends State<_SeveralLinksDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_t(fr: 'Plusieurs liens', en: 'Several links')),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _t(fr: 'Un lien par ligne. Les fichiers sont ajoutés à la file d’attente.', en: 'One link per line. Files are added to the queue.'),
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _controller,
              minLines: 5,
              maxLines: 10,
              keyboardType: TextInputType.multiline,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                hintText: 'https://…\nhttps://…',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(_radius)),
              ),
            ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () async {
                  final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
                  if (text != null && text.trim().isNotEmpty) {
                    final current = _controller.text.trim();
                    _controller.text = current.isEmpty ? text.trim() : '$current\n${text.trim()}';
                  }
                },
                icon: const Icon(Icons.content_paste_rounded, size: 18),
                label: Text(_t(fr: 'Coller', en: 'Paste')),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(_t(fr: 'Annuler', en: 'Cancel'))),
        FilledButton(onPressed: () => Navigator.pop(context, _controller.text), child: Text(_t(fr: 'Ajouter', en: 'Add'))),
      ],
    );
  }
}

/// Download manager options.
/// Download manager options, in a dialog: its content scrolls within the
/// window height, even on small windows.
class _OptionsDialog extends StatelessWidget {
  const _OptionsDialog();

  @override
  Widget build(BuildContext context) {
    final settings = context.ref.watch(linkDownloadProvider.select((s) => s.settings));
    final service = context.ref.notifier(linkDownloadProvider);
    return AlertDialog(
      title: Text(_t(fr: 'Options de téléchargement', en: 'Download options')),
      scrollable: true,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(_t(fr: 'Fermer', en: 'Close'))),
      ],
      content: SizedBox(
        width: 520,
        child: Builder(
          builder: (context) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Stepper(
                title: _t(fr: 'Connexions par fichier', en: 'Connections per file'),
                subtitle: _t(
                  fr: 'Accélère les gros fichiers quand le serveur l’accepte (comme IDM).',
                  en: 'Speeds up large files when the server allows it (like IDM).',
                ),
                value: settings.connections,
                min: 1,
                max: maxConnectionsPerDownload,
                onChanged: (v) async => service.setConnections(v),
              ),
              const SizedBox(height: 12),
              _Stepper(
                title: _t(fr: 'Téléchargements simultanés', en: 'Simultaneous downloads'),
                subtitle: _t(fr: 'Les autres attendent dans la file.', en: 'The others wait in the queue.'),
                value: settings.parallel,
                min: 1,
                max: maxParallelDownloads,
                onChanged: (v) async => service.setParallel(v),
              ),
              const SizedBox(height: 12),
              const _GitHubAccountTile(),
              if (checkPlatformIsDesktop()) ...[
                const SizedBox(height: 12),
                const _BrowserBridgeTile(),
              ],
              if (checkPlatformIsDesktop() || checkPlatform([TargetPlatform.android])) ...[
                const SizedBox(height: 12),
                _SwitchRow(
                  value: settings.clipboardWatch,
                  onChanged: (v) async => service.setClipboardWatch(v),
                  title: Text(_t(fr: 'Détecter les liens copiés', en: 'Detect copied links'), style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    _t(
                      fr: checkPlatformIsDesktop()
                          ? 'Quand vous copiez un lien vers un fichier (.zip, .exe, .mp4…), Aika propose de le télécharger. Le presse-papiers reste sur cet appareil.'
                          : 'Copiez un lien vers un fichier (.apk, .zip, .mp4…) puis ouvrez Aika : le téléchargement est proposé. Android affiche alors « Aika a collé du contenu ».',
                      en: checkPlatformIsDesktop()
                          ? 'When you copy a link to a file (.zip, .exe, .mp4…), Aika offers to download it. The clipboard stays on this device.'
                          : 'Copy a link to a file (.apk, .zip, .mp4…), then open Aika: the download is offered. Android then shows “Aika pasted from your clipboard”.',
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  final String title;
  final String subtitle;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  const _Stepper({required this.title, required this.subtitle, required this.value, required this.min, required this.max, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(subtitle, style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13)),
            ],
          ),
        ),
        IconButton.outlined(
          onPressed: value > min ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove_rounded),
        ),
        SizedBox(
          width: 36,
          child: Text('$value', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        ),
        IconButton.outlined(
          onPressed: value < max ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add_rounded),
        ),
      ],
    );
  }
}

/// "Compte GitHub" in the options: used only to download GitHub Actions
/// artifacts through GitHub's official API.
class _GitHubAccountTile extends StatelessWidget {
  const _GitHubAccountTile();

  @override
  Widget build(BuildContext context) {
    final account = context.ref.watch(githubAccountProvider);
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_t(fr: 'Compte GitHub', en: 'GitHub account'), style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(
                account.connected
                    ? _t(fr: 'Connecté : @${account.login} (artefacts d’Actions)', en: 'Connected: @${account.login} (Actions artifacts)')
                    : _t(fr: 'Pour télécharger les artefacts de GitHub Actions.', en: 'To download GitHub Actions artifacts.'),
                style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
              ),
            ],
          ),
        ),
        if (account.connected)
          TextButton(
            onPressed: () async => context.ref.notifier(githubAccountProvider).disconnect(),
            child: Text(_t(fr: 'Déconnecter', en: 'Disconnect')),
          )
        else
          TextButton(
            onPressed: () async => showGitHubTokenDialog(context),
            child: Text(_t(fr: 'Connecter', en: 'Connect')),
          ),
      ],
    );
  }
}

/// Asks for a GitHub personal access token, checks it with GitHub and saves
/// it. Returns whether an account is now connected.
Future<bool> showGitHubTokenDialog(BuildContext context) async {
  final connected = await showDialog<bool>(context: context, builder: (_) => const _GitHubTokenDialog());
  return connected ?? false;
}

class _GitHubTokenDialog extends StatefulWidget {
  const _GitHubTokenDialog();

  @override
  State<_GitHubTokenDialog> createState() => _GitHubTokenDialogState();
}

class _GitHubTokenDialogState extends State<_GitHubTokenDialog> {
  final _controller = TextEditingController();
  bool _checking = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final login = await context.ref.notifier(githubAccountProvider).connect(_controller.text);
      if (!mounted) {
        return;
      }
      context.showSnackBar(_t(fr: 'Connecté à GitHub : @$login', en: 'Connected to GitHub: @$login'));
      Navigator.pop(context, true);
    } on GitHubConnectException catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _checking = false;
        _error = switch (e.error) {
          GitHubConnectError.malformed => _t(fr: 'Ce n’est pas un jeton GitHub valide.', en: 'This is not a valid GitHub token.'),
          GitHubConnectError.invalid => _t(fr: 'GitHub a refusé ce jeton.', en: 'GitHub refused this token.'),
          GitHubConnectError.network => _t(fr: 'Impossible de joindre GitHub. Vérifiez la connexion.', en: 'Could not reach GitHub. Check the connection.'),
          GitHubConnectError.storage => _t(
            fr: 'Le stockage sécurisé de cet appareil est indisponible : le jeton n’a pas été enregistré.',
            en: 'This device’s secure storage is unavailable: the token was not saved.',
          ),
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(_t(fr: 'Connecter GitHub', en: 'Connect GitHub')),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _t(
                fr: 'Créez un jeton d’accès « fine-grained » sur GitHub avec, pour les dépôts voulus, la seule permission « Actions : lecture », puis collez-le ici.',
                en: 'Create a fine-grained access token on GitHub with only the “Actions: read” permission for the repositories you need, then paste it here.',
              ),
              style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
            ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () async => launchUrl(
                  Uri.parse('https://github.com/settings/personal-access-tokens/new'),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: Text(_t(fr: 'Créer un jeton sur GitHub', en: 'Create a token on GitHub')),
              ),
            ),
            TextField(
              controller: _controller,
              obscureText: _obscure,
              autocorrect: false,
              enableSuggestions: false,
              onSubmitted: (_) async => _submit(),
              decoration: InputDecoration(
                labelText: _t(fr: 'Jeton d’accès', en: 'Access token'),
                hintText: 'github_pat_…',
                errorText: _error,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(_radius)),
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _t(
                fr: 'Le jeton est chiffré sur cet appareil et envoyé uniquement à api.github.com. Vous pouvez le retirer à tout moment.',
                en: 'The token is encrypted on this device and only sent to api.github.com. You can remove it at any time.',
              ),
              style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _checking ? null : () => Navigator.pop(context, false), child: Text(_t(fr: 'Annuler', en: 'Cancel'))),
        FilledButton(
          onPressed: _checking ? null : () async => _submit(),
          child: _checking
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.4))
              : Text(_t(fr: 'Vérifier et enregistrer', en: 'Verify and save')),
        ),
      ],
    );
  }
}

/// "Intégration navigateur": downloads clicked in Chrome / Edge are taken
/// over by Aika through the Aika extension (computers only).
class _BrowserBridgeTile extends StatelessWidget {
  const _BrowserBridgeTile();

  @override
  Widget build(BuildContext context) {
    final (enabled, token, running) = context.ref.watch(
      linkDownloadProvider.select((s) => (s.settings.browserBridge, s.settings.bridgeToken, s.bridgeRunning)),
    );
    final service = context.ref.notifier(linkDownloadProvider);
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SwitchRow(
          value: enabled,
          onChanged: (v) async => service.setBrowserBridge(v),
          title: Text(_t(fr: 'Intégration navigateur', en: 'Browser integration'), style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(
            _t(
              fr: 'Avec l’extension Aika pour Chrome / Edge, les téléchargements cliqués dans le navigateur sont repris par Aika (multi-connexions, pause, reprise).',
              en: 'With the Aika extension for Chrome / Edge, downloads clicked in the browser are taken over by Aika (multiple connections, pause, resume).',
            ),
          ),
        ),
        if (enabled) ...[
          Text(
            running
                ? _t(fr: 'Actif sur cet ordinateur (port $browserBridgePort).', en: 'Active on this computer (port $browserBridgePort).')
                : _t(
                    fr: 'Inactif : le port $browserBridgePort est déjà utilisé par une autre application.',
                    en: 'Inactive: port $browserBridgePort is already used by another app.',
                  ),
            style: TextStyle(color: running ? colorScheme.primary : colorScheme.error, fontSize: 13),
          ),
          const SizedBox(height: 10),
          Text(_t(fr: 'Code d’appairage (à saisir dans l’extension)', en: 'Pairing code (to type in the extension)'), style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(_radius),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: Row(
              children: [
                Expanded(
                  child: SelectableText(
                    token,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 1.5),
                  ),
                ),
                IconButton(
                  tooltip: _t(fr: 'Copier', en: 'Copy'),
                  icon: const Icon(Icons.copy_rounded),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: token));
                    if (context.mounted) {
                      context.showSnackBar(_t(fr: 'Code copié', en: 'Code copied'));
                    }
                  },
                ),
                IconButton(
                  tooltip: _t(fr: 'Nouveau code', en: 'New code'),
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: () async => service.regenerateBridgeToken(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _t(
              fr: 'Installation : dossier « browser_extension » du projet → chrome://extensions (ou edge://extensions) → Mode développeur → « Charger l’extension non empaquetée ».',
              en: 'Install: the project’s “browser_extension” folder → chrome://extensions (or edge://extensions) → Developer mode → “Load unpacked”.',
            ),
            style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
          ),
        ],
      ],
    );
  }
}

/// Title, wrapping description and a switch. Unlike SwitchListTile, its
/// height follows the text, so long descriptions never overflow.
class _SwitchRow extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final Widget title;
  final Widget subtitle;

  const _SwitchRow({required this.value, required this.onChanged, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(_radius),
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  title,
                  const SizedBox(height: 2),
                  DefaultTextStyle.merge(
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                    child: subtitle,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}
