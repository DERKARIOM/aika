import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'chat_database.g.dart';

/// One row per 1:1 conversation. In phase 1 (private conversations only),
/// a conversation is uniquely identified by the peer's TLS certificate
/// fingerprint - the same authenticity anchor already used by the
/// "Favorites" trust list, so a conversation survives IP changes and
/// re-discovery exactly like a favorite device does.
class ChatConversations extends Table {
  /// The peer's certificate fingerprint (SHA-256), see [Device.fingerprint].
  TextColumn get peerFingerprint => text()();

  /// Best-known alias for the peer. Kept in sync with live discovery data
  /// (like `FavoriteDevice.alias`) so the conversation list never shows a
  /// stale name after the peer renames itself.
  TextColumn get peerAlias => text()();

  TextColumn get peerDeviceModel => text().nullable()();

  /// Updated whenever the peer is seen via discovery (multicast/HTTP scan)
  /// or sends anything. Used to render "last seen" when the peer is
  /// currently offline; while online, the UI derives status live from
  /// [nearbyDevicesProvider] instead of this column.
  DateTimeColumn get lastSeenAt => dateTime().nullable()();

  /// Denormalized counter, incremented on every incoming message while the
  /// conversation is not open, reset to 0 when the user opens it.
  IntColumn get unreadCount => integer().withDefault(const Constant(0))();

  /// Denormalized preview of the most recent message (either direction),
  /// so the conversation list can render without joining `chatMessages`.
  TextColumn get lastMessagePreview => text().nullable()();

  DateTimeColumn get lastMessageAt => dateTime().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {peerFingerprint};
}

enum ChatMessageDirectionColumn { incoming, outgoing }

enum ChatMessageStatusColumn {
  /// Written locally, not yet handed off to the network layer.
  pending,

  /// The `prepare-upload` request succeeded; for media messages the
  /// companion file may still be uploading.
  sent,

  /// The peer's own client acknowledged the message with a receipt.
  delivered,

  /// The peer opened the conversation and acknowledged reading it.
  read,

  /// Every retry attempt failed (should be rare given the persistent
  /// outbox; mainly reserved for "blocked by peer" style failures that
  /// must not be retried).
  failed,
}

/// One row per chat message (either direction).
///
/// `id` doubles as [ChatEnvelope.messageId] so that receipts, dedup and
/// outbox bookkeeping can all key off the very same identifier that goes
/// over the wire.
class ChatMessages extends Table {
  TextColumn get id => text()();

