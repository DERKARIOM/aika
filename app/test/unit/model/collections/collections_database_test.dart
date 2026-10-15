import 'dart:io';

import 'package:drift/native.dart';
import 'package:localsend_app/model/collections/collections_database.dart';
import 'package:test/test.dart';

NewCollectionItem _item(String name, {CollectionItemSource source = CollectionItemSource.path, int size = 10}) {
  return NewCollectionItem(name: name, mimeType: null, size: size, source: source, location: '/files/$name');
}

void main() {
  late CollectionsDatabase db;

  setUp(() {
    db = CollectionsDatabase(NativeDatabase.memory());
  });

  tearDown(() async => db.close());

  group('collections', () {
    test('an empty collection can be created', () async {
      final id = await db.createCollection(name: '  Photos   de  famille ', description: '  ');
      final collection = await db.getCollection(id);
      expect(collection, isNotNull);
      expect(collection!.name, 'Photos de famille');
      expect(collection.description, isNull);
      expect(collection.itemCount, 0);
      expect(collection.cover, isNull);
    });

    test('the database starts empty: no collection is created on its own', () async {
      expect(await db.listCollections(), isEmpty);
    });

    test('invalid names and descriptions are refused', () async {
      final invalid = throwsA(isA<InvalidCollectionException>());
      await expectLater(db.createCollection(name: '   '), invalid);
      await expectLater(db.createCollection(name: 'a' * (maxCollectionNameLength + 1)), invalid);
      await expectLater(db.createCollection(name: 'ok', description: 'd' * (maxCollectionDescriptionLength + 1)), invalid);
      expect(await db.listCollections(), isEmpty);
    });

    test('rename and description', () async {
      final id = await db.createCollection(name: 'Avant', description: 'texte');
      await db.updateCollection(id, name: 'Après');
      expect((await db.getCollection(id))!.name, 'Après');
      expect((await db.getCollection(id))!.description, 'texte');
      await db.updateCollection(id, clearDescription: true);
      expect((await db.getCollection(id))!.description, isNull);
    });

    test('most recently changed first', () async {
      final a = await db.createCollection(name: 'A', now: DateTime(2026));
      final b = await db.createCollection(name: 'B', now: DateTime(2026, 2));
      expect((await db.listCollections()).map((c) => c.id), [b, a]);
      await db.addItems(a, [_item('x.jpg')], now: DateTime(2026, 3));
      expect((await db.listCollections()).map((c) => c.id), [a, b]);
    });

    test('deleting a collection removes its items', () async {
      final id = await db.createCollection(name: 'A');
      await db.addItems(id, [_item('a.jpg'), _item('b.pdf')]);
      await db.deleteCollection(id);
      expect(await db.getCollection(id), isNull);
      expect(await db.listItems(id), isEmpty);
    });
  });

  group('items', () {
    test('are added in order, with their source', () async {
      final id = await db.createCollection(name: 'A');
      await db.addItems(id, [_item('a.jpg'), _item('b.mp4', source: CollectionItemSource.asset)]);
      await db.addItems(id, [_item('c.pdf', source: CollectionItemSource.copy)]);
      final items = await db.listItems(id);
      expect(items.map((i) => i.name), ['a.jpg', 'b.mp4', 'c.pdf']);
      expect(items.map((i) => i.source), [CollectionItemSource.path, CollectionItemSource.asset, CollectionItemSource.copy]);
      expect(items[0].isMedia, isTrue);
      expect(items[2].isMedia, isFalse);
      expect((await db.getCollection(id))!.itemCount, 3);
    });

    test('items of other collections are not mixed', () async {
      final a = await db.createCollection(name: 'A');
      final b = await db.createCollection(name: 'B');
      await db.addItems(a, [_item('a.jpg')]);
      await db.addItems(b, [_item('b.jpg'), _item('c.jpg')]);
      expect((await db.listItems(a)).length, 1);
      expect((await db.listItems(b)).length, 2);
    });

    test('the cover is the chosen item, else the first one', () async {
      final id = await db.createCollection(name: 'A');
      final ids = await db.addItems(id, [_item('a.jpg'), _item('b.jpg')]);
      expect((await db.getCollection(id))!.cover!.id, ids[0]);
      await db.updateCollection(id, coverItemId: ids[1]);
      expect((await db.getCollection(id))!.cover!.id, ids[1]);
      expect((await db.listCollections()).single.cover!.id, ids[1]);
    });

    test('removing the cover falls back to the first item', () async {
      final id = await db.createCollection(name: 'A');
      final ids = await db.addItems(id, [_item('a.jpg'), _item('b.jpg'), _item('c.jpg')]);
      await db.updateCollection(id, coverItemId: ids[2]);
      await db.removeItems(id, [ids[2]]);
      final collection = (await db.getCollection(id))!;
      expect(collection.cover!.id, ids[0]);
      expect(collection.itemCount, 2);
    });

    test('an item can be moved', () async {
      final id = await db.createCollection(name: 'A');
      final ids = await db.addItems(id, [_item('a.jpg'), _item('b.jpg'), _item('c.jpg')]);
      await db.moveItem(id, ids[2], 0);
      expect((await db.listItems(id)).map((i) => i.id), [ids[2], ids[0], ids[1]]);
      await db.moveItem(id, ids[2], 99);
      expect((await db.listItems(id)).map((i) => i.id), [ids[0], ids[1], ids[2]]);
    });
  });

  test('collections survive a restart', () async {
    final dir = await Directory.systemTemp.createTemp('aika_collections_test');
    final file = File('${dir.path}/collections.sqlite');
    try {
      final first = CollectionsDatabase(NativeDatabase(file));
      final id = await first.createCollection(name: 'Voyage', description: 'Été');
      await first.addItems(id, [_item('plage.jpg')]);
      await first.close();

      final second = CollectionsDatabase(NativeDatabase(file));
      final collection = (await second.getCollection(id))!;
      expect(collection.name, 'Voyage');
      expect(collection.description, 'Été');
      expect((await second.listItems(id)).single.name, 'plage.jpg');
      await second.close();
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
