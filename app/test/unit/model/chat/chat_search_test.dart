import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:localsend_app/model/chat/chat_database.dart';
import 'package:test/test.dart';

void main() {
  late ChatDatabase db;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  setUp(() async {
    db = ChatDatabase(NativeDatabase.memory());
    await db.upsertConversation(peerFingerprint: 'P', peerAlias: 'Bob');
    var minute = 0;
    Future<void> add(String id, {String? body, String? fileName}) {
      return db.insertMessage(
        ChatMessagesCompanion.insert(
          id: id,
          conversationId: 'P',
          direction: ChatMessageDirectionColumn.incoming,
          contentType: fileName == null ? 'text' : 'document',
          status: ChatMessageStatusColumn.delivered,
          createdAt: DateTime.utc(2026, 10, 4, 12, minute++),
          body: Value(body),
          attachmentFileName: Value(fileName),
        ),
      );
    }

    await add('a', body: 'Bonjour, tu es sûr à 100% ?');
    await add('b', fileName: 'Rapport_Final.pdf');
    await add('c', body: 'Le rapport arrive');
    await add('d', body: 'rien à voir');
  });

  tearDown(() async {
    await db.close();
  });

  Future<List<String>> search(String query) async => (await db.searchMessages(query)).map((m) => m.id).toList();

  test('Should find text and file names, case-insensitively, newest first', () async {
    expect(await search('RAPPORT'), ['c', 'b']);
  });

  test('Should match % and _ literally', () async {
    expect(await search('100%'), ['a']);
    expect(await search('_'), ['b']);
  });

  test('Should return nothing for a blank query', () async {
    expect(await search('   '), isEmpty);
  });

  test('Should count the messages from a given time on', () async {
    final b = (await db.getMessage('b'))!;
    expect(await db.countMessagesSince('P', b.createdAt), 3);
  });
}
