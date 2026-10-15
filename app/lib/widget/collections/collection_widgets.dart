import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:localsend_app/config/theme.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/collections/collections_database.dart';
import 'package:localsend_app/model/cross_file.dart';
import 'package:localsend_app/pages/link_download_page.dart' show formatBytes;
import 'package:localsend_app/pages/web_send_page.dart';
import 'package:localsend_app/provider/collections_provider.dart';
import 'package:localsend_app/provider/selection/selected_sending_files_provider.dart';
import 'package:localsend_app/util/file_type_ext.dart';
import 'package:localsend_app/util/native/channel/android_channel.dart' as android_channel;
import 'package:localsend_app/util/native/cross_file_converters.dart';
import 'package:localsend_app/util/native/pick_directory_path.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_app/util/ui/asset_picker_translated_text_delegate.dart';
import 'package:localsend_app/widget/dialogs/custom_bottom_sheet.dart';
import 'package:localsend_app/widget/dialogs/loading_dialog.dart';
import 'package:localsend_app/widget/dialogs/send_target_sheet.dart';
import 'package:localsend_isolates/model/file_type.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

final _logger = Logger('CollectionWidgets');

String _t({required String fr, required String en}) => LocaleSettings.currentLocale == AppLocale.fr ? fr : en;

/// Corner radius of the collection screens (same as the home page).
const collectionRadius = 10.0;

/// Most files taken from one picked folder.
const _maxFolderFiles = 5000;

/// `12/10/2026`.
String formatCollectionDate(DateTime date) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(date.day)}/${two(date.month)}/${date.year}';
}

/// "1 élément" / "48 éléments".
String formatItemCount(int count) =>
    _t(fr: count <= 1 ? '$count élément' : '$count éléments', en: count == 1 ? '$count item' : '$count items');

// ---------------------------------------------------------------------------
// Thumbnails
// ---------------------------------------------------------------------------

/// Gallery entries resolved once per id (rebuilds never query again).
final _assetCache = <String, Future<AssetEntity?>>{};

/// Square thumbnail of an item, decoded at a small size (never the full
/// image in memory). Documents show the icon of their type.
class CollectionThumbnail extends StatelessWidget {
  final CollectionItem? item;

  /// Decoding size in physical pixels.
  final int cacheSize;

