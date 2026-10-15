import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/collections/collections_database.dart';
import 'package:localsend_app/pages/collection_editor_page.dart';
import 'package:localsend_app/pages/collection_page.dart';
import 'package:localsend_app/provider/collections_provider.dart';
import 'package:localsend_app/widget/collections/collection_widgets.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

String _t({required String fr, required String en}) => LocaleSettings.currentLocale == AppLocale.fr ? fr : en;

/// The search field appears above this many collections.
const _searchThreshold = 6;

/// "Collections" tab: the user's groups of files, kept on this device.
class CollectionsTab extends StatefulWidget {
  const CollectionsTab();

  @override
  State<CollectionsTab> createState() => _CollectionsTabState();
}

class _CollectionsTabState extends State<CollectionsTab> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final state = context.ref.watch(collectionsProvider);
    if (!state.loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.collections.isEmpty) {
      return const _EmptyState();
    }
    final query = _query.trim().toLowerCase();
    final visible = query.isEmpty
        ? state.collections
        : state.collections.where((c) => c.name.toLowerCase().contains(query) || (c.description?.toLowerCase().contains(query) ?? false)).toList();

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _Header(),
                if (state.collections.length > _searchThreshold) ...[
                  const SizedBox(height: 14),
                  TextField(
                    onChanged: (v) => setState(() => _query = v),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search_rounded),
                      hintText: _t(fr: 'Rechercher une collection', en: 'Search collections'),
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(collectionRadius)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (visible.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: Text(_t(fr: 'Aucune collection trouvée.', en: 'No collection found.'))),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 240,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.82,
              ),
              itemCount: visible.length,
              itemBuilder: (context, index) => _CollectionCard(
                collection: visible[index],
                shared: visible[index].id == state.sharedCollectionId,
              ),
            ),
          ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Collections', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(
                _t(fr: 'Organisez et partagez vos fichiers', en: 'Organize and share your files'),
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        FilledButton.icon(
          onPressed: () async => createCollectionFlow(context),
          style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(collectionRadius))),
          icon: const Icon(Icons.add_rounded),
          label: Text(_t(fr: 'Nouvelle', en: 'New')),
        ),
      ],
    );
  }
}

/// Opens the editor, then the new collection.
Future<void> createCollectionFlow(BuildContext context) async {
  final id = await context.pushWithResult<String, CollectionEditorPage>(() => const CollectionEditorPage());
  if (id != null && context.mounted) {
    await context.push(() => CollectionPage(collectionId: id));
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Icon(Icons.photo_library_rounded, size: 46, color: colorScheme.primary),
              ),
              const SizedBox(height: 24),
              Text(
                _t(fr: 'Vos fichiers, organisés à votre façon.', en: 'Your files, organized your way.'),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              Text(
                _t(
                  fr: 'Créez votre première collection pour regrouper vos images, vidéos et documents, puis partagez-les en quelques secondes.',
                  en: 'Create your first collection to group your images, videos and documents, then share them in seconds.',
                ),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () async => createCollectionFlow(context),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(collectionRadius)),
                ),
                icon: const Icon(Icons.add_rounded),
                label: Text(_t(fr: 'Créer ma première collection', en: 'Create my first collection')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _CardAction { rename, share, send, delete }

class _CollectionCard extends StatelessWidget {
  final CollectionSummary collection;
  final bool shared;

  const _CollectionCard({required this.collection, required this.shared});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Material(
      color: colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(collectionRadius + 4),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async => context.push(() => CollectionPage(collectionId: collection.id)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CollectionThumbnail(item: collection.cover),
                  if (shared)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: _Badge(icon: Icons.link_rounded, label: _t(fr: 'Lien actif', en: 'Live link')),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 2, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          collection.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          '${formatItemCount(collection.itemCount)} · ${formatCollectionDate(collection.updatedAt)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<_CardAction>(
                    tooltip: _t(fr: 'Options', en: 'Options'),
                    icon: const Icon(Icons.more_vert_rounded),
                    onSelected: (action) async => _onAction(context, action),
                    itemBuilder: (_) => [
                      _menuItem(_CardAction.rename, Icons.edit_rounded, _t(fr: 'Modifier', en: 'Edit')),
                      if (collection.itemCount > 0) ...[
                        _menuItem(_CardAction.share, Icons.link_rounded, _t(fr: 'Partager par lien', en: 'Share by link')),
                        _menuItem(_CardAction.send, Icons.send_rounded, _t(fr: 'Envoyer vers un appareil', en: 'Send to a device')),
                      ],
                      _menuItem(_CardAction.delete, Icons.delete_outline_rounded, _t(fr: 'Supprimer', en: 'Delete')),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<_CardAction> _menuItem(_CardAction action, IconData icon, String label) {
    return PopupMenuItem(
      value: action,
      child: Row(children: [Icon(icon, size: 20), const SizedBox(width: 12), Text(label)]),
    );
  }

  Future<void> _onAction(BuildContext context, _CardAction action) async {
    final service = context.ref.notifier(collectionsProvider);
    switch (action) {
      case _CardAction.rename:
        await editCollectionInfo(context, collection);
      case _CardAction.share:
        final items = await service.items(collection.id);
        if (context.mounted) {
          await shareCollectionByLink(context, collection.id, items);
        }
      case _CardAction.send:
        final items = await service.items(collection.id);
        if (context.mounted) {
          await sendCollectionItems(context, collection.id, items);
        }
      case _CardAction.delete:
        await deleteCollectionFlow(context, collection);
    }
  }
}

/// Edits the name and description of [collection].
Future<void> editCollectionInfo(BuildContext context, CollectionSummary collection) async {
  final info = await showCollectionInfoDialog(
    context,
    title: _t(fr: 'Modifier la collection', en: 'Edit collection'),
    name: collection.name,
    description: collection.description,
  );
  if (info == null || !context.mounted) {
    return;
  }
  final service = context.ref.notifier(collectionsProvider);
  try {
    await service.rename(collection.id, info.name);
    await service.setDescription(collection.id, info.description);
  } on InvalidCollectionException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

/// Asks for confirmation, then deletes [collection]. Returns whether it
/// was deleted.
Future<bool> deleteCollectionFlow(BuildContext context, CollectionSummary collection) async {
  final service = context.ref.notifier(collectionsProvider);
  final copies = await service.copiesSize(collection.id);
  if (!context.mounted) {
    return false;
  }
  final deleteCopies = await confirmDeleteCollection(context, name: collection.name, copiesBytes: copies);
  if (deleteCopies == null) {
    return false;
  }
  await service.delete(collection.id, deleteCopies: deleteCopies);
  return true;
}

class _Badge extends StatelessWidget {
  final IconData icon;
  final String label;

  const _Badge({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(color: colorScheme.primary, borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: colorScheme.onPrimary),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: colorScheme.onPrimary)),
          ],
        ),
      ),
    );
  }
}
