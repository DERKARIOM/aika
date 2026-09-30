import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:localsend_app/model/chat/chat_database.dart';
import 'package:localsend_app/model/chat/chat_database_encryption.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

const _key = '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';
const _otherKey = 'ffeeddccbbaa99887766554433221100ffeeddccbbaa99887766554433221100';

class _MemoryKeyStore implements ChatDatabaseKeyStore {
  String? value;
  int writes = 0;

  _MemoryKeyStore([this.value]);

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String key) async {
    writes++;
    value = key;
  }
}

/// A secure storage that is never available (e.g. Linux without keyring).
class _BrokenSecureStorage implements FlutterSecureStorage {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<Never>.error(Exception('no keyring'));
}

bool _hasPlaintextHeader(String path) {
  final bytes = File(path).openSync().readSync(16);
  return String.fromCharCodes(bytes) == 'SQLite format 3\u0000';
}

void main() {
  late Directory tmp;
  late String dbPath;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('aika_chat_test');
    dbPath = p.join(tmp.path, 'aika_chat.sqlite');
  });

  tearDown(() {
    tmp.deleteSync(recursive: true);
  });

  group('loadOrCreateChatDatabaseKey', () {
    test('Should generate and store a 64-char hex key once', () async {
      final store = _MemoryKeyStore();

      final first = await loadOrCreateChatDatabaseKey(store, random: Random(1));
      final second = await loadOrCreateChatDatabaseKey(store);

      expect(first, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(second, first);
      expect(store.writes, 1);
    });

    test('Should replace a malformed stored key', () async {
      final store = _MemoryKeyStore('not-a-key');

      final key = await loadOrCreateChatDatabaseKey(store);

      expect(key, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(store.value, key);
    });
  });

  group('SecureChatDatabaseKeyStore', () {
    test('Should fall back to a private file when secure storage is unavailable', () async {
      final store = SecureChatDatabaseKeyStore(fallbackDirectory: () async => tmp, storage: _BrokenSecureStorage());

      expect(await store.read(), isNull);
      await store.write(_key);

      expect(await store.read(), _key);
      final file = File(p.join(tmp.path, 'aika_chat.key'));
      expect(file.readAsStringSync(), _key);
      if (!Platform.isWindows) {
        expect(file.statSync().modeString(), 'rw-------');
      }
    });
  });

  group('encrypted database file', () {
    test('Should use an SQLite build with encryption support', () {
      final db = sqlite3.openInMemory();
      addTearDown(db.close);
      expect(db.select('PRAGMA cipher;'), isNotEmpty);
    });

    test('Should write an encrypted file that reopens with the same key only', () {
      final db = sqlite3.open(dbPath);
      applyChatDatabaseKey(db, _key);
      db
        ..execute('CREATE TABLE t (v TEXT);')
        ..execute("INSERT INTO t VALUES ('secret message');")
        ..close();

      expect(_hasPlaintextHeader(dbPath), false);
      expect(File(dbPath).readAsStringSync(encoding: latin1).contains('secret message'), false);
      expect(prepareChatDatabaseFile(dbPath, _key), ChatDatabaseFileState.ready);

      final reopened = sqlite3.open(dbPath);
      addTearDown(reopened.close);
      expect(() => applyChatDatabaseKey(reopened, _otherKey), throwsA(isA<SqliteException>()));
    });

    test('Should report a missing file', () {
      expect(prepareChatDatabaseFile(dbPath, _key), ChatDatabaseFileState.missing);
    });

    test('Should encrypt a v1.0.3 plaintext database in place, keeping its content', () {
      final plain = sqlite3.open(dbPath);
      plain
        ..execute('PRAGMA journal_mode = WAL;')
        ..execute('CREATE TABLE t (v TEXT);')
        ..execute("INSERT INTO t VALUES ('hello');")
        ..close();
      expect(_hasPlaintextHeader(dbPath), true);

      expect(prepareChatDatabaseFile(dbPath, _key), ChatDatabaseFileState.encryptedLegacy);

      expect(_hasPlaintextHeader(dbPath), false);
      final db = sqlite3.open(dbPath);
      addTearDown(db.close);
      applyChatDatabaseKey(db, _key);
      expect(db.select('SELECT v FROM t').single['v'], 'hello');
    });

    test('Should move aside a database encrypted with a lost key', () {
      final db = sqlite3.open(dbPath);
      applyChatDatabaseKey(db, _otherKey);
      db
        ..execute('CREATE TABLE t (v TEXT);')
        ..close();

      expect(prepareChatDatabaseFile(dbPath, _key), ChatDatabaseFileState.quarantined);

      expect(File(dbPath).existsSync(), false);
      final moved = tmp.listSync().map((e) => p.basename(e.path)).where((n) => n.startsWith('aika_chat.sqlite.unreadable-'));
      expect(moved, isNotEmpty);
    });

    test('Should reject a key that is not 64 hex characters', () {
      final db = sqlite3.openInMemory();
      addTearDown(db.close);
      expect(() => applyChatDatabaseKey(db, "x'; DROP TABLE t; --"), throwsArgumentError);
    });

    test('Should run ChatDatabase on top of an encrypted file', () async {
      final db = ChatDatabase(NativeDatabase(File(dbPath), setup: (raw) => applyChatDatabaseKey(raw, _key)));
      await db.upsertConversation(peerFingerprint: 'fp', peerAlias: 'Alice');
      await db.close();

      expect(_hasPlaintextHeader(dbPath), false);

      final reopened = ChatDatabase(NativeDatabase(File(dbPath), setup: (raw) => applyChatDatabaseKey(raw, _key)));
      addTearDown(reopened.close);
      expect((await reopened.getConversation('fp'))?.peerAlias, 'Alice');
    });
  });
}