  TextColumn get conversationId => text().references(ChatConversations, #peerFingerprint)();

  TextColumn get direction => textEnum<ChatMessageDirectionColumn>()();

  TextColumn get contentType => text()(); // ChatContentType.name

  /// The message's text content (or caption, for media messages).
  /// Named `body` on the Dart side only to avoid shadowing the inherited
  /// `text()` column builder method with a same-named getter; the
  /// generated SQL column is still called `body`.
  TextColumn get body => text().nullable()();

  /// Absolute local path once the attachment bytes are available (either
  /// because we sent it from local storage, or because we finished
  /// receiving it). Null while a media message is still in flight.
  TextColumn get attachmentPath => text().nullable()();

  TextColumn get attachmentFileName => text().nullable()();

  IntColumn get attachmentSize => integer().nullable()();

  TextColumn get status => textEnum<ChatMessageStatusColumn>()();

  TextColumn get errorMessage => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();

  DateTimeColumn get deliveredAt => dateTime().nullable()();

  DateTimeColumn get readAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// The persistent send-outbox: one row per message that still needs to be
/// (re)transmitted. A message leaves the outbox as soon as its
/// `prepare-upload` call succeeds; until then it survives app restarts and
/// is retried with an increasing backoff every time the target device
/// reappears in discovery (see `ChatOutboxService`).
class ChatOutboxEntries extends Table {
  TextColumn get messageId => text().references(ChatMessages, #id)();

  IntColumn get attempts => integer().withDefault(const Constant(0))();

  DateTimeColumn get nextAttemptAt => dateTime()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {messageId};
}

/// Devices the user explicitly blocked from starting/continuing a
/// conversation. Mirrors `FavoriteDevice`'s fingerprint-keyed design.
class ChatBlockedDevices extends Table {
  TextColumn get fingerprint => text()();

  TextColumn get alias => text()();

  DateTimeColumn get blockedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {fingerprint};
}

@DriftDatabase(tables: [ChatConversations, ChatMessages, ChatOutboxEntries, ChatBlockedDevices])
class ChatDatabase extends _$ChatDatabase {
  ChatDatabase(super.e);

  /// Opens (or creates) the on-disk database in the platform's default app
  /// data directory. `drift_flutter`'s `driftDatabase()` picks the right
  /// native backend (NativeDatabase w/ background isolate) per platform.
  ChatDatabase.defaults() : super(driftDatabase(name: 'aika_chat'));

  @override
  int get schemaVersion => 1;

  // ---------------------------------------------------------------------
  // Conversations
  // ---------------------------------------------------------------------

  Stream<List<ChatConversation>> watchConversations() {
    return (select(chatConversations)..orderBy([(t) => OrderingTerm.desc(t.lastMessageAt), (t) => OrderingTerm.desc(t.lastSeenAt)])).watch();
  }

  Future<ChatConversation?> getConversation(String peerFingerprint) {
    return (select(chatConversations)..where((t) => t.peerFingerprint.equals(peerFingerprint))).getSingleOrNull();
  }

  Future<void> upsertConversation({
    required String peerFingerprint,
    required String peerAlias,
    String? peerDeviceModel,
    DateTime? lastSeenAt,
  }) {
    return into(chatConversations).insertOnConflictUpdate(
      ChatConversationsCompanion.insert(
        peerFingerprint: peerFingerprint,
        peerAlias: peerAlias,
        peerDeviceModel: Value(peerDeviceModel),
        lastSeenAt: Value(lastSeenAt),
      ),
    );
  }

  /// Called whenever the peer is freshly seen via discovery, or on any
  /// inbound/outbound traffic, to keep "last seen" accurate while offline.
  Future<void> touchLastSeen(String peerFingerprint, DateTime at) {
    return (update(chatConversations)..where((t) => t.peerFingerprint.equals(peerFingerprint))).write(
      ChatConversationsCompanion(lastSeenAt: Value(at)),
    );
  }

  /// Updates the conversation-list preview. Called once per message (both
  /// directions), separately from [touchLastSeen] so lightweight signals
  /// (typing) never touch the preview.
  Future<void> updateLastMessagePreview(String peerFingerprint, {required String preview, required DateTime at}) {
    return (update(chatConversations)..where((t) => t.peerFingerprint.equals(peerFingerprint))).write(
      ChatConversationsCompanion(lastMessagePreview: Value(preview), lastMessageAt: Value(at)),
    );
  }

  /// Type-safe (no raw SQL, no assumptions about drift's Dart-to-SQL naming
  /// convention) increment. A plain read-then-write is fine here: this is a
  /// local, single-process SQLite database, not a highly concurrent one.
  Future<void> incrementUnread(String peerFingerprint) async {
    final conversation = await getConversation(peerFingerprint);
    if (conversation == null) {
      return;
    }
    await (update(chatConversations)..where((t) => t.peerFingerprint.equals(peerFingerprint))).write(
      ChatConversationsCompanion(unreadCount: Value(conversation.unreadCount + 1)),
    );
  }

  Future<void> resetUnread(String peerFingerprint) {
    return (update(chatConversations)..where((t) => t.peerFingerprint.equals(peerFingerprint))).write(
      const ChatConversationsCompanion(unreadCount: Value(0)),
    );
  }

  Future<void> deleteConversation(String peerFingerprint) async {
    await (delete(chatMessages)..where((t) => t.conversationId.equals(peerFingerprint))).go();
    await (delete(chatConversations)..where((t) => t.peerFingerprint.equals(peerFingerprint))).go();
  }

  // ---------------------------------------------------------------------
  // Messages
  // ---------------------------------------------------------------------

  Stream<List<ChatMessage>> watchMessages(String conversationId, {int limit = 200}) {
    return (select(chatMessages)
          ..where((t) => t.conversationId.equals(conversationId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(limit))
        .watch()
        .map((rows) => rows.reversed.toList());
  }

  /// Full-text-ish search across all conversations (simple LIKE; more than
  /// good enough for a local, per-user message store).
  Future<List<ChatMessage>> searchMessages(String query) {
    final like = '%${query.replaceAll('%', r'\%')}%';
    return (select(chatMessages)
          ..where((t) => t.body.like(like))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(200))
        .get();
  }

  Future<void> insertMessage(ChatMessagesCompanion message) {
    return into(chatMessages).insert(message);
  }

  Future<void> updateMessageStatus(
    String messageId,
    ChatMessageStatusColumn status, {
    String? errorMessage,
    DateTime? deliveredAt,
    DateTime? readAt,
  }) {
    return (update(chatMessages)..where((t) => t.id.equals(messageId))).write(
      ChatMessagesCompanion(
        status: Value(status),
        errorMessage: Value(errorMessage),
        deliveredAt: deliveredAt != null ? Value(deliveredAt) : const Value.absent(),
        readAt: readAt != null ? Value(readAt) : const Value.absent(),
      ),
    );
  }

  Future<void> attachLocalFile(String messageId, {required String path}) {
    return (update(chatMessages)..where((t) => t.id.equals(messageId))).write(
      ChatMessagesCompanion(attachmentPath: Value(path)),
    );
  }

  Future<bool> messageExists(String messageId) async {
    final row = await (select(chatMessages)..where((t) => t.id.equals(messageId))).getSingleOrNull();
    return row != null;
  }

  /// Ids of incoming messages that have not been marked as read yet, used
  /// to send a batch of read receipts when the user opens a conversation.
  Future<List<String>> unreadIncomingMessageIds(String conversationId) async {
    final rows = await (select(chatMessages)..where(
          (t) =>
              t.conversationId.equals(conversationId) &
              t.direction.equalsValue(ChatMessageDirectionColumn.incoming) &
              t.status.equalsValue(ChatMessageStatusColumn.read).not(),
        ))
        .get();
    return rows.map((r) => r.id).toList();
  }

  /// Renders the full conversation as a plain-text transcript, newest
  /// message last, suitable for the "export conversation" feature.
  Future<String> exportConversationAsText(String conversationId) async {
    final conversation = await getConversation(conversationId);
    final rows = await (select(chatMessages)
          ..where((t) => t.conversationId.equals(conversationId))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();

    final buffer = StringBuffer()..writeln('Conversation avec ${conversation?.peerAlias ?? conversationId}')..writeln();
    for (final m in rows) {
      final who = m.direction == ChatMessageDirectionColumn.outgoing ? 'Moi' : (conversation?.peerAlias ?? 'Contact');
      final body = m.body ?? (m.attachmentFileName != null ? '[${m.contentType}] ${m.attachmentFileName}' : '[${m.contentType}]');
      buffer.writeln('[${m.createdAt.toLocal()}] $who: $body');
    }
    return buffer.toString();
  }

  // ---------------------------------------------------------------------
  // Outbox (persistent offline queue)
  // ---------------------------------------------------------------------

  Future<void> enqueueOutbox(String messageId, {DateTime? nextAttemptAt}) {
    return into(chatOutboxEntries).insertOnConflictUpdate(
      ChatOutboxEntriesCompanion.insert(
        messageId: messageId,
        nextAttemptAt: nextAttemptAt ?? DateTime.now().toUtc(),
      ),
    );
  }

  Future<void> rescheduleOutbox(String messageId, DateTime nextAttemptAt, int attempts) {
    return (update(chatOutboxEntries)..where((t) => t.messageId.equals(messageId))).write(
      ChatOutboxEntriesCompanion(
        nextAttemptAt: Value(nextAttemptAt),
        attempts: Value(attempts),
      ),
    );
  }

  Future<void> removeFromOutbox(String messageId) {
    return (delete(chatOutboxEntries)..where((t) => t.messageId.equals(messageId))).go();
  }

  /// All outbox entries whose retry time has come, joined with their
  /// message row so the caller doesn't need a second query per entry.
  /// Returns `(message, attemptsSoFar)` pairs so the caller can compute the
  /// next backoff delay.
  Future<List<(ChatMessage, int)>> dueOutboxMessages(DateTime now) async {
    final query = select(chatOutboxEntries).join([
      innerJoin(chatMessages, chatMessages.id.equalsExp(chatOutboxEntries.messageId)),
    ])..where(chatOutboxEntries.nextAttemptAt.isSmallerOrEqualValue(now));

    final rows = await query.get();
    return rows.map((row) => (row.readTable(chatMessages), row.readTable(chatOutboxEntries).attempts)).toList();
  }

  Stream<int> watchOutboxSize() {
    final count = chatOutboxEntries.messageId.count();
    final query = selectOnly(chatOutboxEntries)..addColumns([count]);
    return query.map((row) => row.read(count) ?? 0).watchSingle();
  }

  // ---------------------------------------------------------------------
  // Blocked devices
  // ---------------------------------------------------------------------

  Stream<List<ChatBlockedDevice>> watchBlockedDevices() => select(chatBlockedDevices).watch();

  Future<void> blockDevice({required String fingerprint, required String alias}) {
    return into(chatBlockedDevices).insertOnConflictUpdate(
      ChatBlockedDevicesCompanion.insert(fingerprint: fingerprint, alias: alias),
    );
  }

  Future<void> unblockDevice(String fingerprint) {
    return (delete(chatBlockedDevices)..where((t) => t.fingerprint.equals(fingerprint))).go();
  }

  Future<bool> isBlocked(String fingerprint) async {
    final row = await (select(chatBlockedDevices)..where((t) => t.fingerprint.equals(fingerprint))).getSingleOrNull();
    return row != null;
  }
}
