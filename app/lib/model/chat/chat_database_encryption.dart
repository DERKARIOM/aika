import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/common.dart';
import 'package:sqlite3/sqlite3.dart';

final _logger = Logger('ChatDatabaseEncryption');

/// Secure-storage entry holding the chat database passphrase.
const _secureStorageKey = 'aika_chat_db_key_v1';

/// First 16 bytes of every *unencrypted* SQLite file. An encrypted file
/// starts with random-looking bytes instead, which is how a v1.0.3
/// plaintext database is told apart from an already encrypted one.
final _plaintextSqliteHeader = ascii.encode('SQLite format 3\u0000');

/// Where the chat database passphrase lives.
abstract class ChatDatabaseKeyStore {
  Future<String?> read();

  Future<void> write(String key);
}

/// The platform's secure storage: Android Keystore, iOS/macOS Keychain,
/// libsecret on Linux, DPAPI on Windows.
///
/// If that storage is unusable (typically a Linux session without a
/// running keyring), the key falls back to a file readable only by the
/// current user next to the database, so the chat keeps working instead of
/// failing to start. Once such a file exists it is always preferred, so a
/// keyring that becomes available later never produces a second key.
class SecureChatDatabaseKeyStore implements ChatDatabaseKeyStore {
  final FlutterSecureStorage _storage;
  final Future<Directory> Function() _fallbackDirectory;

  SecureChatDatabaseKeyStore({
    required Future<Directory> Function() fallbackDirectory,
    FlutterSecureStorage? storage,
  }) : _fallbackDirectory = fallbackDirectory,
       _storage =
           storage ??
           const FlutterSecureStorage(
             // Readable once the device was unlocked after a reboot, so a
             // message received in the background can still be stored.
             iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
             mOptions: MacOsOptions(accessibility: KeychainAccessibility.first_unlock),
           );

  Future<File> _fallbackFile() async => File(p.join((await _fallbackDirectory()).path, 'aika_chat.key'));

  @override
  Future<String?> read() async {
    final fallback = await _fallbackFile();
    if (await fallback.exists()) {
      return (await fallback.readAsString()).trim();
    }
    try {
      return await _storage.read(key: _secureStorageKey);
    } catch (e) {
      _logger.warning('Secure storage unavailable while reading the chat key: $e');
      return null;
    }
  }

  @override
  Future<void> write(String key) async {
    try {
      await _storage.write(key: _secureStorageKey, value: key);
      if (await _storage.read(key: _secureStorageKey) == key) {
        return;
      }
      _logger.warning('Secure storage did not persist the chat key.');
    } catch (e) {
      _logger.warning('Secure storage unavailable while writing the chat key: $e');
    }

    final fallback = await _fallbackFile();
    await fallback.parent.create(recursive: true);
    await fallback.writeAsString(key, flush: true);
    if (!Platform.isWindows) {
      await Process.run('chmod', ['600', fallback.path]);
    }
    _logger.warning('Chat database key stored in ${fallback.path} (secure storage unavailable).');
  }
}

/// Returns the chat database passphrase, generating and storing a new one
/// on first use: 32 random bytes, hex-encoded (so it never needs quoting
/// inside a PRAGMA).
Future<String> loadOrCreateChatDatabaseKey(ChatDatabaseKeyStore store, {Random? random}) async {
  final existing = await store.read();
  if (existing != null && _hexKey.hasMatch(existing)) {
    return existing;
  }
  if (existing != null) {
    _logger.warning('Stored chat database key is malformed, generating a new one.');
  }
  final rng = random ?? Random.secure();
  final bytes = Uint8List.fromList(List.generate(32, (_) => rng.nextInt(256)));
  final key = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  await store.write(key);
  return key;
}

