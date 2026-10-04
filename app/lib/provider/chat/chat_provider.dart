import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:localsend_app/model/chat/chat_database.dart';
import 'package:localsend_app/model/chat/chat_envelope.dart';
import 'package:localsend_app/model/chat/chat_frame.dart';
import 'package:localsend_app/model/cross_file.dart';
import 'package:localsend_app/provider/chat/blocked_devices_provider.dart';
import 'package:localsend_app/provider/chat/chat_contact_policy.dart';
import 'package:localsend_app/provider/chat/chat_conversations_provider.dart';
import 'package:localsend_app/provider/chat/chat_database_provider.dart';
import 'package:localsend_app/provider/chat/chat_link_provider.dart';
import 'package:localsend_app/provider/chat/chat_link_supervisor.dart';
import 'package:localsend_app/provider/chat/peer_link_manager.dart';
import 'package:localsend_app/provider/device_info_provider.dart';
import 'package:localsend_app/provider/http_provider.dart';
import 'package:localsend_app/provider/network/nearby_devices_provider.dart';
import 'package:localsend_app/provider/network/send_provider.dart';
import 'package:localsend_app/provider/network/server/server_provider.dart';
import 'package:localsend_app/util/chat/chat_preview.dart';
import 'package:localsend_isolates/isolate.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/model/dto/file_dto.dart';
import 'package:localsend_isolates/model/file_type.dart';
import 'package:localsend_isolates/model/session_status.dart';
import 'package:localsend_isolates/rust/api/http.dart' as rust_http;
import 'package:localsend_isolates/rust/api/model.dart' as rust_model;
import 'package:localsend_isolates/util/rust.dart';
import 'package:logging/logging.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:uuid/uuid.dart';

final _logger = Logger('Chat');
const _uuid = Uuid();

/// How long a message sent over a chat link may wait for the peer's
/// `delivered` ack before it is sent again.
const _ackTimeout = Duration(seconds: 30);

/// Longest wait between two link attempts for a queued text message.
/// A contact that reappears is normally linked by [ChatLinkSupervisor],
/// which flushes its messages at once; this bounds the delay otherwise
/// (e.g. a peer only known from an earlier link, not from discovery).
const _maxLinkRetryDelay = Duration(seconds: 60);

/// How far in the future an incoming message's timestamp may be (clocks
/// of two devices differ a little). Later timestamps are replaced by the
/// reception time, so a wrong or hostile clock cannot pin a message at
/// the bottom of the conversation.
const _maxClockSkew = Duration(minutes: 2);

/// Read receipts are sent again, on reconnection, for messages read from
/// this long before the link went down: one may have been lost with it
/// (the peer ignores duplicates).
const _readResyncMargin = Duration(minutes: 1);

/// How long to wait before asking again a peer without a chat link, which
/// only changes when its app is updated. Matches `PeerLinkManager`.
const _legacyPeerRetryDelay = Duration(minutes: 10);

// Why a queued text message is not delivered, when waiting alone will not
// fix it. Shown under the message (French, like the other chat errors).
const _legacyPeerError = "Cet appareil utilise une version d'Aika sans messagerie instantanée. Mettez-le à jour pour recevoir ce message.";
const _unencryptedPeerError = 'Le chiffrement est désactivé sur cet appareil. Activez-le dans ses réglages pour discuter.';
const _impostorError = "L'identité de l'appareil n'a pas pu être vérifiée, message retenu.";

/// Ephemeral (non-persisted) chat UI state: who is currently typing towards
/// us, and who is reachable over a chat link right now. Everything else
/// (conversations, messages) lives in [ChatDatabase] and is consumed
/// reactively from there.
class ChatUiState {
  final Set<String> typingPeerFingerprints;

  /// Peers with a ready chat link (online). Peers on the legacy transport
  /// never appear here, see `nearbyDevicesProvider` for those.
  final Set<String> onlinePeerFingerprints;

  const ChatUiState({this.typingPeerFingerprints = const {}, this.onlinePeerFingerprints = const {}});

  ChatUiState copyWith({Set<String>? typingPeerFingerprints, Set<String>? onlinePeerFingerprints}) {
    return ChatUiState(
      typingPeerFingerprints: typingPeerFingerprints ?? this.typingPeerFingerprints,
      onlinePeerFingerprints: onlinePeerFingerprints ?? this.onlinePeerFingerprints,
    );
  }
}

/// High-level chat API used by the UI (send text/media, mark read, block,
/// export/delete) and by [ReceiveController] (route an incoming chat
/// envelope). Everything above this layer only deals with
/// [Device]/[ChatMessage]/[CrossFile].
///
/// Two transports, strictly separated:
/// - **Chat link** (persistent mTLS WebSocket, see [PeerLinkManager]): the
///   only transport for text messages, typing indicators and receipts.
///   When there is no link, they wait in the outbox (messages) or are
///   dropped (typing); they never fall back to the file-transfer pipeline.
/// - **File transfer** (`prepare-upload`/`upload`): media messages only,
///   with their [ChatEnvelope] smuggled in a reserved file (see
///   [kChatEnvelopeFileName]). Envelopes from older peers are still
///   received, see [handleIncomingEnvelope].
final chatProvider = NotifierProvider<ChatService, ChatUiState>((ref) {
  return ChatService();
});

class ChatService extends Notifier<ChatUiState> {
  /// Optional hook a notification layer can set to react to new incoming
  /// messages without this service depending on notification code
  /// (keeps the module boundary clean, see `chat_notification_service.dart`).
  void Function(Device sender, ChatEnvelope envelope)? onIncomingMessage;

