import 'dart:async';
import 'dart:io';

import 'package:localsend_app/model/collections/collections_database.dart';
import 'package:localsend_app/model/cross_file.dart';
import 'package:localsend_app/util/link_download/file_naming.dart';
import 'package:localsend_app/util/native/cross_file_converters.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_app/util/native/storage_info.dart';
import 'package:localsend_isolates/model/file_type.dart';
import 'package:logging/logging.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart' as path_provider;
import 'package:refena_flutter/refena_flutter.dart';
import 'package:uri_content/uri_content.dart';
import 'package:uuid/uuid.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

final _logger = Logger('Collections');
const _uuid = Uuid();

/// The collections database, opened on first use.
final collectionsDatabaseProvider = Provider<CollectionsDatabase>((ref) => CollectionsDatabase.defaults());

class CollectionsState {
  /// `false` until the list was read once.
  final bool loaded;
  final List<CollectionSummary> collections;

  /// Collection currently shared by link (one share at a time in Aika).
  final String? sharedCollectionId;

  const CollectionsState({required this.loaded, required this.collections, this.sharedCollectionId});

  CollectionsState copyWith({bool? loaded, List<CollectionSummary>? collections, String? sharedCollectionId, bool clearShared = false}) {
    return CollectionsState(
      loaded: loaded ?? this.loaded,
      collections: collections ?? this.collections,
      sharedCollectionId: clearShared ? null : sharedCollectionId ?? this.sharedCollectionId,
    );
  }
}

/// Why adding files failed.
enum CollectionsProblem { notEnoughSpace, unreadable }

class CollectionsException implements Exception {
  final CollectionsProblem problem;

  const CollectionsException(this.problem);
}

/// Files ready for the transfer / share-link flows, and the items whose
/// file is gone (deleted, moved, permission removed).
class ResolvedCollectionFiles {
  final List<CrossFile> files;
  final List<CollectionItem> missing;

  const ResolvedCollectionFiles(this.files, this.missing);
}

/// How a picked file is kept in a collection:
/// - a photo / video of the phone's gallery → its stable gallery id;
/// - a file on a computer → its path (no copy);
/// - anything the system only lends temporarily (documents picked on a
///   phone, pasted images) → an Aika copy.
CollectionItemSource sourceForPickedFile(CrossFile file, {required bool isDesktop}) {
  if (!isDesktop && file.asset != null) {
    return CollectionItemSource.asset;
  }
  final path = file.path;
  if (isDesktop && path != null && !path.startsWith('content://')) {
    return CollectionItemSource.path;
  }
  return CollectionItemSource.copy;
}

/// Collections: local groups of files, kept across restarts. Reuses the
/// existing pickers, transfer and share-link flows (see the pages).
final collectionsProvider = NotifierProvider<CollectionsService, CollectionsState>((ref) {
  return CollectionsService(ref.read(collectionsDatabaseProvider));
});

class CollectionsService extends Notifier<CollectionsState> {
  final CollectionsDatabase _db;

  /// Overridable in tests (folder of Aika's copies).
  final Future<Directory> Function() _copiesRoot;
  final bool _isDesktop;

  CollectionsService(this._db, {Future<Directory> Function()? copiesRoot, bool? isDesktop})
    : _copiesRoot = copiesRoot ?? _defaultCopiesRoot,
      _isDesktop = isDesktop ?? checkPlatformIsDesktop();

  static Future<Directory> _defaultCopiesRoot() async {
    final base = await path_provider.getApplicationSupportDirectory();
    return Directory(p.join(base.path, 'collections'));
  }

  @override
  CollectionsState init() {
    unawaited(refresh());
    return const CollectionsState(loaded: false, collections: []);
  }

  Future<void> refresh() async {
    try {
      final collections = await _db.listCollections();
      state = state.copyWith(loaded: true, collections: collections);
    } catch (e) {
      _logger.warning('Could not read the collections', e);
      state = state.copyWith(loaded: true);
    }
  }