/// Unlocks [db] with [key]. Used as drift's `setup` callback, so it runs
/// before any other statement on every connection.
///
/// Throws if the linked SQLite has no encryption support: writing the chat
/// history in clear text because of a build misconfiguration must never
/// happen silently.
void applyChatDatabaseKey(CommonDatabase db, String key) {
  _checkHexKey(key);
  if (db.select('PRAGMA cipher;').isEmpty) {
    throw StateError('The bundled SQLite has no encryption support (expected SQLite3MultipleCiphers).');
  }
  db.execute("PRAGMA key = '$key';");
  // Fails with SQLITE_NOTADB right away if the key is wrong.
  db.select('SELECT count(*) FROM sqlite_master;');
}

/// What [prepareChatDatabaseFile] did to the file.
enum ChatDatabaseFileState {
  /// No file yet: drift will create an encrypted one.
  missing,

  /// Already encrypted with the current key.
  ready,

  /// A v1.0.3 plaintext database, now encrypted in place.
  encryptedLegacy,

  /// Encrypted with another key (lost or reset secure storage): moved
  /// aside, a new empty database will be created.
  quarantined,
}

/// Makes the file at [path] openable with [key] before drift touches it.
/// Synchronous and potentially slow (it rewrites a legacy database), so
/// call it through [prepareChatDatabaseFileInBackground].
ChatDatabaseFileState prepareChatDatabaseFile(String path, String key) {
  _checkHexKey(key);
  final file = File(path);
  if (!file.existsSync() || file.lengthSync() == 0) {
    return ChatDatabaseFileState.missing;
  }

  if (_isPlaintextSqlite(file)) {
    final db = sqlite3.open(path);
    try {
      if (db.select('PRAGMA cipher;').isEmpty) {
        throw StateError('The bundled SQLite has no encryption support (expected SQLite3MultipleCiphers).');
      }
      // Rekeying is not supported in WAL mode.
      db.execute('PRAGMA journal_mode = DELETE;');
      db.execute("PRAGMA rekey = '$key';");
    } finally {
      db.close();
    }
    return ChatDatabaseFileState.encryptedLegacy;
  }

  final db = sqlite3.open(path);
  try {
    applyChatDatabaseKey(db, key);
    return ChatDatabaseFileState.ready;
  } on SqliteException catch (e) {
    if (e.resultCode != 26 /* SQLITE_NOTADB */ ) {
      rethrow;
    }
  } finally {
    db.close();
  }

  final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(RegExp('[^0-9]'), '');
  for (final suffix in const ['', '-wal', '-shm', '-journal']) {
    final f = File('$path$suffix');
    if (f.existsSync()) {
      f.renameSync('$path.unreadable-$stamp$suffix');
    }
  }
  return ChatDatabaseFileState.quarantined;
}

Future<ChatDatabaseFileState> prepareChatDatabaseFileInBackground(String path, String key) async {
  final state = await Isolate.run(() => prepareChatDatabaseFile(path, key));
  switch (state) {
    case ChatDatabaseFileState.encryptedLegacy:
      _logger.info('Existing plaintext chat database encrypted.');
    case ChatDatabaseFileState.quarantined:
      _logger.warning('Chat database could not be decrypted with the stored key; moved aside and starting fresh.');
    case ChatDatabaseFileState.missing:
    case ChatDatabaseFileState.ready:
      break;
  }
  return state;
}

bool _isPlaintextSqlite(File file) {
  final raf = file.openSync();
  try {
    final header = raf.readSync(_plaintextSqliteHeader.length);
    if (header.length != _plaintextSqliteHeader.length) {
      return false;
    }
    for (var i = 0; i < header.length; i++) {
      if (header[i] != _plaintextSqliteHeader[i]) {
        return false;
      }
    }
    return true;
  } finally {
    raf.closeSync();
  }
}

final _hexKey = RegExp(r'^[0-9a-f]{64}$');

void _checkHexKey(String key) {
  if (!_hexKey.hasMatch(key)) {
    throw ArgumentError('The chat database key must be 64 lowercase hex characters.');
  }
}
