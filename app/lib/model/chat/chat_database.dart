import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:localsend_app/model/chat/chat_database_encryption.dart';
import 'package:localsend_app/model/chat/chat_envelope.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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

  /// Highest chat protocol version the peer announced in its WebSocket
  /// `hello` (schema v2). Null means unknown: only the legacy
  /// `.aika-chat.v1.json` envelope is safe to use with that peer.
  IntColumn get peerChatProtocol => integer().nullable()();

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

/// Progress rank of a message status: a message only ever moves forward
/// (`pending`/`failed` < `sent` < `delivered` < `read`). `pending` and
/// `failed` share a rank so a retry may flip between them.
int _statusRank(ChatMessageStatusColumn status) {
  return switch (status) {
    ChatMessageStatusColumn.pending || ChatMessageStatusColumn.failed => 0,
    ChatMessageStatusColumn.sent => 1,
    ChatMessageStatusColumn.delivered => 2,
    ChatMessageStatusColumn.read => 3,
  };
}

/// Whether a message currently in [from] may be moved to [to].
///
/// Receipts and send results arrive over independent requests, so they can
/// be processed out of order (e.g. the peer's "delivered" receipt before
/// our own "sent" write). Refusing any backward move makes the final state
/// independent of that order. Same-status writes stay allowed so an error
/// message can still be refreshed.
bool isChatStatusTransitionAllowed(ChatMessageStatusColumn from, ChatMessageStatusColumn to) {
  return _statusRank(to) >= _statusRank(from);
}