  Future<String> create({required String name, String? description}) async {
    final id = await _db.createCollection(name: name, description: description);
    await refresh();
    return id;
  }

  Future<void> rename(String id, String name) async {
    await _db.updateCollection(id, name: name);
    await refresh();
  }

  Future<void> setDescription(String id, String? description) async {
    final clean = validateCollectionDescription(description);
    await _db.updateCollection(id, description: clean, clearDescription: clean == null);
    await refresh();
  }

  Future<void> setCover(String id, String itemId) async {
    await _db.updateCollection(id, coverItemId: itemId);
    await refresh();
  }

  Future<CollectionSummary?> get(String id) => _db.getCollection(id);

  Future<List<CollectionItem>> items(String collectionId) => _db.listItems(collectionId);

  Future<void> moveItem(String collectionId, String itemId, int newIndex) async {
    await _db.moveItem(collectionId, itemId, newIndex);
  }

  /// Adds picked files. Gallery media and computer files are referenced;
  /// other files are copied into Aika's storage after checking the free
  /// space. Returns the number of files added.
  Future<int> addFiles(String collectionId, List<CrossFile> files) async {
    final candidates = files.where((f) => f.fileType != FileType.text || f.path != null).toList();
    final toCopy = candidates.where((f) => sourceForPickedFile(f, isDesktop: _isDesktop) == CollectionItemSource.copy);
    final copyBytes = toCopy.fold<int>(0, (sum, f) => sum + f.size);
    if (copyBytes > 0) {
      final storage = await readStorageInfo();
      if (storage != null && storage.freeBytes < copyBytes + 50 * 1024 * 1024) {
        throw const CollectionsException(CollectionsProblem.notEnoughSpace);
      }
    }

    final newItems = <NewCollectionItem>[];
    for (final file in candidates) {
      final source = sourceForPickedFile(file, isDesktop: _isDesktop);
      final id = _uuid.v4();
      final location = await _locationFor(collectionId, id, file, source);
      if (location == null) {
        continue; // Unreadable: skip this file, keep the others.
      }
      newItems.add(
        NewCollectionItem(
          id: id,
          name: file.name,
          mimeType: lookupMimeType(file.name),
          size: file.size,
          source: source,
          location: location,
        ),
      );
    }
    if (newItems.isEmpty && candidates.isNotEmpty) {
      throw const CollectionsException(CollectionsProblem.unreadable);
    }
    await _db.addItems(collectionId, newItems);
    await refresh();
    return newItems.length;
  }

  Future<String?> _locationFor(String collectionId, String itemId, CrossFile file, CollectionItemSource source) async {
    switch (source) {
      case CollectionItemSource.asset:
        return file.asset!.id;
      case CollectionItemSource.path:
        return file.path!;
      case CollectionItemSource.copy:
        try {
          return await _storeCopy(collectionId, itemId, file);
        } catch (e) {
          _logger.warning('Could not copy ${file.name}', e);
          return null;
        }
    }
  }

  /// Removes items from the collection. Original files are never touched;
  /// Aika's own copies of these items are deleted.
  Future<void> removeItems(String collectionId, List<CollectionItem> items) async {
    await _db.removeItems(collectionId, items.map((i) => i.id));
    for (final item in items.where((i) => i.source == CollectionItemSource.copy)) {
      await _deleteQuietly(File(item.location));
    }
    await refresh();
  }

  /// Space used by Aika's copies in this collection.
  Future<int> copiesSize(String collectionId) async {
    final items = await _db.listItems(collectionId);
    return items.where((i) => i.source == CollectionItemSource.copy).fold<int>(0, (sum, i) => sum + i.size);
  }

