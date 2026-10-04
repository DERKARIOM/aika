import 'dart:async';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:localsend_app/model/chat/chat_database.dart';
import 'package:localsend_app/provider/chat/blocked_devices_provider.dart';
import 'package:localsend_app/provider/chat/chat_contact_policy.dart';
import 'package:localsend_app/provider/chat/chat_database_provider.dart';
import 'package:localsend_app/provider/persistence_provider.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:test/test.dart';

import '../../../mocks.mocks.dart';

final _stranger = Device.empty.copyWith(ip: '192.168.1.30', port: 53317, https: true, fingerprint: 'DDDD', alias: 'Eve');

/// [chatSenderVerdict] decides, without any dialog, how a chat sender is
/// treated; the receive path answers the network from it right away.
void main() {
  late ChatDatabase db;
  late RefenaContainer container;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  setUp(() {
    db = ChatDatabase(NativeDatabase.memory());
    container = RefenaContainer(
      overrides: [
        chatDatabaseProvider.overrideWithValue(db),
        persistenceProvider.overrideWithValue(MockPersistenceService()),
      ],
    );
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> settle() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('Should classify a first-time sender as unknown', () async {
    expect(await chatSenderVerdict(container, _stranger), ChatSenderVerdict.unknown);
  });

  test('Should classify a sender with a conversation as known', () async {
    await db.upsertConversation(peerFingerprint: _stranger.fingerprint, peerAlias: 'Eve');

    expect(await chatSenderVerdict(container, _stranger), ChatSenderVerdict.known);
  });

  test('Should classify a blocked sender as blocked, even with a conversation', () async {
    unawaited(container.redux(blockedDevicesProvider).dispatchAsync(StartWatchingBlockedDevicesAction()));
    await db.upsertConversation(peerFingerprint: _stranger.fingerprint, peerAlias: 'Eve');
    await db.blockDevice(fingerprint: _stranger.fingerprint, alias: 'Eve');
    await settle();

    expect(await chatSenderVerdict(container, _stranger), ChatSenderVerdict.blocked);
  });
}