/// One row per chat message (either direction).
///
/// `id` doubles as [ChatEnvelope.messageId] so that receipts, dedup and
/// outbox bookkeeping can all key off the very same identifier that goes
/// over the wire.
@TableIndex(name: 'chat_messages_conversation_created', columns: {#conversationId, #createdAt})
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

  /// When an outgoing message actually left this device (schema v2); null
  /// while it is still pending, and for incoming messages.
  DateTimeColumn get sentAt => dateTime().nullable()();

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
@TableIndex(name: 'chat_outbox_next_attempt', columns: {#nextAttemptAt})
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

const _databaseName = 'aika_chat';

/// Loads (or creates) the key, encrypts a v1.0.3 plaintext file in place if
/// needed, then opens the database with the key applied on every
/// connection. Same file as before encryption (`<documents>/aika_chat.sqlite`).
Future<DatabaseConnection> _openEncrypted() async {
  final key = await loadOrCreateChatDatabaseKey(SecureChatDatabaseKeyStore(fallbackDirectory: getApplicationSupportDirectory));
  final path = p.join((await getApplicationDocumentsDirectory()).path, '$_databaseName.sqlite');
  await prepareChatDatabaseFileInBackground(path, key);
  return driftDatabase(name: _databaseName, native: _nativeOptions(path, key));
}

/// Top-level so the `setup` closure only captures [key] and stays sendable
/// to drift's background isolate.
DriftNativeOptions _nativeOptions(String path, String key) {
  return DriftNativeOptions(
    databasePath: () async => path,
    setup: (db) => applyChatDatabaseKey(db, key),
  );
}

@DriftDatabase(tables: [ChatConversations, ChatMessages, ChatOutboxEntries, ChatBlockedDevices])
class ChatDatabase extends _$ChatDatabase {
  ChatDatabase(super.e);

  /// Opens (or creates) the encrypted on-disk database in the platform's
  /// default app data directory. `drift_flutter`'s `driftDatabase()` picks
  /// the right native backend (NativeDatabase w/ background isolate) per
  /// platform; the key is loaded lazily, on the first query, see
  /// [_openEncrypted].
  ChatDatabase.defaults() : super(DatabaseConnection.delayed(_openEncrypted()));

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onUpgrade: (m, from, to) async {
        if (from < 2) {
          await m.addColumn(chatConversations, chatConversations.peerChatProtocol);
          await m.addColumn(chatMessages, chatMessages.sentAt);
          await m.create(chatMessagesConversationCreated);
          await m.create(chatOutboxNextAttempt);
        }
      },
    );
  }

  /// Side tables (pending retractions, replies, reactions), created on
  /// first use rather than by a migration: no generated code and no schema
  /// version bump for these small tables, and the drift schema (checked by
  /// `chat_database_migration_test`) stays unchanged.
  Future<void>? _sideTables;

  Future<void> _ensureSideTables() => _sideTables ??= () async {
    await customStatement(_createPendingRetractions);
    await customStatement(_createReplies);
    await customStatement(_createReactions);
  }();

  static const _createPendingRetractions = """
    CREATE TABLE IF NOT EXISTS chat_pending_retractions (
      peer_fingerprint TEXT NOT NULL,
      message_id TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      PRIMARY KEY (peer_fingerprint, message_id)
    ) WITHOUT ROWID""";

  /// Which message a message replies to.
  static const _createReplies = """
    CREATE TABLE IF NOT EXISTS chat_message_replies (
      message_id TEXT NOT NULL PRIMARY KEY,
      reply_to_id TEXT NOT NULL
    ) WITHOUT ROWID""";

  /// At most one reaction per side (ours, the peer's) and message.
  static const _createReactions = """
    CREATE TABLE IF NOT EXISTS chat_reactions (
      message_id TEXT NOT NULL,
      from_peer INTEGER NOT NULL,
      emoji TEXT NOT NULL,
      PRIMARY KEY (message_id, from_peer)
    ) WITHOUT ROWID""";

  /// How long an undelivered retraction is kept: a peer gone for longer
  /// keeps the bubble of the interrupted attachment, marked not received.
  static const _pendingRetractionTtl = Duration(days: 30);

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
  /// `null` [preview] and [at]: the conversation has no message any more.
  Future<void> updateLastMessagePreview(String peerFingerprint, {required String? preview, required DateTime? at}) {
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
    // Outside the transaction: a rollback must not undo the creation.
    await _ensureSideTables();
    return transaction(() async {
      // Queued messages of this conversation must not be sent any more.
      final messageIds = selectOnly(chatMessages)
        ..addColumns([chatMessages.id])
        ..where(chatMessages.conversationId.equals(peerFingerprint));
      await (delete(chatOutboxEntries)..where((t) => t.messageId.isInQuery(messageIds))).go();
      for (final table in const ['chat_message_replies', 'chat_reactions']) {
        await customUpdate(
          'DELETE FROM $table WHERE message_id IN (SELECT id FROM chat_messages WHERE conversation_id = ?)',
          variables: [Variable.withString(peerFingerprint)],
          updateKind: UpdateKind.delete,
        );
      }
      await (delete(chatMessages)..where((t) => t.conversationId.equals(peerFingerprint))).go();
      await (delete(chatConversations)..where((t) => t.peerFingerprint.equals(peerFingerprint))).go();
      await customUpdate(
        'DELETE FROM chat_pending_retractions WHERE peer_fingerprint = ?',
        variables: [Variable.withString(peerFingerprint)],
        updateKind: UpdateKind.delete,
      );
    });
  }

  /// Records the chat protocol version the peer announced (schema v2).
  Future<void> setPeerChatProtocol(String peerFingerprint, int? version) {
    return (update(chatConversations)..where((t) => t.peerFingerprint.equals(peerFingerprint))).write(
      ChatConversationsCompanion(peerChatProtocol: Value(version)),
    );
  }

  // ---------------------------------------------------------------------
  // Messages
  // ---------------------------------------------------------------------

  Stream<List<ChatMessage>> watchMessages(String conversationId, {int limit = 200}) {
    return (select(chatMessages)
          ..where((t) => t.conversationId.equals(conversationId))
          // The id breaks ties (same millisecond), so the order is stable.
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt), (t) => OrderingTerm.desc(t.id)])
          ..limit(limit))
        .watch()
        .map((rows) => rows.reversed.toList());
  }

  /// Messages whose text or attachment name contains [query], newest
  /// first, across all conversations.
  ///
  /// A plain substring match (`instr`), case-insensitive for ASCII: unlike
  /// `LIKE`, characters such as `%` and `_` in the query match themselves.
  /// Plenty for a local, per-user message store.
  Future<List<ChatMessage>> searchMessages(String query, {int limit = 200}) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) {
      return Future.value(const []);
    }
    Expression<bool> contains(Expression<String> column) =>
        FunctionCallExpression<int>('instr', [column.lower(), Variable.withString(needle)]).isBiggerThanValue(0);
    return (select(chatMessages)
          ..where((t) => contains(t.body) | contains(t.attachmentFileName))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt), (t) => OrderingTerm.desc(t.id)])
          ..limit(limit))
        .get();
  }

  /// How many messages of [conversationId] were written at or after
  /// [since]: the position of a message counted from the latest one.
  Future<int> countMessagesSince(String conversationId, DateTime since) async {
    final count = chatMessages.id.count();
    final row = await (selectOnly(chatMessages)
          ..addColumns([count])
          ..where(chatMessages.conversationId.equals(conversationId) & chatMessages.createdAt.isBiggerOrEqualValue(since)))
        .getSingle();
    return row.read(count) ?? 0;
  }

  Future<void> insertMessage(ChatMessagesCompanion message) {
    return into(chatMessages).insert(message);
  }

  Future<ChatMessage?> getMessage(String messageId) {
    return (select(chatMessages)..where((t) => t.id.equals(messageId))).getSingleOrNull();
  }

  /// Deletes a message and its outbox entry; an unread incoming message no
  /// longer counts as unread. Returns the conversation's latest remaining
  /// message (for its preview in the list), or `null` if none is left.
  Future<ChatMessage?> deleteMessage(ChatMessage message) async {
    // Outside the transaction: a rollback must not undo the creation.
    await _ensureSideTables();
    return transaction(() async {
      await removeFromOutbox(message.id);
      for (final table in const ['chat_message_replies', 'chat_reactions']) {
        await customUpdate(
          'DELETE FROM $table WHERE message_id = ?',
          variables: [Variable.withString(message.id)],
          updateKind: UpdateKind.delete,
        );
      }
      await (delete(chatMessages)..where((t) => t.id.equals(message.id))).go();
      if (message.direction == ChatMessageDirectionColumn.incoming && message.readAt == null) {
        final conversation = await getConversation(message.conversationId);
        if (conversation != null && conversation.unreadCount > 0) {
          await (update(chatConversations)..where((t) => t.peerFingerprint.equals(message.conversationId))).write(
            ChatConversationsCompanion(unreadCount: Value(conversation.unreadCount - 1)),
          );
        }
      }
      return (select(chatMessages)
            ..where((t) => t.conversationId.equals(message.conversationId))
            ..orderBy([(t) => OrderingTerm.desc(t.createdAt), (t) => OrderingTerm.desc(t.id)])
            ..limit(1))
          .getSingleOrNull();
    });
  }

  /// Moves a message to [status] unless that would be a step backwards
  /// (see [isChatStatusTransitionAllowed]). Returns whether it was written.
  Future<bool> updateMessageStatus(
    String messageId,
    ChatMessageStatusColumn status, {
    String? errorMessage,
    DateTime? deliveredAt,
    DateTime? readAt,
  }) {
    return transaction(() async {
      final current = await getMessage(messageId);
      if (current == null || !isChatStatusTransitionAllowed(current.status, status)) {
        return false;
      }
      await (update(chatMessages)..where((t) => t.id.equals(messageId))).write(
        ChatMessagesCompanion(
          status: Value(status),
          errorMessage: Value(errorMessage),
          sentAt: status == ChatMessageStatusColumn.sent && current.sentAt == null ? Value(DateTime.now().toUtc()) : const Value.absent(),
          deliveredAt: deliveredAt != null ? Value(deliveredAt) : const Value.absent(),
          readAt: readAt != null ? Value(readAt) : const Value.absent(),
        ),
      );
      return true;
    });
  }

  /// Applies a delivered/read receipt sent by the peer [conversationId].
  ///
  /// Only our own outgoing messages of that very conversation are touched:
  /// a peer can never flip the status of a message it did not receive
  /// (another conversation's, or one of its own incoming ones). Text
  /// messages acknowledged this way also leave the outbox, since the peer
  /// provably has them. Returns the ids actually updated.
  Future<List<String>> applyReceipt({
    required String conversationId,
    required List<String> messageIds,
    required ChatMessageStatusColumn status,
    required DateTime at,
  }) {
    assert(status == ChatMessageStatusColumn.delivered || status == ChatMessageStatusColumn.read);
    if (messageIds.isEmpty) {
      return Future.value(const []);
    }
    return transaction(() async {
      final rows =
          await (select(chatMessages)..where(
                (t) => t.id.isIn(messageIds) & t.conversationId.equals(conversationId) & t.direction.equalsValue(ChatMessageDirectionColumn.outgoing),
              ))
              .get();

      final updated = <String>[];
      for (final row in rows) {
        if (row.contentType == ChatContentType.text.name) {
          await removeFromOutbox(row.id);
        }
        if (!isChatStatusTransitionAllowed(row.status, status)) {
          continue;
        }
        await (update(chatMessages)..where((t) => t.id.equals(row.id))).write(
          ChatMessagesCompanion(
            status: Value(status),
            errorMessage: const Value(null),
            // A read receipt implies delivery: keep deliveredAt meaningful
            // even when the "delivered" receipt itself got lost.
            deliveredAt: status == ChatMessageStatusColumn.delivered || row.deliveredAt == null ? Value(at) : const Value.absent(),
            readAt: status == ChatMessageStatusColumn.read ? Value(at) : const Value.absent(),
          ),
        );
        updated.add(row.id);
      }
      return updated;
    });
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

  /// Marks every not-yet-read incoming message of [conversationId] as read
  /// in a single transaction. Returns their ids, oldest first, so the
  /// caller can acknowledge them all with one batched receipt.
  Future<List<String>> markIncomingAsRead(String conversationId, DateTime at) {
    return transaction(() async {
      final rows =
          await (select(chatMessages)
                ..where(
                  (t) =>
                      t.conversationId.equals(conversationId) &
                      t.direction.equalsValue(ChatMessageDirectionColumn.incoming) &
                      t.status.equalsValue(ChatMessageStatusColumn.read).not(),
                )
                ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
              .get();
      if (rows.isEmpty) {
        return const <String>[];
      }
      final ids = rows.map((r) => r.id).toList();
      await (update(chatMessages)..where((t) => t.id.isIn(ids))).write(
        ChatMessagesCompanion(status: const Value(ChatMessageStatusColumn.read), readAt: Value(at)),
      );
      return ids;
    });
  }

  /// Ids of the incoming messages of [conversationId] read at or after
  /// [since], oldest first, at most [limit]: the read receipts to send
  /// again after a link was down (receipts are idempotent on the peer).
  Future<List<String>> incomingReadSince(String conversationId, DateTime since, {int limit = 500}) async {
    final rows =
        await (select(chatMessages)
              ..where(
                (t) =>
                    t.conversationId.equals(conversationId) &
                    t.direction.equalsValue(ChatMessageDirectionColumn.incoming) &
                    t.status.equalsValue(ChatMessageStatusColumn.read) &
                    t.readAt.isBiggerOrEqualValue(since),
              )
              ..orderBy([(t) => OrderingTerm.desc(t.readAt)])
              ..limit(limit))
            .get();
    return rows.reversed.map((r) => r.id).toList();
  }

  /// Renders the full conversation as a plain-text transcript, newest
  /// message last, suitable for the "export conversation" feature.
  Future<String> exportConversationAsText(String conversationId) async {
    final conversation = await getConversation(conversationId);
    final rows =
        await (select(chatMessages)
              ..where((t) => t.conversationId.equals(conversationId))
              ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
            .get();

    final buffer = StringBuffer()
      ..writeln('Conversation avec ${conversation?.peerAlias ?? conversationId}')
      ..writeln();
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

  /// Makes the queued messages of [conversationId] that were not sent yet
  /// due now, e.g. because the peer just came online. Messages already
  /// sent and waiting for their ack keep their own timer.
  ///
  /// [attachmentsOnly]: only messages carrying a file (they wait for the
  /// peer to be discovered, texts wait for its chat link).
  Future<void> makeOutboxDueNow(String conversationId, DateTime now, {bool attachmentsOnly = false}) {
    var condition =
        chatMessages.conversationId.equals(conversationId) &
        chatMessages.status.isInValues([ChatMessageStatusColumn.pending, ChatMessageStatusColumn.failed]);
    if (attachmentsOnly) {
      condition = condition & chatMessages.contentType.equals(ChatContentType.text.name).not();
    }
    final messageIds = selectOnly(chatMessages)
      ..addColumns([chatMessages.id])
      ..where(condition);
    return (update(chatOutboxEntries)..where((t) => t.messageId.isInQuery(messageIds))).write(
      ChatOutboxEntriesCompanion(nextAttemptAt: Value(now)),
    );
  }

  // ---------------------------------------------------------------------
  // Replies and reactions (side tables)
  // ---------------------------------------------------------------------

  Future<void> setReplyTo(String messageId, String replyToId) async {
    await _ensureSideTables();
    await customInsert(
      'INSERT OR REPLACE INTO chat_message_replies (message_id, reply_to_id) VALUES (?, ?)',
      variables: [Variable.withString(messageId), Variable.withString(replyToId)],
    );
    _notifyMessagesChanged();
  }

  Future<String?> replyToOf(String messageId) async {
    await _ensureSideTables();
    final row = await customSelect(
      'SELECT reply_to_id FROM chat_message_replies WHERE message_id = ?',
      variables: [Variable.withString(messageId)],
    ).getSingleOrNull();
    return row?.read<String>('reply_to_id');
  }

  /// Sets (or with a `null` [emoji], removes) our reaction or the peer's.
  Future<void> setReaction(String messageId, {required bool fromPeer, required String? emoji}) async {
    await _ensureSideTables();
    if (emoji == null) {
      await customUpdate(
        'DELETE FROM chat_reactions WHERE message_id = ? AND from_peer = ?',
        variables: [Variable.withString(messageId), Variable.withBool(fromPeer)],
        updateKind: UpdateKind.delete,
      );
    } else {
      await customInsert(
        'INSERT OR REPLACE INTO chat_reactions (message_id, from_peer, emoji) VALUES (?, ?, ?)',
        variables: [Variable.withString(messageId), Variable.withBool(fromPeer), Variable.withString(emoji)],
      );
    }
    _notifyMessagesChanged();
  }

  /// Replies and reactions of [conversationId], kept up to date. Only
  /// messages having one are listed, so this stays small.
  Stream<ChatMessageExtras> watchExtras(String conversationId) async* {
    await _ensureSideTables();
    yield* customSelect(
      '''
      SELECT m.id AS id,
             r.reply_to_id AS reply_to_id,
             q.direction AS quoted_direction,
             q.content_type AS quoted_content_type,
             q.body AS quoted_body,
             q.attachment_file_name AS quoted_file_name,
             (SELECT emoji FROM chat_reactions WHERE message_id = m.id AND from_peer = 0) AS my_reaction,
             (SELECT emoji FROM chat_reactions WHERE message_id = m.id AND from_peer = 1) AS peer_reaction
      FROM chat_messages m
      LEFT JOIN chat_message_replies r ON r.message_id = m.id
      LEFT JOIN chat_messages q ON q.id = r.reply_to_id AND q.conversation_id = m.conversation_id
      WHERE m.conversation_id = ?
        AND (r.message_id IS NOT NULL OR EXISTS (SELECT 1 FROM chat_reactions x WHERE x.message_id = m.id))
      ''',
      variables: [Variable.withString(conversationId)],
      // The side tables are unknown to drift: their writers notify through
      // `chat_messages` (see [_notifyMessagesChanged]).
      readsFrom: {chatMessages},
    ).watch().map(ChatMessageExtras._fromRows);
  }

  /// Wakes the queries reading `chat_messages`, e.g. [watchExtras].
  void _notifyMessagesChanged() {
    notifyUpdates({TableUpdate.onTable(chatMessages, kind: UpdateKind.update)});
  }

  // ---------------------------------------------------------------------
  // Pending retractions: "forget this message" frames for a peer whose
  // chat link is down, sent when it comes back (survives app restarts).
  // ---------------------------------------------------------------------

  Future<void> addPendingRetraction(String peerFingerprint, String messageId) async {
    await _ensureSideTables();
    await customInsert(
      'INSERT OR IGNORE INTO chat_pending_retractions (peer_fingerprint, message_id, created_at) VALUES (?, ?, ?)',
      variables: [
        Variable.withString(peerFingerprint),
        Variable.withString(messageId),
        Variable.withInt(DateTime.now().millisecondsSinceEpoch),
      ],
    );
  }

  /// The oldest [limit] retractions waiting for [peerFingerprint]. Expired
  /// ones (see [_pendingRetractionTtl]) are dropped first.
  Future<List<String>> pendingRetractions(String peerFingerprint, {required int limit}) async {
    await _ensureSideTables();
    await customUpdate(
      'DELETE FROM chat_pending_retractions WHERE created_at < ?',
      variables: [Variable.withInt(DateTime.now().subtract(_pendingRetractionTtl).millisecondsSinceEpoch)],
      updateKind: UpdateKind.delete,
    );
    final rows = await customSelect(
      'SELECT message_id FROM chat_pending_retractions WHERE peer_fingerprint = ? ORDER BY created_at LIMIT ?',
      variables: [Variable.withString(peerFingerprint), Variable.withInt(limit)],
    ).get();
    return [for (final row in rows) row.read<String>('message_id')];
  }

  Future<void> removePendingRetractions(String peerFingerprint, List<String> messageIds) async {
    if (messageIds.isEmpty) {
      return;
    }
    await _ensureSideTables();
    await customUpdate(
      'DELETE FROM chat_pending_retractions WHERE peer_fingerprint = ? AND message_id IN (${List.filled(messageIds.length, '?').join(', ')})',
      variables: [Variable.withString(peerFingerprint), for (final id in messageIds) Variable.withString(id)],
      updateKind: UpdateKind.delete,
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

  /// Number of outgoing messages of [conversationId] not sent yet
  /// (waiting for a chat link), for the conversation's connection banner.
  Stream<int> watchPendingCount(String conversationId) {
    final count = chatMessages.id.count();
    final query = selectOnly(chatMessages)
      ..addColumns([count])
      ..where(
        chatMessages.conversationId.equals(conversationId) &
            chatMessages.direction.equalsValue(ChatMessageDirectionColumn.outgoing) &
            chatMessages.status.equalsValue(ChatMessageStatusColumn.pending),
      );
    return query.map((row) => row.read(count) ?? 0).watchSingle();
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

/// The message a reply quotes, as shown above the reply. `null` fields
/// when the quoted message is not (or no longer) in this conversation.
class ChatQuotedMessage {
  final String id;
  final ChatMessageDirectionColumn? direction;
  final String? contentType;
  final String? body;
  final String? attachmentFileName;

  const ChatQuotedMessage({required this.id, this.direction, this.contentType, this.body, this.attachmentFileName});

  /// The quoted message still exists here.
  bool get isAvailable => direction != null;
}

/// Replies and reactions of one conversation, by message id.
class ChatMessageExtras {
  final Map<String, ChatQuotedMessage> quotes;

  /// Our reaction and the peer's.
  final Map<String, ({String? mine, String? peer})> reactions;

  const ChatMessageExtras({this.quotes = const {}, this.reactions = const {}});

  static const empty = ChatMessageExtras();

  static ChatMessageExtras _fromRows(List<QueryRow> rows) {
    final quotes = <String, ChatQuotedMessage>{};
    final reactions = <String, ({String? mine, String? peer})>{};
    for (final row in rows) {
      final id = row.read<String>('id');
      final replyTo = row.readNullable<String>('reply_to_id');
      if (replyTo != null) {
        final direction = row.readNullable<String>('quoted_direction');
        quotes[id] = ChatQuotedMessage(
          id: replyTo,
          direction: direction == null ? null : ChatMessageDirectionColumn.values.asNameMap()[direction],
          contentType: row.readNullable<String>('quoted_content_type'),
          body: row.readNullable<String>('quoted_body'),
          attachmentFileName: row.readNullable<String>('quoted_file_name'),
        );
      }
      final mine = row.readNullable<String>('my_reaction');
      final peer = row.readNullable<String>('peer_reaction');
      if (mine != null || peer != null) {
        reactions[id] = (mine: mine, peer: peer);
      }
    }
    return ChatMessageExtras(quotes: quotes, reactions: reactions);
  }
}
