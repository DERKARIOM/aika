import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:localsend_app/util/file_path_helper.dart';
import 'package:localsend_isolates/model/file_type.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Longest collection name accepted.
const maxCollectionNameLength = 80;

/// Longest description accepted.
const maxCollectionDescriptionLength = 500;

/// Where the file of a collection item lives.
enum CollectionItemSource {
  /// Original file on a computer, referenced by its absolute path: nothing
  /// is copied.
  path,

  /// Photo or video of the phone's gallery, referenced by its stable
  /// gallery id (photo_manager): nothing is copied.
  asset,

  /// Aika's own copy in the app's private storage, for files the system
  /// only lends temporarily (documents picked on Android / iOS). Owned by
  /// Aika: deleted with the item.
  copy,
}

/// One file of a collection. Only metadata is stored; the file itself
/// stays where [location] points.
class CollectionItem {
  final String id;
  final String collectionId;
  final String name;
  final String? mimeType;
  final int size;
  final CollectionItemSource source;

  /// Absolute path ([CollectionItemSource.path], [CollectionItemSource.copy])
  /// or gallery id ([CollectionItemSource.asset]). Never shown to others.
  final String location;
  final DateTime addedAt;
  final int position;

  const CollectionItem({
    required this.id,
    required this.collectionId,
    required this.name,
    required this.mimeType,
    required this.size,
    required this.source,
    required this.location,
    required this.addedAt,
    required this.position,
  });

  FileType get fileType => name.guessFileType();

  bool get isMedia => fileType == FileType.image || fileType == FileType.video;

  static CollectionItem _fromRow(QueryRow row) {
    return CollectionItem(
      id: row.read<String>('id'),
      collectionId: row.read<String>('collection_id'),
      name: row.read<String>('name'),
      mimeType: row.readNullable<String>('mime_type'),
      size: row.read<int>('size'),
      source: CollectionItemSource.values.firstWhere((s) => s.name == row.read<String>('source'), orElse: () => CollectionItemSource.path),
      location: row.read<String>('location'),
      addedAt: DateTime.fromMillisecondsSinceEpoch(row.read<int>('added_at')),
      position: row.read<int>('position'),
    );
  }
}

/// What is needed to add a file to a collection.
class NewCollectionItem {
  final String? id;
  final String name;
  final String? mimeType;
  final int size;
  final CollectionItemSource source;
  final String location;

  const NewCollectionItem({
    this.id,
    required this.name,
    required this.mimeType,
    required this.size,
    required this.source,
    required this.location,
  });
}

/// A collection as shown in the list: details, number of items and cover.
class CollectionSummary {
  final String id;
  final String name;
  final String? description;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int itemCount;

  /// The chosen cover, or the first item; `null` for an empty collection.
  final CollectionItem? cover;

  const CollectionSummary({
    required this.id,
    required this.name,
    required this.description,
    required this.createdAt,
    required this.updatedAt,
    required this.itemCount,
    required this.cover,
  });
}

/// Thrown for an invalid name or description.
class InvalidCollectionException implements Exception {
  final String message;

  const InvalidCollectionException(this.message);

  @override
  String toString() => 'InvalidCollectionException($message)';
}

/// Local database of the "Collections" (separate from the chat database).
///
/// The tables are created with plain SQL when the database opens, like the
/// chat's side tables: no generated code, nothing to run before building.
/// A collection is a logical group: deleting it never touches the user's
/// original files (see `collections_provider.dart` for Aika's copies).
class CollectionsDatabase extends GeneratedDatabase {
  CollectionsDatabase(super.executor);