  /// Called when the user opens (reads) a conversation, e.g. to clear its
  /// notification.
  void Function(String fingerprint)? onConversationRead;

  /// Fingerprint of the conversation currently visible on screen, if any.
  /// Set/cleared by `ChatConversationPage` itself; used by the
  /// notification layer to skip notifying about a message the user is
  /// already looking at.
  String? currentlyOpenConversationFingerprint;

  /// Serializes our own outbound media `prepare-upload` requests per peer
  /// so two of them never race for the peer's single transfer session
  /// (the Rust server answers `409` to the second one).
  final Map<String, Future<void>> _peerLocks = {};

  /// Correlates an accepted incoming attachment's file id back to the chat
  /// message row it belongs to, so `onAttachmentSaved` (called once the
  /// bytes are actually on disk) can stamp the local path.
  final Map<String, String> _pendingAttachmentFileIdToMessageId = {};

  DateTime? _lastTypingSentAt;
  Timer? _retryTimer;

  /// What each connected peer announced in its hello, and from which IP,
  /// to describe a sender that discovery has not seen (yet).
  final Map<String, (ChatHelloFrame, String)> _linkPeers = {};

  /// When this service started, and when each peer lost its last link:
  /// the read receipts to send again on reconnection start there.
  final DateTime _startedAt = DateTime.now().toUtc();
  final Map<String, DateTime> _linkLostAt = {};

  /// Reconnects to contacts on the network, see [startLinks].
  ChatLinkSupervisor? _supervisor;
  StreamSubscription<Object?>? _nearbySubscription;
  StreamSubscription<Object?>? _conversationsSubscription;

  /// The Rust server's `sessionId` of the chat-media download currently (or
  /// most recently) in flight, if any. `ReceiveController` cannot tag
  /// `ReceiveSessionState` itself as "belongs to chat" without touching the
  /// `dart_mappable`-generated session model, so it instead asks
  /// [isChatSession] and routes `onFileUpload`/session-end handling
  /// accordingly (skip the generic history/"open file" UI, call
  /// [onAttachmentSaved] instead).
  String? _activeIncomingChatSessionId;

  bool isChatSession(String sessionId) => _activeIncomingChatSessionId == sessionId;

  void beginIncomingChatSession(String sessionId) => _activeIncomingChatSessionId = sessionId;

  void endIncomingChatSession(String sessionId) {
    if (_activeIncomingChatSessionId == sessionId) {
      _activeIncomingChatSessionId = null;
    }
  }

  @override
  ChatUiState init() => const ChatUiState();

  // -------------------------------------------------------------------
  // Outgoing: user-initiated sends
  // -------------------------------------------------------------------

  /// Sends [text] (trimmed) as one message, or as several in a row when it
  /// is longer than a chat frame allows ([chatMaxTextLength]).
  Future<void> sendText({required Device target, required String text}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || await _isBlocked(target)) {
      return;
    }

    final db = ref.read(chatDatabaseProvider);
    await _touchConversation(target);

