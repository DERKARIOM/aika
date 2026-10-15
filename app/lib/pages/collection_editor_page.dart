import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/collections/collections_database.dart';
import 'package:localsend_app/model/cross_file.dart';
import 'package:localsend_app/pages/link_download_page.dart' show formatBytes;
import 'package:localsend_app/provider/collections_provider.dart';
import 'package:localsend_app/util/file_type_ext.dart';
import 'package:localsend_app/widget/collections/collection_widgets.dart';
import 'package:localsend_app/widget/custom_basic_appbar.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

String _t({required String fr, required String en}) => LocaleSettings.currentLocale == AppLocale.fr ? fr : en;

/// "Nouvelle collection": name, description and first files. Pops with
/// the id of the created collection.
class CollectionEditorPage extends StatefulWidget with PopsWithResult<String> {
  const CollectionEditorPage();

  @override
  State<CollectionEditorPage> createState() => _CollectionEditorPageState();
}

class _CollectionEditorPageState extends State<CollectionEditorPage> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _files = <CrossFile>[];
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _addFiles() async {
    final picked = await pickFilesForCollection(context);
    if (picked.isNotEmpty && mounted) {
      setState(() => _files.addAll(picked));
    }
  }

  Future<void> _create() async {
    if (_saving || _name.text.trim().isEmpty) {
      return;
    }
    setState(() => _saving = true);
    final service = context.ref.notifier(collectionsProvider);
    try {
      final id = await service.create(name: _name.text, description: _description.text);
      if (_files.isNotEmpty && mounted) {
        await addPickedFilesToCollection(context, id, _files);
      }
      if (mounted) {
        widget.popWithResult(context, id);
      }
    } on InvalidCollectionException catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final totalSize = _files.fold<int>(0, (sum, f) => sum + f.size);

    return Scaffold(
      appBar: basicAikaAppbar(_t(fr: 'Nouvelle collection', en: 'New collection')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                CollectionInfoFields(name: _name, description: _description),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _files.isEmpty
                            ? _t(fr: 'Fichiers', en: 'Files')
                            : '${formatItemCount(_files.length)} · ${formatBytes(totalSize)}',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (_files.isNotEmpty)
                      TextButton(
                        onPressed: () => setState(_files.clear),
                        child: Text(_t(fr: 'Tout retirer', en: 'Remove all')),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _saving ? null : _addFiles,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(collectionRadius)),
                  ),
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: Text(_t(fr: 'Ajouter des fichiers', en: 'Add files')),
                ),
                if (_files.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _t(
                        fr: 'Facultatif : vous pourrez en ajouter plus tard.',
                        en: 'Optional: you can add more later.',
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ),
                const SizedBox(height: 8),
                for (var i = 0; i < _files.length && i < 200; i++) _PickedFileRow(file: _files[i], onRemove: () => setState(() => _files.removeAt(i))),
                if (_files.length > 200)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(_t(fr: '… et ${_files.length - 200} autres', en: '… and ${_files.length - 200} more')),
                  ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: ValueListenableBuilder<TextEditingValue>(
            valueListenable: _name,
            builder: (context, value, _) => FilledButton(
              onPressed: _saving || value.text.trim().isEmpty ? null : _create,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(collectionRadius)),
                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              child: _saving
                  ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                  : Text(_t(fr: 'Créer la collection', en: 'Create the collection')),
            ),
          ),
        ),
      ),
    );
  }
}

class _PickedFileRow extends StatelessWidget {
  final CrossFile file;
  final VoidCallback onRemove;

  const _PickedFileRow({required this.file, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(file.fileType.icon, color: colorScheme.primary),
      title: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(formatBytes(file.size)),
      trailing: IconButton(
        tooltip: _t(fr: 'Retirer', en: 'Remove'),
        onPressed: onRemove,
        icon: const Icon(Icons.close_rounded),
      ),
    );
  }
}