  /// On-disk database in the app's data folder, opened on first use.
  CollectionsDatabase.defaults() : super(driftDatabase(name: 'aika_collections'));

  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    beforeOpen: (_) async {
      for (final statement in _schema) {
        await customStatement(statement);
      }
    },
  );

  static const _schema = [
    '''
    CREATE TABLE IF NOT EXISTS collections (
      id TEXT NOT NULL PRIMARY KEY,
      name TEXT NOT NULL,
      description TEXT,
      cover_item_id TEXT,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    ) WITHOUT ROWID''',
    '''
    CREATE TABLE IF NOT EXISTS collection_items (
      id TEXT NOT NULL PRIMARY KEY,
      collection_id TEXT NOT NULL,
      name TEXT NOT NULL,
      mime_type TEXT,
      size INTEGER NOT NULL,
      source TEXT NOT NULL,
      location TEXT NOT NULL,
      added_at INTEGER NOT NULL,
      position INTEGER NOT NULL
    ) WITHOUT ROWID''',
    'CREATE INDEX IF NOT EXISTS collection_items_by_collection ON collection_items (collection_id, position)',
  ];

  /// All collections, most recently changed first.
  Future<List<CollectionSummary>> listCollections() async {
    final rows = await customSelect('''
      SELECT c.*,
        (SELECT COUNT(*) FROM collection_items i WHERE i.collection_id = c.id) AS item_count
      FROM collections c
      ORDER BY c.updated_at DESC''').get();
    final covers = await _covers();
    return [for (final row in rows) _summary(row, covers[row.read<String>('id')])];
  }

  Future<CollectionSummary?> getCollection(String id) async {
    final row = await customSelect(
      '''
      SELECT c.*,
        (SELECT COUNT(*) FROM collection_items i WHERE i.collection_id = c.id) AS item_count
      FROM collections c WHERE c.id = ?''',
      variables: [Variable.withString(id)],
    ).getSingleOrNull();
    if (row == null) {
      return null;
    }
    final covers = await _covers(collectionId: id);
    return _summary(row, covers[id]);
  }

  /// Cover of each collection: the chosen item, else the first one.
  Future<Map<String, CollectionItem>> _covers({String? collectionId}) async {
    final rows = await customSelect(
      '''
      SELECT i.* FROM collection_items i
      JOIN collections c ON c.id = i.collection_id
      WHERE (? IS NULL OR c.id = ?)
        AND i.id = COALESCE(
          (SELECT x.id FROM collection_items x WHERE x.id = c.cover_item_id AND x.collection_id = c.id),
          (SELECT y.id FROM collection_items y WHERE y.collection_id = c.id ORDER BY y.position, y.added_at LIMIT 1)
        )''',
      variables: [Variable<String>(collectionId), Variable<String>(collectionId)],
    ).get();
    return {for (final row in rows) row.read<String>('collection_id'): CollectionItem._fromRow(row)};
  }

  CollectionSummary _summary(QueryRow row, CollectionItem? cover) {
    return CollectionSummary(
      id: row.read<String>('id'),
      name: row.read<String>('name'),
      description: row.readNullable<String>('description'),
      createdAt: DateTime.fromMillisecondsSinceEpoch(row.read<int>('created_at')),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row.read<int>('updated_at')),
      itemCount: row.read<int>('item_count'),
      cover: cover,
    );
  }

  /// Creates a collection and returns its id.
  Future<String> createCollection({required String name, String? description, String? id, DateTime? now}) async {
    final cleanName = validateCollectionName(name);
    final cleanDescription = validateCollectionDescription(description);
    final collectionId = id ?? _uuid.v4();
    final time = (now ?? DateTime.now()).millisecondsSinceEpoch;
    await customStatement(
      'INSERT INTO collections (id, name, description, cover_item_id, created_at, updated_at) VALUES (?, ?, ?, NULL, ?, ?)',
      [collectionId, cleanName, cleanDescription, time, time],
    );
    return collectionId;
  }

  /// Renames, describes or sets the cover of a collection. Only the given
  /// values change; [clearDescription] removes the description.
  Future<void> updateCollection(String id, {String? name, String? description, bool clearDescription = false, String? coverItemId}) async {
    await transaction(() async {
      if (name != null) {
        await customStatement('UPDATE collections SET name = ? WHERE id = ?', [validateCollectionName(name), id]);
      }
      if (description != null || clearDescription) {
        await customStatement('UPDATE collections SET description = ? WHERE id = ?', [
          clearDescription ? null : validateCollectionDescription(description),
          id,
        ]);
      }
      if (coverItemId != null) {
        await customStatement('UPDATE collections SET cover_item_id = ? WHERE id = ?', [coverItemId, id]);
      }
      await _touch(id);
    });
  }

  /// Deletes a collection and its item list (never the files).
  Future<void> deleteCollection(String id) async {
    await transaction(() async {
      await customStatement('DELETE FROM collection_items WHERE collection_id = ?', [id]);
      await customStatement('DELETE FROM collections WHERE id = ?', [id]);
    });
  }

  /// Items of a collection, in their order.
  Future<List<CollectionItem>> listItems(String collectionId) async {
    final rows = await customSelect(
      'SELECT * FROM collection_items WHERE collection_id = ? ORDER BY position, added_at',
      variables: [Variable.withString(collectionId)],
    ).get();
    return rows.map(CollectionItem._fromRow).toList();
  }

  /// Appends [items] at the end of the collection; returns their ids.
  Future<List<String>> addItems(String collectionId, List<NewCollectionItem> items, {DateTime? now}) async {
    if (items.isEmpty) {
      return const [];
    }
    final time = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final ids = <String>[];
    await transaction(() async {
      final last = await customSelect(
        'SELECT COALESCE(MAX(position), -1) AS last FROM collection_items WHERE collection_id = ?',
        variables: [Variable.withString(collectionId)],
      ).getSingle();
      var position = last.read<int>('last');
      for (final item in items) {
        final id = item.id ?? _uuid.v4();
        ids.add(id);
        position++;
        await customStatement(
          'INSERT INTO collection_items (id, collection_id, name, mime_type, size, source, location, added_at, position) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [id, collectionId, item.name, item.mimeType, item.size, item.source.name, item.location, time, position],
        );
      }
      await _touch(collectionId, time: time);
    });
    return ids;
  }

  /// Removes items from a collection (the files are not touched here).
  Future<void> removeItems(String collectionId, Iterable<String> itemIds) async {
    final ids = itemIds.toList();
    if (ids.isEmpty) {
      return;
    }
    await transaction(() async {
      for (final id in ids) {
        await customStatement('DELETE FROM collection_items WHERE collection_id = ? AND id = ?', [collectionId, id]);
      }
      await customStatement(
        'UPDATE collections SET cover_item_id = NULL WHERE id = ? AND cover_item_id NOT IN (SELECT id FROM collection_items WHERE collection_id = ?)',
        [collectionId, collectionId],
      );
      await _touch(collectionId);
    });
  }

  /// Moves an item to [newIndex] (0-based) and renumbers the collection.
  Future<void> moveItem(String collectionId, String itemId, int newIndex) async {
    await transaction(() async {
      final items = await listItems(collectionId);
      final from = items.indexWhere((i) => i.id == itemId);
      if (from < 0) {
        return;
      }
      final moved = items.removeAt(from);
      items.insert(newIndex.clamp(0, items.length), moved);
      for (var i = 0; i < items.length; i++) {
        await customStatement('UPDATE collection_items SET position = ? WHERE id = ?', [i, items[i].id]);
      }
      await _touch(collectionId);
    });
  }

  Future<void> _touch(String collectionId, {int? time}) async {
    await customStatement('UPDATE collections SET updated_at = ? WHERE id = ?', [time ?? DateTime.now().millisecondsSinceEpoch, collectionId]);
  }
}

/// Trimmed, non-empty name of at most [maxCollectionNameLength] characters.
String validateCollectionName(String name) {
  final clean = name.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (clean.isEmpty) {
    throw const InvalidCollectionException('empty name');
  }
  if (clean.length > maxCollectionNameLength) {
    throw const InvalidCollectionException('name too long');
  }
  return clean;
}

/// Trimmed description, `null` when empty.
String? validateCollectionDescription(String? description) {
  final clean = description?.trim();
  if (clean == null || clean.isEmpty) {
    return null;
  }
  if (clean.length > maxCollectionDescriptionLength) {
    throw const InvalidCollectionException('description too long');
  }
  return clean;
}
