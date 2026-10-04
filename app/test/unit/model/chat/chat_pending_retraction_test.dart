import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:localsend_app/model/chat/chat_database.dart';
import 'package:test/test.dart';

void main() {
  late ChatDatabase db;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  setUp(() {
    db = ChatDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('Should keep pending retractions per peer, in order, without duplicates', () async {
    await db.addPendingRetraction('P', 'a');
    await db.addPendingRetraction('P', 'b');
    await db.addPendingRetraction('P', 'a');
    await db.addPendingRetraction('Q', 'c');

    expect(await db.pendingRetractions('P', limit: 10), ['a', 'b']);
    expect(await db.pendingRetractions('P', limit: 1), ['a']);
    expect(await db.pendingRetractions('Q', limit: 10), ['c']);
  });

  test('Should forget delivered retractions only', () async {
    await db.addPendingRetraction('P', 'a');
    await db.addPendingRetraction('P', 'b');

    await db.removePendingRetractions('P', ['a']);

    expect(await db.pendingRetractions('P', limit: 10), ['b']);
  });

  test('Should forget the retractions of a deleted conversation', () async {
    await db.upsertConversation(peerFingerprint: 'P', peerAlias: 'Bob');
    await db.addPendingRetraction('P', 'a');

    await db.deleteConversation('P');

    expect(await db.pendingRetractions('P', limit: 10), isEmpty);
  });
}
