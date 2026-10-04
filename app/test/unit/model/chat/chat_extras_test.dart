import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:localsend_app/model/chat/chat_database.dart';
import 'package:test/test.dart';

void main() {
  late ChatDatabase db;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  Future<void> add(String id, String conversation, {ChatMessageDirectionColumn direction = ChatMessageDirectionColumn.incoming}) {
    return db.insertMessage(
      ChatMessagesCompanion.insert(
        id: id,
        conversationId: conversation,
        direction: direction,
        contentType: 'text',
        status: ChatMessageStatusColumn.delivered,
        createdAt: DateTime.utc(2026),
        body: Value('text of $id'),
      ),
    );
  }

  setUp(() async {
    db = ChatDatabase(NativeDatabase.memory());
    await db.upsertConversation(peerFingerprint: 'P', peerAlias: 'Bob');
    await db.upsertConversation(peerFingerprint: 'Q', peerAlias: 'Eve');
    await add('a', 'P');
    await add('b', 'P', direction: ChatMessageDirectionColumn.outgoing);
    await add('x', 'Q');
  });

  tearDown(() async {
    await db.close();
  });

  test('Should quote the replied message of the same conversation only', () async {
    await db.setReplyTo('b', 'a');
    await add('c', 'P');
    await db.setReplyTo('c', 'x');

    final extras = await db.watchExtras('P').first;

    expect(extras.quotes['b']!.body, 'text of a');
    expect(extras.quotes['b']!.direction, ChatMessageDirectionColumn.incoming);
    // A message of another conversation is never shown in this one.
    expect(extras.quotes['c']!.isAvailable, false);
    expect(extras.quotes['c']!.body, isNull);
  });

  test('Should keep one reaction per side, and remove it', () async {
    await db.setReaction('a', fromPeer: false, emoji: '👍');
    await db.setReaction('a', fromPeer: false, emoji: '❤️');
    await db.setReaction('a', fromPeer: true, emoji: '😂');
    expect((await db.watchExtras('P').first).reactions['a'], (mine: '❤️', peer: '😂'));

    await db.setReaction('a', fromPeer: false, emoji: null);
    expect((await db.watchExtras('P').first).reactions['a'], (mine: null, peer: '😂'));
  });

  test('Should update watchers on a new reaction', () async {
    final updates = db.watchExtras('P').map((e) => e.reactions['a']?.peer);
    final expectation = expectLater(updates, emitsInOrder([isNull, '🙏']));
    await Future<void>.delayed(Duration.zero);
    await db.setReaction('a', fromPeer: true, emoji: '🙏');
    await expectation;
  });

  test('Should drop the replies and reactions of deleted messages', () async {
    await db.setReplyTo('b', 'a');
    await db.setReaction('b', fromPeer: true, emoji: '👍');

    await db.deleteMessage((await db.getMessage('b'))!);

    final extras = await db.watchExtras('P').first;
    expect(extras.quotes, isEmpty);
    expect(extras.reactions, isEmpty);
    expect(await db.replyToOf('b'), isNull);
  });
}