    final parts = splitChatText(trimmed);
    final start = DateTime.now().toUtc();
    for (var i = 0; i < parts.length; i++) {
      final messageId = _uuid.v4();
      // One millisecond apart, so the parts keep their order everywhere.
      final createdAt = start.add(Duration(milliseconds: i));
      await db.insertMessage(
        ChatMessagesCompanion.insert(
          id: messageId,
          conversationId: target.fingerprint,
          direction: ChatMessageDirectionColumn.outgoing,
          contentType: ChatContentType.text.name,
          status: ChatMessageStatusColumn.pending,
          createdAt: createdAt,
          body: Value(parts[i]),
        ),
      );
      await db.updateLastMessagePreview(target.fingerprint, preview: parts[i], at: createdAt);

      await _dispatchOutgoing(
        target: target,
        messageId: messageId,
        envelope: ChatEnvelope.message(messageId: messageId, contentType: ChatContentType.text, text: parts[i], timestamp: createdAt),
      );
    }
  }

  /// Sends [file] (image/video/document) as a chat message, optionally with
  /// a text [caption]. The file travels in the very same `prepare-upload`
  /// batch as the chat envelope - see [_sendMedia].
  Future<void> sendMedia({required Device target, required CrossFile file, String? caption}) async {
    if (await _isBlocked(target)) {
      return;
    }

    final db = ref.read(chatDatabaseProvider);
    await _touchConversation(target);

    final messageId = _uuid.v4();
    final now = DateTime.now().toUtc();
    final contentType = _fileTypeToContentType(file.fileType);
    await db.insertMessage(
      ChatMessagesCompanion.insert(
        id: messageId,
        conversationId: target.fingerprint,
        direction: ChatMessageDirectionColumn.outgoing,
        contentType: contentType.name,
        status: ChatMessageStatusColumn.pending,
        createdAt: now,
        body: Value(caption),
        attachmentPath: Value(file.path),
        attachmentFileName: Value(file.name),
        attachmentSize: Value(file.size),
      ),
    );
    await db.updateLastMessagePreview(target.fingerprint, preview: _previewFor(contentType, caption, file.name), at: now);

    await _dispatchOutgoing(
      target: target,
      messageId: messageId,
      envelope: ChatEnvelope.message(
        messageId: messageId,
        contentType: contentType,
        text: caption,
        attachmentFileId: _uuid.v4(),
        attachmentFileName: file.name,
        attachmentSize: file.size,
        timestamp: now,
      ),
      media: file,
    );
  }

  /// Best-effort "I am typing" / "I stopped typing" signal, sent only over
  /// an existing chat link. Never queued, never retried, never opens a link:
  /// if it is lost, the next keystroke (or its absence) naturally corrects
  /// the peer's view within a couple of seconds.
  Future<void> setTyping({required Device target, required bool isTyping}) async {
    final links = ref.read(peerLinkManagerProvider);
    if (!links.isReady(target.fingerprint) || await _isBlocked(target)) {
      return;
    }
    final now = DateTime.now();
    if (isTyping && _lastTypingSentAt != null && now.difference(_lastTypingSentAt!) < const Duration(seconds: 2)) {
      return;
    }
    _lastTypingSentAt = isTyping ? now : null;
    unawaited(links.send(target.fingerprint, ChatTypingFrame(isTyping: isTyping)));
  }

  /// Marks every unread incoming message of this conversation as read,
  /// resets the unread badge, and best-effort notifies the peer over the
  /// chat link with batched read receipts.
  ///
  /// Without a link the receipts are not sent (they never go through the
  /// file-transfer pipeline): they are sent on reconnection instead, see
  /// [_resendReadReceipts].
  Future<void> markConversationRead(Device target) async {
    final db = ref.read(chatDatabaseProvider);
    onConversationRead?.call(target.fingerprint);
    await db.resetUnread(target.fingerprint);

    final readIds = await db.markIncomingAsRead(target.fingerprint, DateTime.now().toUtc());

    // Opening a conversation is the right moment to (re)establish the link:
    // the user is likely to answer.
    if (!_isLinkable(target) || await _ensureLink(target) != PeerLinkStatus.ready) {
      return;
    }
    final links = ref.read(peerLinkManagerProvider);
    for (var i = 0; i < readIds.length; i += chatMaxIdsPerAck) {
      final chunk = readIds.sublist(i, (i + chatMaxIdsPerAck).clamp(0, readIds.length));
      unawaited(links.send(target.fingerprint, ChatAckFrame(ids: chunk, status: ChatReceiptStatus.read)));
    }
  }

  /// Sends an outgoing message again right away (user tapped "Retry"),
  /// including one that failed for good (e.g. declined by the peer).
  Future<void> retryMessage(String messageId) async {
    final db = ref.read(chatDatabaseProvider);
    final message = await db.getMessage(messageId);
    if (message == null ||
        message.direction != ChatMessageDirectionColumn.outgoing ||
        message.status == ChatMessageStatusColumn.delivered ||
        message.status == ChatMessageStatusColumn.read) {
      return;
    }
    if (message.status == ChatMessageStatusColumn.failed) {
      await db.updateMessageStatus(messageId, ChatMessageStatusColumn.pending, errorMessage: message.errorMessage);
    }
    await db.enqueueOutbox(messageId);
    await retryDueOutbox();
  }

  Future<void> deleteConversation(Device target) {
    return ref.read(chatDatabaseProvider).deleteConversation(target.fingerprint);
  }

  Future<String> exportConversation(Device target) {
    return ref.read(chatDatabaseProvider).exportConversationAsText(target.fingerprint);
  }

  Future<void> blockDevice(Device target) async {
    await ref.redux(blockedDevicesProvider).dispatchAsync(BlockDeviceAction(fingerprint: target.fingerprint, alias: target.alias));
    ref.read(peerLinkManagerProvider).disconnect(target.fingerprint);
  }

  Future<void> unblockDevice(String fingerprint) {
    return ref.redux(blockedDevicesProvider).dispatchAsync(UnblockDeviceAction(fingerprint));
  }

  // -------------------------------------------------------------------
  // Incoming: called by ReceiveController
  // -------------------------------------------------------------------

  /// Handles a decoded [ChatEnvelope] found in an incoming `prepare-upload`
  /// batch. Returns the subset of [allFilesInBatch] (besides the envelope
  /// itself, which is never accepted) that should actually be downloaded.
  Future<Set<String>> handleIncomingEnvelope({
    required Device sender,
    required ChatEnvelope envelope,
    required Map<String, FileDto> allFilesInBatch,
  }) async {
    final db = ref.read(chatDatabaseProvider);

    switch (envelope.kind) {
      case ChatEnvelopeKind.typing:
        _setTypingPeer(sender.fingerprint, envelope.isTyping ?? false);
        return const {};

      case ChatEnvelopeKind.receipt:
        final status = switch (envelope.receiptStatus) {
          ChatReceiptStatus.delivered => ChatMessageStatusColumn.delivered,
          ChatReceiptStatus.read => ChatMessageStatusColumn.read,
          null => null,
        };
        if (status != null) {
          // Scoped to the sender's own conversation (its fingerprint comes
          // from the mTLS certificate), see `ChatDatabase.applyReceipt`.
          await db.applyReceipt(
            conversationId: sender.fingerprint,
            messageIds: envelope.acknowledgedMessageIds,
            status: status,
            at: envelope.timestamp,
          );
        }
        return const {};

      case ChatEnvelopeKind.message:
        // No delivered receipt: it would have to travel back through the
        // file-transfer pipeline. The sender (an older app, or a media
        // message) only waits for one to show the double tick.
        await _storeIncomingMessage(sender, envelope);

        final attachmentId = envelope.attachmentFileId;
        if (attachmentId != null && allFilesInBatch.containsKey(attachmentId)) {
          _pendingAttachmentFileIdToMessageId[attachmentId] = envelope.messageId;
          return {attachmentId};
        }
        return const {};
    }
  }

  /// Stores a received message unless it is a duplicate (same id already
  /// stored, e.g. a retransmission whose ack got lost).
  Future<void> _storeIncomingMessage(Device sender, ChatEnvelope envelope) async {
    final db = ref.read(chatDatabaseProvider);
    if (await db.messageExists(envelope.messageId)) {
      return;
    }
    final now = DateTime.now().toUtc();
    final createdAt = envelope.timestamp.isAfter(now.add(_maxClockSkew)) ? now : envelope.timestamp;
    await db.upsertConversation(
      peerFingerprint: sender.fingerprint,
      peerAlias: sender.alias,
      peerDeviceModel: sender.deviceModel,
      lastSeenAt: DateTime.now().toUtc(),
    );
    await db.insertMessage(
      ChatMessagesCompanion.insert(
        id: envelope.messageId,
        conversationId: sender.fingerprint,
        direction: ChatMessageDirectionColumn.incoming,
        contentType: (envelope.contentType ?? ChatContentType.text).name,
        status: ChatMessageStatusColumn.delivered,
        createdAt: createdAt,
        body: Value(envelope.text),
        attachmentFileName: Value(envelope.attachmentFileName),
        attachmentSize: Value(envelope.attachmentSize),
        deliveredAt: Value(DateTime.now().toUtc()),
      ),
    );
    await db.incrementUnread(sender.fingerprint);
    await db.updateLastMessagePreview(
      sender.fingerprint,
      preview: _previewFor(envelope.contentType ?? ChatContentType.text, envelope.text, envelope.attachmentFileName),
      at: createdAt,
    );
    onIncomingMessage?.call(sender, envelope);
  }

  // -------------------------------------------------------------------
  // Chat links (WebSocket transport)
  // -------------------------------------------------------------------

  /// Starts the chat hub and routes its frames here, then keeps a link open
  /// with every contact discovery sees (see [ChatLinkSupervisor]). Call
  /// once, after the isolates are set up.
  void startLinks() {
    final links = ref.read(peerLinkManagerProvider)
      ..onFrame = _onLinkFrame
      ..onPeerReady = _onPeerReady
      ..onPeerGone = _onPeerGone
      ..start();
    _supervisor ??= ChatLinkSupervisor(
      links: links,
      isAllowed: (fingerprint) => !ref.read(blockedDevicesProvider).any((d) => d.fingerprint.toUpperCase() == fingerprint),
    );
    _nearbySubscription ??= ref.stream(nearbyDevicesProvider).listen((_) => _updateLinkCandidates());
    _conversationsSubscription ??= ref.stream(chatConversationsProvider).listen((_) => _updateLinkCandidates());
    _updateLinkCandidates();
  }

  /// Retries the links to every contact on the network right away, e.g.
  /// when the app comes back to the foreground.
  void retryLinksNow() => _supervisor?.retryNow();

  /// Contacts (devices with a conversation) that discovery sees over HTTPS
  /// are the peers to stay linked with.
  void _updateLinkCandidates() {
    final supervisor = _supervisor;
    if (supervisor == null) {
      return;
    }
    final contacts = {
      for (final conversation in ref.read(chatConversationsProvider)) conversation.peerFingerprint.toUpperCase(),
    };
    supervisor.setCandidates([
      for (final device in ref.read(nearbyDevicesProvider).devices.values)
        if (device.https && device.ip != null && device.port > 0 && contacts.contains(device.fingerprint.toUpperCase()))
          PeerAddress(fingerprint: device.fingerprint, ip: device.ip!, port: device.port),
    ]);
  }

  /// Whether a chat link to [target] exists or can be opened: links are
  /// mutually authenticated TLS, so dialing the peer needs it to serve
  /// HTTPS. (A peer with encryption off can still dial us: its link counts.)
  bool _isLinkable(Device target) => target.https || ref.read(peerLinkManagerProvider).isReady(target.fingerprint);

  /// Returns a chat link to [target], or why there is none.
  /// Callers check [_isLinkable] first.
  Future<PeerLinkStatus> _ensureLink(Device target) async {
    final links = ref.read(peerLinkManagerProvider);
    if (links.isReady(target.fingerprint)) {
      return PeerLinkStatus.ready;
    }
    final ip = target.ip;
    if (ip == null || target.port <= 0) {
      return PeerLinkStatus.unreachable;
    }
    return links.ensureLink(PeerAddress(fingerprint: target.fingerprint, ip: ip, port: target.port));
  }

  void _onPeerReady(String fingerprint, int version, ChatHelloFrame hello, String ip) {
    _linkPeers[fingerprint] = (hello, ip);
    final linkLostAt = _linkLostAt.remove(fingerprint) ?? _startedAt;
    state = state.copyWith(onlinePeerFingerprints: {...state.onlinePeerFingerprints, fingerprint});
    unawaited(
      Future(() async {
        final db = ref.read(chatDatabaseProvider);
        final now = DateTime.now().toUtc();
        await db.setPeerChatProtocol(fingerprint, version);
        await db.touchLastSeen(fingerprint, now);
        // Whatever waited for this peer goes out now, not at the next tick.
        await db.makeOutboxDueNow(fingerprint, now);
        await retryDueOutbox();
        // Reads since the previous link went down (or since the app
        // started, if there was none) were not acknowledged.
        await _resendReadReceipts(fingerprint, since: linkLostAt.subtract(_readResyncMargin));
      }),
    );
  }

  /// Read receipts for the messages read since [since]: those sent while
  /// there was no link never left this device. The peer ignores the ones
  /// it already has (a status never moves backwards).
  Future<void> _resendReadReceipts(String fingerprint, {required DateTime since}) async {
    final ids = await ref.read(chatDatabaseProvider).incomingReadSince(fingerprint, since, limit: chatMaxIdsPerAck);
    if (ids.isNotEmpty) {
      await ref.read(peerLinkManagerProvider).send(fingerprint, ChatAckFrame(ids: ids, status: ChatReceiptStatus.read));
    }
  }

  void _onPeerGone(String fingerprint) {
    _linkLostAt[fingerprint] = DateTime.now().toUtc();
    _supervisor?.onPeerGone(fingerprint);
    state = state.copyWith(
      onlinePeerFingerprints: {...state.onlinePeerFingerprints}..remove(fingerprint),
      typingPeerFingerprints: {...state.typingPeerFingerprints}..remove(fingerprint),
    );
    unawaited(ref.read(chatDatabaseProvider).touchLastSeen(fingerprint, DateTime.now().toUtc()));
  }

  void _onLinkFrame(String fingerprint, ChatFrame frame) {
    switch (frame) {
      case ChatMessageFrame():
        unawaited(_onLinkMessage(fingerprint, frame));
      case ChatAckFrame():
        unawaited(
          ref
              .read(chatDatabaseProvider)
              .applyReceipt(
                conversationId: fingerprint,
                messageIds: frame.ids,
                status: frame.status == ChatReceiptStatus.read ? ChatMessageStatusColumn.read : ChatMessageStatusColumn.delivered,
                at: DateTime.now().toUtc(),
              ),
        );
      case ChatTypingFrame():
        _setTypingPeer(fingerprint, frame.isTyping);
      case ChatHelloFrame():
        break;
    }
  }

  Future<void> _onLinkMessage(String fingerprint, ChatMessageFrame frame) async {
    final sender = _linkSender(fingerprint);
    if (sender == null) {
      return;
    }
    if (!await acceptChatSender(ref, sender)) {
      // Not acknowledged: the sender keeps it queued. A blocked peer's
      // link is closed so it stops retrying over it.
      if (ref.read(blockedDevicesProvider).isFingerprintBlocked(fingerprint)) {
        ref.read(peerLinkManagerProvider).disconnect(fingerprint);
      }
      return;
    }

    await _storeIncomingMessage(
      sender,
      ChatEnvelope.message(messageId: frame.id, contentType: frame.contentType, text: frame.text, timestamp: frame.timestamp),
    );
    // Acknowledged even for a duplicate: the previous ack was lost.
    await ref.read(peerLinkManagerProvider).send(fingerprint, ChatAckFrame(ids: [frame.id], status: ChatReceiptStatus.delivered));
  }

  /// The discovered device for [fingerprint], or one described by its hello.
  Device? _linkSender(String fingerprint) {
    final discovered = _resolveDevice(fingerprint);
    if (discovered != null) {
      return discovered;
    }
    final peer = _linkPeers[fingerprint];
    if (peer == null) {
      return null;
    }
    final (hello, ip) = peer;
    return Device.empty.copyWith(ip: ip, https: true, fingerprint: fingerprint, alias: hello.alias, deviceModel: hello.deviceModel);
  }

  /// Called once an accepted attachment finished downloading, so its local
  /// path can be attached to the corresponding chat message row.
  void onAttachmentSaved({required String fileId, required String path}) {
    final messageId = _pendingAttachmentFileIdToMessageId.remove(fileId);
    if (messageId == null) {
      return;
    }
    unawaited(ref.read(chatDatabaseProvider).attachLocalFile(messageId, path: path));
  }

  void _setTypingPeer(String fingerprint, bool isTyping) {
    final updated = {...state.typingPeerFingerprints};
    if (isTyping) {
      updated.add(fingerprint);
    } else {
      updated.remove(fingerprint);
    }
    state = state.copyWith(typingPeerFingerprints: updated);

    if (isTyping) {
      // Self-heals a lost "stopped typing" signal.
      Timer(const Duration(seconds: 6), () {
        final stale = {...state.typingPeerFingerprints}..remove(fingerprint);
        state = state.copyWith(typingPeerFingerprints: stale);
      });
    }
  }

  // -------------------------------------------------------------------
  // Persistent offline outbox (survives app restarts)
  // -------------------------------------------------------------------

  /// Starts the periodic retry loop. Idempotent; should be called once
  /// from `postInit()`.
  void startOutboxRetryLoop() {
    _retryTimer?.cancel();
    _retryTimer = Timer.periodic(const Duration(seconds: 15), (_) => retryDueOutbox());
    retryDueOutbox(); // ignore: discarded_futures
  }

  bool _retrying = false;
  bool _retryAgain = false;

  /// Sends every due outbox message. Never runs twice at once: a call made
  /// while a pass is running schedules one more pass instead.
  Future<void> retryDueOutbox() async {
    if (_retrying) {
      _retryAgain = true;
      return;
    }
    _retrying = true;
    try {
      do {
        _retryAgain = false;
        await _retryDueOutboxOnce();
      } while (_retryAgain);
    } finally {
      _retrying = false;
    }
  }

  Future<void> _retryDueOutboxOnce() async {
    final db = ref.read(chatDatabaseProvider);
    final due = await db.dueOutboxMessages(DateTime.now().toUtc());
    // Oldest first, so messages written offline go out in the order typed.
    due.sort((a, b) => a.$1.createdAt.compareTo(b.$1.createdAt));
    // One link attempt per peer and pass: ten queued messages to an offline
    // peer cost one connection timeout, not ten.
    final links = <String, PeerLinkStatus>{};
    for (final (message, attempts) in due) {
      final target = _resolveDevice(message.conversationId) ?? _linkSender(message.conversationId);
      if (target == null) {
        // Peer not currently visible via discovery: leave it queued, the
        // next periodic tick (or the peer reappearing) will retry it.
        continue;
      }
      await _retryOutboxMessage(message, attempts, target, links);
    }
  }

  Future<void> _retryOutboxMessage(ChatMessage message, int attempts, Device target, Map<String, PeerLinkStatus> links) async {
    final db = ref.read(chatDatabaseProvider);
    final contentType = ChatContentType.values.byName(message.contentType);

    CrossFile? media;
    String? attachmentFileId;
    if (contentType != ChatContentType.text && message.attachmentPath != null) {
      final file = File(message.attachmentPath!);
      if (!await file.exists()) {
        await db.updateMessageStatus(message.id, ChatMessageStatusColumn.failed, errorMessage: 'Fichier local introuvable, envoi annulé.');
        await db.removeFromOutbox(message.id);
        return;
      }
      attachmentFileId = _uuid.v4();
      media = CrossFile(
        name: message.attachmentFileName ?? file.uri.pathSegments.last,
        fileType: _contentTypeToFileType(contentType),
        size: message.attachmentSize ?? await file.length(),
        thumbnail: null,
        asset: null,
        path: message.attachmentPath,
        bytes: null,
        lastModified: null,
        lastAccessed: null,
      );
    }

    final envelope = ChatEnvelope.message(
      messageId: message.id,
      contentType: contentType,
      text: message.body,
      attachmentFileId: attachmentFileId,
      attachmentFileName: message.attachmentFileName,
      attachmentSize: message.attachmentSize,
      timestamp: message.createdAt,
    );

    if (media == null) {
      await _sendTextOverLink(target, envelope, attempts: attempts, links: links);
      return;
    }

    final outcome = await _sendMedia(target: target, envelope: envelope, media: media);
    if (outcome.success) {
      await db.updateMessageStatus(message.id, ChatMessageStatusColumn.sent);
      await db.removeFromOutbox(message.id);
    } else if (outcome.failureReason == _ChatSendFailureReason.blocked) {
      // Hard decline: retrying would just hammer the peer for nothing.
      await db.updateMessageStatus(message.id, ChatMessageStatusColumn.failed, errorMessage: outcome.errorMessage);
      await db.removeFromOutbox(message.id);
    } else {
      await db.updateMessageStatus(message.id, ChatMessageStatusColumn.pending, errorMessage: outcome.errorMessage);
      final nextAttempts = attempts + 1;
      await db.rescheduleOutbox(message.id, DateTime.now().toUtc().add(_backoffFor(nextAttempts)), nextAttempts);
    }
  }

  Device? _resolveDevice(String fingerprint) {
    for (final device in ref.read(nearbyDevicesProvider).devices.values) {
      if (device.fingerprint == fingerprint) {
        return device;
      }
    }
    return null;
  }

  Duration _backoffFor(int attempts) {
    final seconds = 5 * (1 << attempts.clamp(0, 7));
    return Duration(seconds: seconds.clamp(5, 600));
  }

  // -------------------------------------------------------------------
  // Low-level transport (shared by fresh sends and outbox retries)
  // -------------------------------------------------------------------

  Future<void> _dispatchOutgoing({
    required Device target,
    required String messageId,
    required ChatEnvelope envelope,
    CrossFile? media,
  }) async {
    if (media == null) {
      await _sendTextOverLink(target, envelope, attempts: 0);
      return;
    }

    final db = ref.read(chatDatabaseProvider);
    final outcome = await _sendMedia(target: target, envelope: envelope, media: media);
    if (outcome.success) {
      // No-op if the peer's "delivered" receipt was processed first.
      await db.updateMessageStatus(messageId, ChatMessageStatusColumn.sent);
      await db.removeFromOutbox(messageId);
    } else {
      await db.updateMessageStatus(messageId, ChatMessageStatusColumn.pending, errorMessage: outcome.errorMessage);
      // Retried even if the peer acknowledged the text part: the
      // attachment bytes may still be missing.
      await db.enqueueOutbox(messageId, nextAttemptAt: DateTime.now().toUtc().add(_backoffFor(1)));
    }
  }

  /// Sends a text message over the chat link, the only transport text
  /// messages use.
  ///
  /// - Sent: the message stays queued until the peer's `delivered` ack (see
  ///   `ChatDatabase.applyReceipt`) and is sent again after [_ackTimeout]
  ///   otherwise; the peer deduplicates it by id.
  /// - Not sent: it stays `pending` in the outbox and is tried again later.
  ///   A reason is shown only when waiting alone will not fix it.
  ///
  /// [links] caches the link status per peer during one outbox pass.
  Future<void> _sendTextOverLink(
    Device target,
    ChatEnvelope envelope, {
    required int attempts,
    Map<String, PeerLinkStatus>? links,
  }) async {
    final messageId = envelope.messageId;
    final nextAttempts = attempts + 1;

    if ((envelope.text?.length ?? 0) > chatMaxTextLength) {
      // Queued before texts were split ([sendText]): the peer would reject
      // it as malformed, and it would be sent again forever.
      final db = ref.read(chatDatabaseProvider);
      await db.updateMessageStatus(messageId, ChatMessageStatusColumn.failed, errorMessage: 'Message trop long pour être envoyé.');
      await db.removeFromOutbox(messageId);
      return;
    }

    if (!_isLinkable(target)) {
      await _holdInOutbox(messageId, nextAttempts, _linkRetryDelay(nextAttempts), errorMessage: _unencryptedPeerError);
      return;
    }

    final status = links?[target.fingerprint] ?? await _ensureLink(target);
    links?[target.fingerprint] = status;
    if (status != PeerLinkStatus.ready) {
      _logger.fine('Message $messageId kept in the outbox: no chat link to ${target.alias} (${status.name})');
    }
    switch (status) {
      case PeerLinkStatus.ready:
        final frame = ChatMessageFrame(
          id: messageId,
          timestamp: envelope.timestamp,
          contentType: envelope.contentType ?? ChatContentType.text,
          text: envelope.text,
        );
        if (await ref.read(peerLinkManagerProvider).send(target.fingerprint, frame)) {
          final db = ref.read(chatDatabaseProvider);
          final ackDue = DateTime.now().toUtc().add(_ackTimeout);
          await db.updateMessageStatus(messageId, ChatMessageStatusColumn.sent);
          await db.enqueueOutbox(messageId, nextAttemptAt: ackDue);
          await db.rescheduleOutbox(messageId, ackDue, nextAttempts);
          return;
        }
        // The link closed meanwhile.
        links?[target.fingerprint] = PeerLinkStatus.unreachable;
        await _holdInOutbox(messageId, nextAttempts, _linkRetryDelay(nextAttempts));
      case PeerLinkStatus.unreachable:
        await _holdInOutbox(messageId, nextAttempts, _linkRetryDelay(nextAttempts));
      case PeerLinkStatus.legacy:
        await _holdInOutbox(messageId, nextAttempts, _legacyPeerRetryDelay, errorMessage: _legacyPeerError);
      case PeerLinkStatus.impostor:
        await _holdInOutbox(messageId, nextAttempts, _backoffFor(nextAttempts), errorMessage: _impostorError);
    }
  }

  /// Keeps an unsent text message `pending` in the outbox until [delay]
  /// has passed, with [errorMessage] (or none) as the reason shown.
  /// A message the peer already acknowledged just leaves the outbox.
  Future<void> _holdInOutbox(String messageId, int attempts, Duration delay, {String? errorMessage}) async {
    final db = ref.read(chatDatabaseProvider);
    final message = await db.getMessage(messageId);
    if (message == null || message.status == ChatMessageStatusColumn.delivered || message.status == ChatMessageStatusColumn.read) {
      await db.removeFromOutbox(messageId);
      return;
    }
    // Refused (kept as is) for a message already `sent`, waiting for its ack.
    await db.updateMessageStatus(messageId, ChatMessageStatusColumn.pending, errorMessage: errorMessage);
    final at = DateTime.now().toUtc().add(delay);
    await db.enqueueOutbox(messageId, nextAttemptAt: at);
    await db.rescheduleOutbox(messageId, at, attempts);
  }

  /// [_backoffFor] capped at [_maxLinkRetryDelay]: 10 s, 20 s, 40 s, then 60 s.
  Duration _linkRetryDelay(int attempts) {
    final delay = _backoffFor(attempts);
    return delay > _maxLinkRetryDelay ? _maxLinkRetryDelay : delay;
  }

  /// Sends a media message through the file-transfer pipeline: its
  /// envelope and the file in one `prepare-upload` batch, then the bytes.
  /// Serialized per peer, see [_peerLocks].
  Future<_ChatSendOutcome> _sendMedia({
    required Device target,
    required ChatEnvelope envelope,
    required CrossFile media,
  }) {
    final previous = _peerLocks[target.fingerprint] ?? Future<void>.value();
    final result = previous.then((_) => _sendMediaLocked(target: target, envelope: envelope, media: media));
    _peerLocks[target.fingerprint] = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<_ChatSendOutcome> _sendMediaLocked({
    required Device target,
    required ChatEnvelope envelope,
    required CrossFile media,
  }) async {
    final mediaFileId = envelope.attachmentFileId;
    if (mediaFileId == null) {
      return const _ChatSendOutcome.failure(_ChatSendFailureReason.network, 'Pièce jointe invalide.');
    }
    if (target.ip == null) {
      return const _ChatSendOutcome.failure(_ChatSendFailureReason.network, 'Appareil injoignable (pas d\'adresse IP connue).');
    }

    // Never race a real (non-chat) transfer to/from this peer: a fresh
    // `prepare-upload` request would forcibly close the Rust server's
    // single active session on the receiving side (see the invariant
    // documented in `ReceiveController.onPrepareUpload`).
    const occupiedStates = {SessionStatus.waiting, SessionStatus.sending};
    final activeOutgoingRealTransfer = ref
        .read(sendProvider)
        .values
        .any((s) => s.target.fingerprint == target.fingerprint && occupiedStates.contains(s.status));
    final activeSession = ref.read(serverProvider)?.session;
    final activeIncomingRealTransfer =
        activeSession != null && activeSession.sender.fingerprint == target.fingerprint && occupiedStates.contains(activeSession.status);
    if (activeOutgoingRealTransfer || activeIncomingRealTransfer) {
      return const _ChatSendOutcome.failure(_ChatSendFailureReason.deferred, 'Un transfert de fichier est en cours avec cet appareil.');
    }

    final envelopeFileId = _uuid.v4();

    final files = <String, rust_model.FileDto>{
      envelopeFileId: FileDto(
        id: envelopeFileId,
        fileName: kChatEnvelopeFileName,
        size: utf8.encode(envelope.encode()).length,
        fileType: FileType.text,
        hash: null,
        preview: envelope.encode(),
        metadata: null,
      ).toRust(),
      mediaFileId: FileDto(
        id: mediaFileId,
        fileName: media.name,
        size: media.size,
        fileType: media.fileType,
        hash: null,
        preview: null,
        metadata: media.lastModified != null || media.lastAccessed != null
            ? FileMetadata(lastModified: media.lastModified, lastAccessed: media.lastAccessed)
            : null,
      ).toRust(),
    };

    final originDevice = ref.read(deviceFullInfoProvider);
    final requestDto = rust_model.PrepareUploadRequestDto(info: originDevice.toRegisterDto(), files: files);

    final client = ref.read(httpProvider).v2;
    rust_http.PrepareUploadResult response;
    try {
      response = await client.prepareUpload(
        protocol: target.getProtocolType(),
        ip: target.ip!,
        port: target.port,
        payload: requestDto,
        publicKey: null,
        pin: null,
      );
    } on rust_http.RsHttpClientError_StatusCode catch (e) {
      return switch (e.status) {
        // The receiver has a PIN configured. Chat, being headless, cannot
        // prompt for one; the message stays queued and will only go
        // through once the recipient disables their PIN (a documented
        // trade-off of not touching the Rust server, see project notes).
        401 => const _ChatSendOutcome.failure(_ChatSendFailureReason.pinRequired, 'Le destinataire a activé un code PIN pour la réception.'),
        403 => const _ChatSendOutcome.failure(_ChatSendFailureReason.blocked, 'Message refusé par le destinataire.'),
        409 => const _ChatSendOutcome.failure(_ChatSendFailureReason.busy, 'Le destinataire est occupé (transfert en cours).'),
        429 => const _ChatSendOutcome.failure(_ChatSendFailureReason.tooManyAttempts, 'Trop de tentatives, réessai plus tard.'),
        _ => _ChatSendOutcome.failure(_ChatSendFailureReason.network, e.humanErrorMessage),
      };
    } catch (e) {
      return _ChatSendOutcome.failure(_ChatSendFailureReason.network, e.humanErrorMessage);
    }

    final fileMap = response.statusCode == 204 ? const <String, String>{} : (response.response?.files ?? const <String, String>{});
    final token = fileMap[mediaFileId];
    if (token == null) {
      // The peer's chat layer decided not to fetch the attachment (e.g. it
      // does not yet trust this sender). Retry later via the outbox.
      return const _ChatSendOutcome.failure(_ChatSendFailureReason.network, 'Le média n\'a pas été accepté par le destinataire.');
    }

    final remoteSessionId = response.response?.sessionId;
    final taskResult = ref
        .redux(parentIsolateProvider)
        .dispatchTakeResult(
          IsolateHttpUploadFilesAction(
            remoteSessionId: remoteSessionId,
            files: [
              HttpUploadFile(
                remoteFileToken: token,
                fileId: mediaFileId,
                filePath: media.path,
                fileBytes: media.bytes,
                fileSize: media.size,
              ),
            ],
            device: target,
          ),
        );

    try {
      await for (final event in taskResult.events) {
        if (event is HttpUploadFileFailedEvent) {
          return _ChatSendOutcome.failure(_ChatSendFailureReason.network, event.error);
        }
      }
    } catch (e) {
      return _ChatSendOutcome.failure(_ChatSendFailureReason.network, e.humanErrorMessage);
    }

    return const _ChatSendOutcome.success();
  }

  Future<void> _touchConversation(Device target) {
    return ref
        .read(chatDatabaseProvider)
        .upsertConversation(
          peerFingerprint: target.fingerprint,
          peerAlias: target.alias,
          peerDeviceModel: target.deviceModel,
          lastSeenAt: DateTime.now().toUtc(),
        );
  }

  Future<bool> _isBlocked(Device target) async {
    return ref.read(blockedDevicesProvider).isFingerprintBlocked(target.fingerprint);
  }
}

String _previewFor(ChatContentType contentType, String? text, String? attachmentFileName) {
  return chatPreviewText(contentType, text: text, attachmentFileName: attachmentFileName);
}

ChatContentType _fileTypeToContentType(FileType fileType) {
  return switch (fileType) {
    FileType.image => ChatContentType.image,
    FileType.video => ChatContentType.video,
    FileType.text => ChatContentType.text,
    FileType.pdf || FileType.apk || FileType.other => ChatContentType.document,
  };
}

FileType _contentTypeToFileType(ChatContentType contentType) {
  return switch (contentType) {
    ChatContentType.image => FileType.image,
    ChatContentType.video => FileType.video,
    ChatContentType.text => FileType.text,
    ChatContentType.document || ChatContentType.audio => FileType.other,
  };
}

enum _ChatSendFailureReason { blocked, pinRequired, busy, tooManyAttempts, network, deferred }

class _ChatSendOutcome {
  final bool success;
  final _ChatSendFailureReason? failureReason;
  final String? errorMessage;

  const _ChatSendOutcome.success() : success = true, failureReason = null, errorMessage = null;

  const _ChatSendOutcome.failure(this.failureReason, this.errorMessage) : success = false;
}
