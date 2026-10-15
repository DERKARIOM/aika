import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/collections/collections_database.dart';
import 'package:localsend_app/pages/link_download_page.dart' show formatBytes;
import 'package:localsend_app/pages/tabs/collections_tab.dart';
import 'package:localsend_app/provider/collections_provider.dart';
import 'package:localsend_app/util/native/open_file.dart';
import 'package:localsend_app/widget/collections/collection_widgets.dart';
import 'package:localsend_app/widget/custom_basic_appbar.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

String _t({required String fr, required String en}) => LocaleSettings.currentLocale == AppLocale.fr ? fr : en;

/// Contents of one collection: grid of files, selection, and the two
/// actions "Partager par lien" / "Envoyer vers un appareil".
class CollectionPage extends StatefulWidget {
  final String collectionId;

  const CollectionPage({required this.collectionId});

  @override
  State<CollectionPage> createState() => _CollectionPageState();
}

class _CollectionPageState extends State<CollectionPage> {
  List<CollectionItem>? _items;

  /// Ids of the selected items; selection mode when not empty.
  final _selected = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async => _reload());
  }

  Future<void> _reload() async {
    final items = await context.ref.notifier(collectionsProvider).items(widget.collectionId);
    if (mounted) {
      setState(() {
        _items = items;
        _selected.retainAll(items.map((i) => i.id));
      });
    }
  }

  List<CollectionItem> get _selectedItems => (_items ?? const []).where((i) => _selected.contains(i.id)).toList();

  /// Selected items, or all of them when nothing is selected.
  List<CollectionItem> get _actionItems => _selected.isEmpty ? (_items ?? const []) : _selectedItems;

  void _toggle(CollectionItem item) {
    setState(() => _selected.contains(item.id) ? _selected.remove(item.id) : _selected.add(item.id));
  }

  Future<void> _addFiles() async {
    final files = await pickFilesForCollection(context);
    if (files.isEmpty || !mounted) {
      return;
    }
    await addPickedFilesToCollection(context, widget.collectionId, files);
    await _reload();
  }

  Future<void> _removeSelected() async {
    final items = _selectedItems;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_t(fr: 'Retirer ${formatItemCount(items.length)} ?', en: 'Remove ${formatItemCount(items.length)}?')),
        content: Text(
          _t(
            fr: 'Ils sont retirés de la collection. Vos fichiers d’origine ne sont pas supprimés.',
            en: 'They are removed from the collection. Your original files are not deleted.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(_t(fr: 'Annuler', en: 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(_t(fr: 'Retirer', en: 'Remove'))),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await context.ref.notifier(collectionsProvider).removeItems(widget.collectionId, items);
    _selected.clear();
    await _reload();
  }

  Future<void> _setCover() async {
    await context.ref.notifier(collectionsProvider).setCover(widget.collectionId, _selected.first);
    if (mounted) {
      setState(_selected.clear);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_t(fr: 'Couverture modifiée.', en: 'Cover changed.'))));
    }
  }

  Future<void> _open(CollectionItem item) async {
    final files = await context.ref.notifier(collectionsProvider).resolveFiles([item]);
    if (!mounted) {
      return;
    }
    final path = files.files.isEmpty ? null : files.files.first.path;
    if (path == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t(fr: 'Ce fichier n’est plus disponible.', en: 'This file is no longer available.'))),
      );
      return;
    }
    await openFile(context, item.fileType, path);
  }

  Future<void> _send() async {
    await sendCollectionItems(context, widget.collectionId, _actionItems);
    await _reload();
  }

  Future<void> _share() async {
    await shareCollectionByLink(context, widget.collectionId, _actionItems);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final summary = context.ref.watch(
      collectionsProvider.select((s) => s.collections.where((c) => c.id == widget.collectionId).firstOrNull),
    );
    final items = _items;
    final selecting = _selected.isNotEmpty;

    return PopScope(
      canPop: !selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          setState(_selected.clear); // Back leaves the selection first.
        }
      },
      child: Scaffold(
        appBar: selecting ? _selectionBar(items ?? const []) : _normalBar(summary),
        body: SafeArea(
          child: items == null
              ? const Center(child: CircularProgressIndicator())
              : items.isEmpty
              ? _EmptyCollection(onAdd: _addFiles)
              : _ItemGrid(
                  items: items,
                  description: summary?.description,
                  selected: _selected,
                  onTap: (item) async {
                    if (selecting) {
                      _toggle(item);
                    } else {
                      await _open(item);
                    }
                  },
                  onLongPress: _toggle,
                ),
        ),
        bottomNavigationBar: items == null || items.isEmpty ? null : _BottomActions(count: _actionItems.length, onShare: _share, onSend: _send),
      ),
    );
  }

  PreferredSizeWidget _normalBar(CollectionSummary? summary) {
    if (summary == null) {
      return basicAikaAppbar('');
    }
    return AppBar(
      title: Text(summary.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      actions: [
        IconButton(
          tooltip: _t(fr: 'Ajouter des fichiers', en: 'Add files'),
          onPressed: _addFiles,
          icon: const Icon(Icons.add_photo_alternate_outlined),
        ),
        PopupMenuButton<String>(
          onSelected: (value) async {
            if (value == 'edit') {
              await editCollectionInfo(context, summary);
            } else if (value == 'reorder') {
              await context.push(() => _ReorderPage(collectionId: widget.collectionId, items: _items ?? const []));
              await _reload();
            } else if (value == 'delete' && await deleteCollectionFlow(context, summary) && mounted) {
              context.pop();
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(value: 'edit', child: Text(_t(fr: 'Modifier le nom et la description', en: 'Edit name and description'))),
            if ((_items?.length ?? 0) > 1) PopupMenuItem(value: 'reorder', child: Text(_t(fr: 'Réorganiser les fichiers', en: 'Reorder files'))),
            PopupMenuItem(value: 'delete', child: Text(_t(fr: 'Supprimer la collection', en: 'Delete collection'))),
          ],
        ),
      ],
    );
  }

  PreferredSizeWidget _selectionBar(List<CollectionItem> items) {
    final allSelected = _selected.length == items.length;
    return AppBar(
      leading: IconButton(
        tooltip: _t(fr: 'Annuler la sélection', en: 'Cancel selection'),
        onPressed: () => setState(_selected.clear),
        icon: const Icon(Icons.close_rounded),
      ),
      title: Text(_t(fr: '${_selected.length} sélectionné(s)', en: '${_selected.length} selected')),
      actions: [
        IconButton(
          tooltip: allSelected ? _t(fr: 'Tout désélectionner', en: 'Deselect all') : _t(fr: 'Tout sélectionner', en: 'Select all'),
          onPressed: () => setState(() => allSelected ? _selected.clear() : _selected.addAll(items.map((i) => i.id))),
          icon: Icon(allSelected ? Icons.deselect_rounded : Icons.select_all_rounded),
        ),
        if (_selected.length == 1)
          IconButton(
            tooltip: _t(fr: 'Définir comme couverture', en: 'Set as cover'),
            onPressed: _setCover,
            icon: const Icon(Icons.wallpaper_rounded),
          ),
        IconButton(
          tooltip: _t(fr: 'Retirer de la collection', en: 'Remove from collection'),
          onPressed: _removeSelected,
          icon: const Icon(Icons.delete_outline_rounded),
        ),
      ],
    );
  }
}

class _ItemGrid extends StatelessWidget {
  final List<CollectionItem> items;
  final String? description;
  final Set<String> selected;
  final void Function(CollectionItem) onTap;
  final void Function(CollectionItem) onLongPress;

  const _ItemGrid({required this.items, required this.description, required this.selected, required this.onTap, required this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalSize = items.fold<int>(0, (sum, i) => sum + i.size);
    final description = this.description;
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (description != null && description.isNotEmpty) ...[
                  Text(description, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 6),
                ],
                Text(
                  '${formatItemCount(items.length)} · ${formatBytes(totalSize)}',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 160,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
            ),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return _ItemTile(
                key: ValueKey(item.id),
                item: item,
                selected: selected.contains(item.id),
                selecting: selected.isNotEmpty,
                onTap: () => onTap(item),
                onLongPress: () => onLongPress(item),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ItemTile extends StatelessWidget {
  final CollectionItem item;
  final bool selected;
  final bool selecting;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _ItemTile({required this.item, required this.selected, required this.selecting, required this.onTap, required this.onLongPress, super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      label: item.name,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(collectionRadius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedPadding(
              duration: const Duration(milliseconds: 120),
              padding: EdgeInsets.all(selected ? 6 : 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(selected ? collectionRadius - 2 : 0),
                child: CollectionThumbnail(item: item),
              ),
            ),
            if (!item.isMedia)
              Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  width: double.infinity,
                  color: colorScheme.surface.withValues(alpha: 0.85),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                ),
              ),
            if (selecting)
              Positioned(
                top: 6,
                right: 6,
                child: Icon(
                  selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                  color: selected ? colorScheme.primary : Colors.white,
                  shadows: const [Shadow(blurRadius: 4)],
                ),
              ),
            Material(
              type: MaterialType.transparency,
              child: InkWell(onTap: onTap, onLongPress: onLongPress),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyCollection extends StatelessWidget {
  final VoidCallback onAdd;

  const _EmptyCollection({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_photo_alternate_outlined, size: 56, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(_t(fr: 'Cette collection est vide.', en: 'This collection is empty.'), style: theme.textTheme.titleMedium),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onAdd,
              style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(collectionRadius))),
              icon: const Icon(Icons.add_rounded),
              label: Text(_t(fr: 'Ajouter des fichiers', en: 'Add files')),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomActions extends StatelessWidget {
  final int count;
  final VoidCallback onShare;
  final VoidCallback onSend;

  const _BottomActions({required this.count, required this.onShare, required this.onSend});

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(collectionRadius));
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onShare,
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50), shape: shape),
                icon: const Icon(Icons.link_rounded),
                label: Text(_t(fr: 'Partager par lien', en: 'Share by link'), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: onSend,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50), shape: shape),
                icon: const Icon(Icons.send_rounded),
                label: Text(
                  _t(fr: 'Envoyer ($count)', en: 'Send ($count)'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Réorganiser": drag the files into the order used for sending and
/// sharing. Each move is saved right away.
class _ReorderPage extends StatefulWidget {
  final String collectionId;
  final List<CollectionItem> items;

  const _ReorderPage({required this.collectionId, required this.items});

  @override
  State<_ReorderPage> createState() => _ReorderPageState();
}

class _ReorderPageState extends State<_ReorderPage> {
  late final List<CollectionItem> _items = [...widget.items];

  Future<void> _onReorder(int oldIndex, int newIndex) async {
    final target = newIndex > oldIndex ? newIndex - 1 : newIndex;
    final item = _items[oldIndex];
    setState(() => _items.insert(target, _items.removeAt(oldIndex)));
    await context.ref.notifier(collectionsProvider).moveItem(widget.collectionId, item.id, target);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: basicAikaAppbar(_t(fr: 'Réorganiser', en: 'Reorder')),
      body: SafeArea(
        child: ReorderableListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: _items.length,
          onReorder: _onReorder,
          buildDefaultDragHandles: false,
          itemBuilder: (context, index) {
            final item = _items[index];
            return ListTile(
              key: ValueKey(item.id),
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(collectionRadius - 4),
                child: SizedBox.square(dimension: 48, child: CollectionThumbnail(item: item, cacheSize: 144)),
              ),
              title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(formatBytes(item.size), style: TextStyle(color: colorScheme.onSurfaceVariant)),
              trailing: ReorderableDragStartListener(index: index, child: const Icon(Icons.drag_handle_rounded)),
            );
          },
        ),
      ),
    );
  }
}