  /// Deletes the collection (never the original files). Aika's copies are
  /// deleted only when [deleteCopies] is true; otherwise they are kept in
  /// Aika's storage folder.
  Future<void> delete(String collectionId, {required bool deleteCopies}) async {
    await _db.deleteCollection(collectionId);
    if (deleteCopies) {
      try {
        final dir = Directory(p.join((await _copiesRoot()).path, collectionId));
        if (dir.existsSync()) {
          await dir.delete(recursive: true);
        }
      } catch (e) {
        _logger.warning('Could not delete the copies of $collectionId', e);
      }
    }
    if (state.sharedCollectionId == collectionId) {
      state = state.copyWith(clearShared: true);
    }
    await refresh();
  }

  void markShared(String? collectionId) {
    state = collectionId == null ? state.copyWith(clearShared: true) : state.copyWith(sharedCollectionId: collectionId);
  }

  /// Whether the file of [item] can still be read.
  Future<bool> isAvailable(CollectionItem item) async {
    switch (item.source) {
      case CollectionItemSource.path:
      case CollectionItemSource.copy:
        return File(item.location).existsSync();
      case CollectionItemSource.asset:
        try {
          return await AssetEntity.fromId(item.location) != null;
        } catch (_) {
          return false;
        }
    }
  }

  /// Turns items into files for the transfer or share-link flows, checking
  /// each one is still there.
  Future<ResolvedCollectionFiles> resolveFiles(List<CollectionItem> items) async {
    final files = <CrossFile>[];
    final missing = <CollectionItem>[];
    for (final item in items) {
      try {
        final file = await _toCrossFile(item);
        if (file == null) {
          missing.add(item);
        } else {
          files.add(file);
        }
      } catch (e) {
        _logger.info('Item ${item.id} unavailable: $e');
        missing.add(item);
      }
    }
    return ResolvedCollectionFiles(files, missing);
  }

  Future<CrossFile?> _toCrossFile(CollectionItem item) async {
    switch (item.source) {
      case CollectionItemSource.path:
      case CollectionItemSource.copy:
        final file = File(item.location);
        if (!file.existsSync()) {
          return null;
        }
        return CrossFile(
          name: item.name,
          fileType: item.fileType,
          size: file.lengthSync(),
          thumbnail: null,
          asset: null,
          path: file.path,
          bytes: null,
          lastModified: file.lastModifiedSync().toUtc(),
          lastAccessed: null,
        );
      case CollectionItemSource.asset:
        final asset = await AssetEntity.fromId(item.location);
        if (asset == null) {
          return null;
        }
        final file = await CrossFileConverters.convertAssetEntity(asset);
        return CrossFile(
          name: item.name,
          fileType: file.fileType,
          size: file.size,
          thumbnail: null,
          asset: asset,
          path: file.path,
          bytes: null,
          lastModified: file.lastModified,
          lastAccessed: file.lastAccessed,
        );
    }
  }

  /// Streams the file into `<app storage>/collections/<collection>/`
  /// (never fully loaded in memory). Returns the copy's path.
  Future<String> _storeCopy(String collectionId, String itemId, CrossFile file) async {
    final dir = Directory(p.join((await _copiesRoot()).path, collectionId));
    await dir.create(recursive: true);
    final target = File(p.join(dir.path, '$itemId-${sanitizeFileName(file.name)}'));
    final source = file.path;
    try {
      if (source != null && source.startsWith('content://')) {
        final sink = target.openWrite();
        try {
          await sink.addStream(UriContent().getContentStream(Uri.parse(source)));
        } finally {
          await sink.close();
        }
      } else if (source != null) {
        await File(source).copy(target.path);
      } else if (file.bytes != null) {
        await target.writeAsBytes(file.bytes!, flush: true);
      } else {
        throw const CollectionsException(CollectionsProblem.unreadable);
      }
    } catch (_) {
      await _deleteQuietly(target);
      rethrow;
    }
    return target.path;
  }
}

Future<void> _deleteQuietly(File file) async {
  try {
    if (file.existsSync()) {
      await file.delete();
    }
  } catch (_) {}
}