  const CollectionThumbnail({required this.item, this.cacheSize = 320});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final item = this.item;
    final placeholder = ColoredBox(
      color: colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(item == null ? Icons.photo_library_outlined : item.fileType.icon, color: colorScheme.onSurfaceVariant, size: 30),
      ),
    );
    if (item == null || !item.isMedia) {
      return placeholder;
    }
    if (item.source == CollectionItemSource.asset) {
      return FutureBuilder<AssetEntity?>(
        future: _assetCache.putIfAbsent(item.location, () => AssetEntity.fromId(item.location)),
        builder: (context, snapshot) {
          final asset = snapshot.data;
          if (asset == null) {
            return placeholder;
          }
          return _withVideoBadge(
            item,
            Image(
              image: AssetEntityImageProvider(asset, isOriginal: false, thumbnailSize: const ThumbnailSize.square(300)),
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => placeholder,
            ),
          );
        },
      );
    }
    if (item.fileType == FileType.image) {
      return Image.file(
        File(item.location),
        fit: BoxFit.cover,
        cacheWidth: cacheSize, // Small decode: low memory, fast scrolling.
        errorBuilder: (_, _, _) => placeholder,
      );
    }
    return _withVideoBadge(item, placeholder);
  }

  Widget _withVideoBadge(CollectionItem item, Widget child) {
    if (item.fileType != FileType.video) {
      return child;
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        const Align(
          alignment: Alignment.bottomLeft,
          child: Padding(
            padding: EdgeInsets.all(4),
            child: Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 20, shadows: [Shadow(blurRadius: 4)]),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Picking files
// ---------------------------------------------------------------------------

enum _PickSource { media, files, folder }

/// Lets the user pick files to add to a collection with the platform's
/// pickers (gallery, documents, folder on computers). Independent of the
/// Send selection, so nothing there is changed or cleared.
Future<List<CrossFile>> pickFilesForCollection(BuildContext context) async {
  final sources = [
    if (!checkPlatformIsDesktop()) _PickSource.media,
    _PickSource.files,
    if (checkPlatformIsDesktop()) _PickSource.folder,
  ];
  final source = sources.length == 1 ? sources.first : await context.pushBottomSheet(() => _PickSourceSheet(sources));
  if (source is! _PickSource || !context.mounted) {
    return const [];
  }
  try {
    switch (source) {
      case _PickSource.media:
        return await _pickMedia(context);
      case _PickSource.files:
        return await _pickFiles(context);
      case _PickSource.folder:
        return await _pickFolder(context);
    }
  } on PlatformException catch (e) {
    if (e.code != 'CANCELED') {
      _logger.warning('Could not pick files', e);
    }
    return const [];
  } catch (e) {
    _logger.warning('Could not pick files', e);
    return const [];
  }
}

Future<List<CrossFile>> _pickMedia(BuildContext context) async {
  if (checkPlatform([TargetPlatform.android])) {
    await PhotoManager.requestPermissionExtend(
      requestOption: const PermissionRequestOption(
        androidPermission: AndroidPermission(type: RequestType.common, mediaLocation: true),
      ),
    );
  }
  if (!context.mounted) {
    return const [];
  }
  final oldBrightness = Theme.of(context).brightness;
  final assets = await AssetPicker.pickAssets(
    context,
    pickerConfig: const AssetPickerConfig(maxAssets: 999, textDelegate: TranslatedAssetPickerTextDelegate()),
  );
  // The picker changes the system bars; restore them like the Send tab.
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (context.mounted) {
      await updateSystemOverlayStyleWithBrightness(oldBrightness);
    }
  });
  if (assets == null || assets.isEmpty || !context.mounted) {
    return const [];
  }
  return _withLoading(context, assets.length, () async {
    final files = <CrossFile>[];
    for (final asset in assets) {
      // Sequential, like the Send selection (photo_manager limitation).
      files.add(await CrossFileConverters.convertAssetEntity(asset));
    }
    return files;
  });
}

Future<List<CrossFile>> _pickFiles(BuildContext context) async {
  if (checkPlatform([TargetPlatform.android])) {
    final picked = await android_channel.pickFilesAndroid();
    if (picked == null || picked.isEmpty || !context.mounted) {
      return const [];
    }
    return _withLoading(context, picked.length, () => Future.wait(picked.map(CrossFileConverters.convertFileInfo)));
  }
  final picked = await openFiles();
  if (picked.isEmpty || !context.mounted) {
    return const [];
  }
  return _withLoading(context, picked.length, () => Future.wait(picked.map(CrossFileConverters.convertXFile)));
}

Future<List<CrossFile>> _pickFolder(BuildContext context) async {
  final folder = await pickDirectoryPath();
  if (folder == null || !context.mounted) {
    return const [];
  }
  return _withLoading(context, null, () async {
    final files = <CrossFile>[];
    await for (final entity in Directory(folder).list(recursive: true, followLinks: false).handleError((Object e) => _logger.fine('Skipped: $e'))) {
      if (entity is! File || p.basename(entity.path).startsWith('.')) {
        continue;
      }
      files.add(await CrossFileConverters.convertFile(entity));
      if (files.length >= _maxFolderFiles) {
        break;
      }
    }
    return files;
  });
}

/// Shows Aika's loading card while [work] runs.
Future<T> _withLoading<T>(BuildContext context, int? fileCount, Future<T> Function() work) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = DialogRoute<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black54,
    builder: (_) => LoadingDialog(fileCount: fileCount),
  );
  unawaited(navigator.push(route));
  try {
    return await work();
  } finally {
    if (route.isActive) {
      navigator.removeRoute(route);
    }
  }
}

class _PickSourceSheet extends StatelessWidget {
  final List<_PickSource> sources;

