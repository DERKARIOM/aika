import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:localsend_app/model/chat/chat_database.dart';
import 'package:test/test.dart';

import '../../../generated_migrations/chat/schema.dart';
import '../../../generated_migrations/chat/schema_v1.dart' as v1;

void main() {
  late SchemaVerifier verifier;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    verifier = SchemaVerifier(GeneratedHelper());
  });

  test('Should upgrade the schema from v1 to v2', () async {
    final connection = await verifier.startAt(1);
    final db = ChatDatabase(connection);
    addTearDown(db.close);

    await verifier.migrateAndValidate(db, 2);
  });

  test('Should keep v1.0.3 data when upgrading to v2', () async {
    final schema = await verifier.schemaAt(1);
    final createdAt = DateTime.utc(2026, 9, 1);
    // drift's default DateTime storage: unix seconds.
    final createdAtSeconds = createdAt.millisecondsSinceEpoch ~/ 1000;

    final old = v1.DatabaseAtV1(schema.newConnection());
    await old
        .into(old.chatConversations)
        .insert(v1.ChatConversationsCompanion.insert(peerFingerprint: 'fp', peerAlias: 'Alice', unreadCount: const Value(2)));
    await old
        .into(old.chatMessages)
        .insert(
          v1.ChatMessagesCompanion.insert(
            id: 'm1',
            conversationId: 'fp',
            direction: 'outgoing',
            contentType: 'text',
            body: const Value('bonjour'),
            status: 'delivered',
            createdAt: createdAtSeconds,
          ),
        );
    await old.into(old.chatOutboxEntries).insert(v1.ChatOutboxEntriesCompanion.insert(messageId: 'm1', nextAttemptAt: createdAtSeconds));
    await old.close();

    final db = ChatDatabase(schema.newConnection());
    addTearDown(db.close);

    final conversation = (await db.getConversation('fp'))!;
    expect(conversation.peerAlias, 'Alice');
    expect(conversation.unreadCount, 2);
    expect(conversation.peerChatProtocol, isNull);

    final message = (await db.getMessage('m1'))!;
    expect(message.body, 'bonjour');
    expect(message.status, ChatMessageStatusColumn.delivered);
    expect(message.createdAt.isAtSameMomentAs(createdAt), true);
    expect(message.sentAt, isNull);

    expect((await db.dueOutboxMessages(DateTime.utc(2100))).map((e) => e.$1.id), ['m1']);
  });

  group('schema v2 behavior', () {
    late ChatDatabase db;

    setUp(() async {
      db = ChatDatabase((await verifier.schemaAt(2)).newConnection());
      await db.upsertConversation(peerFingerprint: 'fp', peerAlias: 'Alice');
    });

    tearDown(() => db.close());

    Future<void> insertOutgoing(String id) {
      return db.insertMessage(
        ChatMessagesCompanion.insert(
          id: id,
          conversationId: 'fp',
          direction: ChatMessageDirectionColumn.outgoing,
          contentType: 'text',
          status: ChatMessageStatusColumn.pending,
          createdAt: DateTime.utc(2026),
        ),
      );
    }

    test('Should stamp sentAt once, when the message is sent', () async {
      await insertOutgoing('m1');
      expect((await db.getMessage('m1'))!.sentAt, isNull);

      await db.updateMessageStatus('m1', ChatMessageStatusColumn.sent);
      final sentAt = (await db.getMessage('m1'))!.sentAt;
      expect(sentAt, isNotNull);

      await db.updateMessageStatus('m1', ChatMessageStatusColumn.sent);
      expect((await db.getMessage('m1'))!.sentAt, sentAt);
    });

    test('Should store the peer chat protocol version', () async {
      await db.setPeerChatProtocol('fp', 2);
      expect((await db.getConversation('fp'))!.peerChatProtocol, 2);

      await db.setPeerChatProtocol('fp', null);
      expect((await db.getConversation('fp'))!.peerChatProtocol, isNull);
    });

    test('Should drop queued messages when the conversation is deleted', () async {
      await insertOutgoing('m1');
      await db.enqueueOutbox('m1');

      await db.deleteConversation('fp');

      expect(await db.getConversation('fp'), isNull);
      expect(await db.getMessage('m1'), isNull);
      expect(await db.watchOutboxSize().first, 0);
    });
  });
}
