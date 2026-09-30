import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:localsend_app/model/chat/chat_database.dart';
import 'package:localsend_app/model/chat/chat_envelope.dart';
import 'package:test/test.dart';

const _alice = 'fingerprint-alice';
const _bob = 'fingerprint-bob';

void main() {
  group('isChatStatusTransitionAllowed', () {
    test('Should allow every forward move', () {
      expect(isChatStatusTransitionAllowed(ChatMessageStatusColumn.pending, ChatMessageStatusColumn.sent), true);
      expect(isChatStatusTransitionAllowed(ChatMessageStatusColumn.pending, ChatMessageStatusColumn.delivered), true);
      expect(isChatStatusTransitionAllowed(ChatMessageStatusColumn.sent, ChatMessageStatusColumn.delivered), true);
      expect(isChatStatusTransitionAllowed(ChatMessageStatusColumn.delivered, ChatMessageStatusColumn.read), true);
      expect(isChatStatusTransitionAllowed(ChatMessageStatusColumn.failed, ChatMessageStatusColumn.sent), true);
    });

    test('Should allow switching between pending and failed', () {
      expect(isChatStatusTransitionAllowed(ChatMessageStatusColumn.pending, ChatMessageStatusColumn.failed), true);
      expect(isChatStatusTransitionAllowed(ChatMessageStatusColumn.failed, ChatMessageStatusColumn.pending), true);
    });

    test('Should allow keeping the same status', () {
      for (final status in ChatMessageStatusColumn.values) {
        expect(isChatStatusTransitionAllowed(status, status), true, reason: status.name);
      }
    });

    test('Should never move backwards', () {
      expect(isChatStatusTransitionAllowed(ChatMessageStatusColumn.delivered, ChatMessageStatusColumn.sent), false);
      expect(isChatStatusTransitionAllowed(ChatMessageStatusColumn.read, ChatMessageStatusColumn.delivered), false);
      expect(isChatStatusTransitionAllowed(ChatMessageStatusColumn.read, ChatMessageStatusColumn.sent), false);
      expect(isChatStatusTransitionAllowed(ChatMessageStatusColumn.sent, ChatMessageStatusColumn.pending), false);
      expect(isChatStatusTransitionAllowed(ChatMessageStatusColumn.delivered, ChatMessageStatusColumn.failed), false);
      expect(isChatStatusTransitionAllowed(ChatMessageStatusColumn.read, ChatMessageStatusColumn.pending), false);
    });
  });

  group('ChatDatabase', () {
    late ChatDatabase db;

    setUpAll(() {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    });

    setUp(() async {
      db = ChatDatabase(NativeDatabase.memory());
      await db.upsertConversation(peerFingerprint: _alice, peerAlias: 'Alice');
      await db.upsertConversation(peerFingerprint: _bob, peerAlias: 'Bob');
    });

    tearDown(() async {
      await db.close();
    });

    Future<void> insert(
      String id, {
      String conversationId = _alice,
      ChatMessageDirectionColumn direction = ChatMessageDirectionColumn.outgoing,
      ChatMessageStatusColumn status = ChatMessageStatusColumn.pending,
      ChatContentType contentType = ChatContentType.text,
      DateTime? createdAt,
    }) {
      return db.insertMessage(
        ChatMessagesCompanion.insert(
          id: id,
          conversationId: conversationId,
          direction: direction,
          contentType: contentType.name,
          status: status,
          createdAt: createdAt ?? DateTime.utc(2026),
          body: const Value('x'),
        ),
      );
    }

    Future<ChatMessageStatusColumn> statusOf(String id) async => (await db.getMessage(id))!.status;

    group('updateMessageStatus', () {
      test('Should keep "delivered" when "sent" is written afterwards', () async {
        // The race: the peer's receipt is processed before our own
        // prepare-upload call returned.
        await insert('m1');

        expect(await db.updateMessageStatus('m1', ChatMessageStatusColumn.delivered), true);
        expect(await db.updateMessageStatus('m1', ChatMessageStatusColumn.sent), false);

        expect(await statusOf('m1'), ChatMessageStatusColumn.delivered);
      });

      test('Should keep "read" when "delivered" arrives late', () async {
        await insert('m1', status: ChatMessageStatusColumn.sent);

        await db.updateMessageStatus('m1', ChatMessageStatusColumn.read);
        await db.updateMessageStatus('m1', ChatMessageStatusColumn.delivered);

        expect(await statusOf('m1'), ChatMessageStatusColumn.read);
      });

      test('Should not reset a delivered message to pending after a failed retry', () async {
        await insert('m1', status: ChatMessageStatusColumn.delivered);

        expect(await db.updateMessageStatus('m1', ChatMessageStatusColumn.pending, errorMessage: 'timeout'), false);

        final row = (await db.getMessage('m1'))!;
        expect(row.status, ChatMessageStatusColumn.delivered);
        expect(row.errorMessage, isNull);
      });

      test('Should refresh the error message of a pending message', () async {
        await insert('m1');

        expect(await db.updateMessageStatus('m1', ChatMessageStatusColumn.pending, errorMessage: 'busy'), true);

        expect((await db.getMessage('m1'))!.errorMessage, 'busy');
      });

      test('Should return false for an unknown message', () async {
        expect(await db.updateMessageStatus('unknown', ChatMessageStatusColumn.sent), false);
      });
    });

    group('applyReceipt', () {
      test('Should apply a batched read receipt', () async {
        await insert('m1', status: ChatMessageStatusColumn.sent);
        await insert('m2', status: ChatMessageStatusColumn.delivered);
        final at = DateTime.utc(2026, 9, 30);

        final updated = await db.applyReceipt(
          conversationId: _alice,
          messageIds: ['m1', 'm2'],
          status: ChatMessageStatusColumn.read,
          at: at,
        );

        expect(updated.toSet(), {'m1', 'm2'});
        final m1 = (await db.getMessage('m1'))!;
        expect(m1.status, ChatMessageStatusColumn.read);
        // drift reads DateTimes back in local time: compare the instant.
        expect(m1.readAt!.isAtSameMomentAs(at), true);
        // Read implies delivered, even if that receipt got lost.
        expect(m1.deliveredAt!.isAtSameMomentAs(at), true);
      });

      test('Should ignore a receipt from another conversation', () async {
        await insert('m1', conversationId: _alice, status: ChatMessageStatusColumn.sent);

        final updated = await db.applyReceipt(
          conversationId: _bob,
          messageIds: ['m1'],
          status: ChatMessageStatusColumn.read,
          at: DateTime.utc(2026),
        );

        expect(updated, isEmpty);
        expect(await statusOf('m1'), ChatMessageStatusColumn.sent);
      });

      test('Should ignore a receipt targeting an incoming message', () async {
        await insert('in1', direction: ChatMessageDirectionColumn.incoming, status: ChatMessageStatusColumn.delivered);

        final updated = await db.applyReceipt(
          conversationId: _alice,
          messageIds: ['in1'],
          status: ChatMessageStatusColumn.read,
          at: DateTime.utc(2026),
        );

        expect(updated, isEmpty);
        expect(await statusOf('in1'), ChatMessageStatusColumn.delivered);
      });

      test('Should be idempotent and never downgrade', () async {
        await insert('m1', status: ChatMessageStatusColumn.sent);
        final at = DateTime.utc(2026);

        await db.applyReceipt(conversationId: _alice, messageIds: ['m1'], status: ChatMessageStatusColumn.read, at: at);
        final again = await db.applyReceipt(conversationId: _alice, messageIds: ['m1'], status: ChatMessageStatusColumn.delivered, at: at);

        expect(again, isEmpty);
        expect(await statusOf('m1'), ChatMessageStatusColumn.read);
      });

      test('Should remove an acknowledged text message from the outbox', () async {
        await insert('m1');
        await insert('media', contentType: ChatContentType.image);
        await db.enqueueOutbox('m1');
        await db.enqueueOutbox('media');

        await db.applyReceipt(
          conversationId: _alice,
          messageIds: ['m1', 'media'],
          status: ChatMessageStatusColumn.delivered,
          at: DateTime.utc(2026),
        );

        final due = await db.dueOutboxMessages(DateTime.utc(2100));
        // The media's attachment may still be missing on the peer side.
        expect(due.map((e) => e.$1.id), ['media']);
      });
    });

    group('markIncomingAsRead', () {
      test('Should mark unread incoming messages only, oldest first', () async {
        await insert(
          'in2',
          direction: ChatMessageDirectionColumn.incoming,
          status: ChatMessageStatusColumn.delivered,
          createdAt: DateTime.utc(2026, 2),
        );
        await insert(
          'in1',
          direction: ChatMessageDirectionColumn.incoming,
          status: ChatMessageStatusColumn.delivered,
          createdAt: DateTime.utc(2026, 1),
        );
        await insert('old', direction: ChatMessageDirectionColumn.incoming, status: ChatMessageStatusColumn.read);
        await insert('out', status: ChatMessageStatusColumn.sent);
        await insert('bob', conversationId: _bob, direction: ChatMessageDirectionColumn.incoming, status: ChatMessageStatusColumn.delivered);

        final ids = await db.markIncomingAsRead(_alice, DateTime.utc(2026, 3));

        expect(ids, ['in1', 'in2']);
        expect(await statusOf('in1'), ChatMessageStatusColumn.read);
        expect(await statusOf('out'), ChatMessageStatusColumn.sent);
        expect(await statusOf('bob'), ChatMessageStatusColumn.delivered);
        expect(await db.markIncomingAsRead(_alice, DateTime.utc(2026, 3)), isEmpty);
      });
    });

    group('duplicates', () {
      test('Should detect an already stored message', () async {
        await insert('m1', direction: ChatMessageDirectionColumn.incoming, status: ChatMessageStatusColumn.delivered);

        expect(await db.messageExists('m1'), true);
        expect(await db.messageExists('m2'), false);
      });

      test('Should refuse to store the same message id twice', () async {
        await insert('m1', direction: ChatMessageDirectionColumn.incoming, status: ChatMessageStatusColumn.delivered);

        await expectLater(
          insert('m1', direction: ChatMessageDirectionColumn.incoming, status: ChatMessageStatusColumn.delivered),
          throwsA(isA<SqliteException>()),
        );
      });
    });
  });
}