  const _PickSourceSheet(this.sources);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return CustomBottomSheet(
      title: _t(fr: 'Ajouter des fichiers', en: 'Add files'),
      description: _t(fr: 'Images, vidéos, documents : tous les types sont acceptés.', en: 'Images, videos, documents: every type is accepted.'),
      child: Column(
        children: [
          for (final source in sources)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: colorScheme.surfaceContainerHigh,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(collectionRadius),
                  side: BorderSide(color: colorScheme.outlineVariant),
                ),
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  leading: Icon(
                    switch (source) {
                      _PickSource.media => Icons.photo_library_rounded,
                      _PickSource.files => Icons.description_rounded,
                      _PickSource.folder => Icons.folder_rounded,
                    },
                    color: colorScheme.primary,
                  ),
                  title: Text(switch (source) {
                    _PickSource.media => _t(fr: 'Photos et vidéos', en: 'Photos and videos'),
                    _PickSource.files => _t(fr: 'Fichiers et documents', en: 'Files and documents'),
                    _PickSource.folder => _t(fr: 'Un dossier entier', en: 'A whole folder'),
                  }),
                  onTap: () => context.pop(source),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Adds picked files to a collection with the loading card and clear
/// errors. Returns the number of files added.
Future<int> addPickedFilesToCollection(BuildContext context, String collectionId, List<CrossFile> files) async {
  if (files.isEmpty) {
    return 0;
  }
  final service = context.ref.notifier(collectionsProvider);
  try {
    final added = await _withLoading(context, files.length, () => service.addFiles(collectionId, files));
    if (context.mounted && added < files.length) {
      _snack(context, _t(fr: '$added fichier(s) ajouté(s), ${files.length - added} illisible(s).', en: '$added file(s) added, ${files.length - added} unreadable.'));
    }
    return added;
  } on CollectionsException catch (e) {
    if (context.mounted) {
      _snack(
        context,
        e.problem == CollectionsProblem.notEnoughSpace
            ? _t(fr: 'Espace insuffisant pour copier ces fichiers dans Aika.', en: 'Not enough space to copy these files into Aika.')
            : _t(fr: 'Ces fichiers ne peuvent pas être lus.', en: 'These files cannot be read.'),
      );
    }
    return 0;
  }
}

void _snack(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..removeCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

// ---------------------------------------------------------------------------
// Dialogs
// ---------------------------------------------------------------------------

/// Name and description of a collection (create / edit).
class CollectionInfo {
  final String name;
  final String? description;

  const CollectionInfo(this.name, this.description);
}

Future<CollectionInfo?> showCollectionInfoDialog(BuildContext context, {required String title, String? name, String? description}) {
  return showDialog<CollectionInfo>(
    context: context,
    builder: (_) => _CollectionInfoDialog(title: title, name: name, description: description),
  );
}

class _CollectionInfoDialog extends StatefulWidget {
  final String title;
  final String? name;
  final String? description;

  const _CollectionInfoDialog({required this.title, this.name, this.description});

  @override
  State<_CollectionInfoDialog> createState() => _CollectionInfoDialogState();
}

class _CollectionInfoDialogState extends State<_CollectionInfoDialog> {
  late final _name = TextEditingController(text: widget.name);
  late final _description = TextEditingController(text: widget.description);

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  void _submit() {
    if (_name.text.trim().isEmpty) {
      return;
    }
    Navigator.pop(context, CollectionInfo(_name.text, _description.text));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      scrollable: true,
      content: SizedBox(
        width: 440,
        child: CollectionInfoFields(name: _name, description: _description, onSubmitted: _submit),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(_t(fr: 'Annuler', en: 'Cancel'))),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _name,
          builder: (context, value, _) => FilledButton(
            onPressed: value.text.trim().isEmpty ? null : _submit,
            child: Text(_t(fr: 'Enregistrer', en: 'Save')),
          ),
        ),
      ],
    );
  }
}

/// Name (required) and description (optional) fields.
class CollectionInfoFields extends StatelessWidget {
  final TextEditingController name;
  final TextEditingController description;
  final VoidCallback? onSubmitted;

  const CollectionInfoFields({required this.name, required this.description, this.onSubmitted});

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(borderRadius: BorderRadius.circular(collectionRadius));
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: name,
          autofocus: true,
          maxLength: maxCollectionNameLength,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: _t(fr: 'Nom de la collection', en: 'Collection name'),
            hintText: _t(fr: 'Photos de famille', en: 'Family photos'),
            border: border,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: description,
          maxLength: maxCollectionDescriptionLength,
          minLines: 2,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: (_) => onSubmitted?.call(),
          decoration: InputDecoration(
            labelText: _t(fr: 'Description (facultatif)', en: 'Description (optional)'),
            border: border,
          ),
        ),
      ],
    );
  }
}

/// Confirms deleting a collection; returns `null` when cancelled, else
/// whether Aika's copies must be deleted too.
Future<bool?> confirmDeleteCollection(BuildContext context, {required String name, required int copiesBytes}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => _DeleteCollectionDialog(name: name, copiesBytes: copiesBytes),
  );
}

class _DeleteCollectionDialog extends StatefulWidget {
  final String name;
  final int copiesBytes;

  const _DeleteCollectionDialog({required this.name, required this.copiesBytes});

  @override
  State<_DeleteCollectionDialog> createState() => _DeleteCollectionDialogState();
}

