import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:localsend_app/model/chat/chat_envelope.dart';

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

  Future<ChatMessage?> getMessage(String messageId) {
    return (select(chatMessages)..where((t) => t.id.equals(messageId))).getSingleOrNull();
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