class _DeleteCollectionDialogState extends State<_DeleteCollectionDialog> {
  bool _deleteCopies = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(_t(fr: 'Supprimer « ${widget.name} » ?', en: 'Delete “${widget.name}”?')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _t(
              fr: 'La collection est supprimée. Vos fichiers d’origine ne sont pas touchés.',
              en: 'The collection is deleted. Your original files are not touched.',
            ),
          ),
          if (widget.copiesBytes > 0) ...[
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _deleteCopies,
              onChanged: (v) => setState(() => _deleteCopies = v ?? false),
              title: Text(
                _t(
                  fr: 'Supprimer aussi les copies Aika (${formatBytes(widget.copiesBytes)})',
                  en: 'Also delete Aika’s copies (${formatBytes(widget.copiesBytes)})',
                ),
              ),
              subtitle: Text(
                _t(fr: 'Documents copiés dans Aika lors de l’ajout.', en: 'Documents copied into Aika when added.'),
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(_t(fr: 'Annuler', en: 'Cancel'))),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: colorScheme.error, foregroundColor: colorScheme.onError),
          onPressed: () => Navigator.pop(context, _deleteCopies),
          child: Text(_t(fr: 'Supprimer', en: 'Delete')),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Send to a device / share by link (existing flows)
// ---------------------------------------------------------------------------

/// Files of [items] that can still be read; when some are missing, the
/// user chooses to remove them from the collection, continue without them
/// or cancel (`null`).
Future<List<CrossFile>?> _resolveForAction(BuildContext context, String collectionId, List<CollectionItem> items) async {
  final service = context.ref.notifier(collectionsProvider);
  final resolved = await _withLoading(context, items.length, () => service.resolveFiles(items));
  if (resolved.missing.isEmpty || !context.mounted) {
    return resolved.files;
  }
  final choice = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(_t(fr: 'Fichiers introuvables', en: 'Files not found')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _t(
              fr: '${resolved.missing.length} fichier(s) ont été supprimés, déplacés, ou ne sont plus accessibles :',
              en: '${resolved.missing.length} file(s) were deleted, moved, or are no longer accessible:',
            ),
          ),
          const SizedBox(height: 6),
          for (final item in resolved.missing.take(5)) Text('• ${item.name}', maxLines: 1, overflow: TextOverflow.ellipsis),
          if (resolved.missing.length > 5) Text('…'),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(_t(fr: 'Annuler', en: 'Cancel'))),
        TextButton(onPressed: () => Navigator.pop(context, 'remove'), child: Text(_t(fr: 'Les retirer', en: 'Remove them'))),
        if (resolved.files.isNotEmpty)
          FilledButton(onPressed: () => Navigator.pop(context, 'continue'), child: Text(_t(fr: 'Continuer sans eux', en: 'Continue without them'))),
      ],
    ),
  );
  if (choice == 'remove') {
    await service.removeItems(collectionId, resolved.missing);
    return resolved.files.isEmpty ? null : resolved.files;
  }
  return choice == 'continue' ? resolved.files : null;
}

/// "Envoyer vers un appareil": hands the items to the usual send flow
/// (same selection, same device list, same transfer protocol).
Future<void> sendCollectionItems(BuildContext context, String collectionId, List<CollectionItem> items) async {
  final files = await _resolveForAction(context, collectionId, items);
  if (files == null || files.isEmpty || !context.mounted) {
    return;
  }
  // Replaces the Send selection without clearing Aika's cache: the files
  // just resolved (e.g. a gallery video exported by the system) must stay.
  context.ref.redux(selectedSendingFilesProvider).dispatch(_ReplaceSelectionAction(files));
  if (context.mounted) {
    await pickTargetAndSend(context);
  }
}

/// "Partager par lien": opens the existing web share page with the items
/// (same server, PIN, visitor approval and HTTPS options).
Future<void> shareCollectionByLink(BuildContext context, String collectionId, List<CollectionItem> items) async {
  final files = await _resolveForAction(context, collectionId, items);
  if (files == null || files.isEmpty || !context.mounted) {
    return;
  }
  final service = context.ref.notifier(collectionsProvider);
  service.markShared(collectionId);
  try {
    await context.push(() => WebSendPage(files));
  } finally {
    service.markShared(null);
  }
}

/// Sets the Send selection to [files] (no cache clean-up, unlike
/// [ClearSelectionAction]).
class _ReplaceSelectionAction extends ReduxAction<SelectedSendingFilesNotifier, List<CrossFile>> {
  final List<CrossFile> files;

  _ReplaceSelectionAction(this.files);

  @override
  List<CrossFile> reduce() => List<CrossFile>.unmodifiable(files);
}
