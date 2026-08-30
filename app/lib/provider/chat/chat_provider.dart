import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:localsend_app/model/chat/chat_database.dart';
import 'package:localsend_app/model/chat/chat_envelope.dart';
import 'package:localsend_app/model/cross_file.dart';
import 'package:localsend_app/provider/chat/blocked_devices_provider.dart';
import 'package:localsend_app/provider/chat/chat_database_provider.dart';
import 'package:localsend_app/provider/device_info_provider.dart';
import 'package:localsend_app/provider/http_provider.dart';
import 'package:localsend_app/provider/network/nearby_devices_provider.dart';
import 'package:localsend_app/provider/network/send_provider.dart';
import 'package:localsend_app/provider/network/server/server_provider.dart';
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

/// Ephemeral (non-persisted) chat UI state: who is currently typing towards
/// us. Everything else (conversations, messages) lives in [ChatDatabase]
/// and is consumed reactively from there.
class ChatUiState {
  final Set<String> typingPeerFingerprints;

  const ChatUiState({this.typingPeerFingerprints = const {}});

  ChatUiState copyWith({Set<String>? typingPeerFingerprints}) {
    return ChatUiState(typingPeerFingerprints: typingPeerFingerprints ?? this.typingPeerFingerprints);
  }
}

/// High-level chat API used by the UI (send text/media, mark read, block,
/// export/delete) and by [ReceiveController] (route an incoming chat
/// envelope). This is the only place that talks to the low-level
/// `prepare-upload`/`upload` HTTP pipeline for chat purposes; everything
/// above this layer only deals with [Device]/[ChatMessage]/[CrossFile].
///
/// No Rust/FFI code was added for this feature: every network operation
/// below reuses the exact same `httpProvider`/`parentIsolateProvider`
/// surface the regular file-transfer feature already uses. See
/// [kChatEnvelopeFileName] for how a chat payload is smuggled through the
/// existing `prepare-upload` request.
final chatProvider = NotifierProvider<ChatService, ChatUiState>((ref) {
  return ChatService();
});

class ChatService extends Notifier<ChatUiState> {
  /// Optional hook a notification layer can set to react to new incoming
  /// messages without this service depending on notification code
  /// (keeps the module boundary clean, see `chat_notification_service.dart`).
  void Function(Device sender, ChatEnvelope envelope)? onIncomingMessage;

  /// Fingerprint of the conversation currently visible on screen, if any.
  /// Set/cleared by `ChatConversationPage` itself; used by the
  /// notification layer to skip notifying about a message the user is
  /// already looking at.
  String? currentlyOpenConversationFingerprint;

  /// Serializes our own outbound `prepare-upload` requests per peer so a
  /// lightweight signal (typing/receipt) can never race - and thus abort,
  /// per the Rust server's single-active-session invariant - a real message
  /// or media upload already in flight to the same peer.
  final Map<String, Future<void>> _peerLocks = {};

  /// Correlates an accepted incoming attachment's file id back to the chat
  /// message row it belongs to, so `onAttachmentSaved` (called once the
  /// bytes are actually on disk) can stamp the local path.
  final Map<String, String> _pendingAttachmentFileIdToMessageId = {};

  DateTime? _lastTypingSentAt;
  Timer? _retryTimer;

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

  Future<void> sendText({required Device target, required String text}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || await _isBlocked(target)) {
      return;
    }

    final db = ref.read(chatDatabaseProvider);
    await _touchConversation(target);

    final messageId = _uuid.v4();
    final now = DateTime.now().toUtc();
    await db.insertMessage(
      ChatMessagesCompanion.insert(
        id: messageId,
        conversationId: target.fingerprint,
        direction: ChatMessageDirectionColumn.outgoing,
        contentType: ChatContentType.text.name,
        status: ChatMessageStatusColumn.pending,
        createdAt: now,
        body: Value(trimmed),
      ),
    );
    await db.updateLastMessagePreview(target.fingerprint, preview: trimmed, at: now);

    await _dispatchOutgoing(
      target: target,
      messageId: messageId,
      envelope: ChatEnvelope.message(messageId: messageId, contentType: ChatContentType.text, text: trimmed, timestamp: now),
    );
  }

  /// Sends [file] (image/video/document) as a chat message, optionally with
  /// a text [caption]. The file travels in the very same `prepare-upload`
  /// batch as the chat envelope - see [_trySend].
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

  /// Best-effort "I am typing" / "I stopped typing" signal. Never queued,
  /// never retried: if it is lost, the next keystroke (or its absence)
  /// naturally corrects the peer's view within a couple of seconds.
  Future<void> setTyping({required Device target, required bool isTyping}) async {
    if (await _isBlocked(target)) {
      return;
    }
    final now = DateTime.now();
    if (isTyping && _lastTypingSentAt != null && now.difference(_lastTypingSentAt!) < const Duration(seconds: 2)) {
      return;
    }
    _lastTypingSentAt = isTyping ? now : null;

    unawaited(
      Future(() async {
        try {
          await _trySend(target: target, envelope: ChatEnvelope.typing(isTyping: isTyping));
        } catch (e) {
          _logger.fine('Typing signal not delivered (ignored): $e');
        }
      }),
    );
  }

  /// Marks every unread incoming message of this conversation as read,
  /// resets the unread badge, and best-effort notifies the peer with one
  /// receipt per message.
  Future<void> markConversationRead(Device target) async {
    final db = ref.read(chatDatabaseProvider);
    await db.resetUnread(target.fingerprint);

    final unreadIds = await db.unreadIncomingMessageIds(target.fingerprint);
    for (final messageId in unreadIds) {
      await db.updateMessageStatus(messageId, ChatMessageStatusColumn.read, readAt: DateTime.now().toUtc());
      unawaited(
        Future(() async {
          try {
            await _trySend(target: target, envelope: ChatEnvelope.receipt(messageId: messageId, status: ChatReceiptStatus.read));
          } catch (e) {
            _logger.fine('Read receipt not delivered (ignored): $e');
          }
        }),
      );
    }
  }

  Future<void> deleteConversation(Device target) {
    return ref.read(chatDatabaseProvider).deleteConversation(target.fingerprint);
  }

  Future<String> exportConversation(Device target) {
    return ref.read(chatDatabaseProvider).exportConversationAsText(target.fingerprint);
  }

  Future<void> blockDevice(Device target) async {
    await ref.redux(blockedDevicesProvider).dispatchAsync(BlockDeviceAction(fingerprint: target.fingerprint, alias: target.alias));
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
        if (envelope.receiptStatus == ChatReceiptStatus.delivered) {
          await db.updateMessageStatus(envelope.messageId, ChatMessageStatusColumn.delivered, deliveredAt: envelope.timestamp);
        } else if (envelope.receiptStatus == ChatReceiptStatus.read) {
          await db.updateMessageStatus(envelope.messageId, ChatMessageStatusColumn.read, readAt: envelope.timestamp);
        }
        return const {};

      case ChatEnvelopeKind.message:
        if (!await db.messageExists(envelope.messageId)) {
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
              createdAt: envelope.timestamp,
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
            at: envelope.timestamp,
          );
          onIncomingMessage?.call(sender, envelope);
        }

        // Best-effort delivered-receipt; a missed one is harmless, the
        // read-receipt sent when the recipient opens the chat subsumes it.
        unawaited(
          Future(() async {
            try {
              await _trySend(target: sender, envelope: ChatEnvelope.receipt(messageId: envelope.messageId, status: ChatReceiptStatus.delivered));
            } catch (_) {}
          }),
        );

        final attachmentId = envelope.attachmentFileId;
        if (attachmentId != null && allFilesInBatch.containsKey(attachmentId)) {
          _pendingAttachmentFileIdToMessageId[attachmentId] = envelope.messageId;
          return {attachmentId};
        }
        return const {};
    }
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

  Future<void> retryDueOutbox() async {
    final db = ref.read(chatDatabaseProvider);
    final due = await db.dueOutboxMessages(DateTime.now().toUtc());
    for (final (message, attempts) in due) {
      final target = _resolveDevice(message.conversationId);
      if (target == null) {
        // Peer not currently visible via discovery: leave it queued, the
        // next periodic tick (or the peer reappearing) will retry it.
        continue;
      }
      await _retryOutboxMessage(message, attempts, target);
    }
  }

  Future<void> _retryOutboxMessage(ChatMessage message, int attempts, Device target) async {
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

    final outcome = await _trySend(target: target, envelope: envelope, media: media);
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
    final db = ref.read(chatDatabaseProvider);
    final outcome = await _trySend(target: target, envelope: envelope, media: media);
    if (outcome.success) {
      await db.updateMessageStatus(messageId, ChatMessageStatusColumn.sent);
      await db.removeFromOutbox(messageId);
    } else {
      await db.updateMessageStatus(messageId, ChatMessageStatusColumn.pending, errorMessage: outcome.errorMessage);
      await db.enqueueOutbox(messageId, nextAttemptAt: DateTime.now().toUtc().add(_backoffFor(1)));
    }
  }

  Future<_ChatSendOutcome> _trySend({
    required Device target,
    required ChatEnvelope envelope,
    CrossFile? media,
  }) {
    final previous = _peerLocks[target.fingerprint] ?? Future<void>.value();
    final result = previous.then((_) => _trySendLocked(target: target, envelope: envelope, media: media));
    _peerLocks[target.fingerprint] = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<_ChatSendOutcome> _trySendLocked({
    required Device target,
    required ChatEnvelope envelope,
    CrossFile? media,
  }) async {
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
    final activeIncomingRealTransfer = activeSession != null && activeSession.sender.fingerprint == target.fingerprint && occupiedStates.contains(activeSession.status);
    if (activeOutgoingRealTransfer || activeIncomingRealTransfer) {
      return const _ChatSendOutcome.failure(_ChatSendFailureReason.deferred, 'Un transfert de fichier est en cours avec cet appareil.');
    }

    final envelopeFileId = _uuid.v4();
    final mediaFileId = envelope.attachmentFileId;

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
      if (media != null && mediaFileId != null)
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

    if (media == null || mediaFileId == null) {
      // Text-only signal: its full content already traveled inside the
      // envelope's `preview` field, exactly like the pre-existing "send a
      // text message" feature. No byte-upload is necessary; a 204 (or an
      // empty file map) confirms the peer fully consumed it that way.
      return const _ChatSendOutcome.success();
    }

    final fileMap = response.statusCode == 204 ? const <String, String>{} : (response.response?.files ?? const <String, String>{});
    final token = fileMap[mediaFileId];
    if (token == null) {
      // The peer's chat layer decided not to fetch the attachment (e.g. it
      // does not yet trust this sender). Retry later via the outbox.
      return const _ChatSendOutcome.failure(_ChatSendFailureReason.network, 'Le média n\'a pas été accepté par le destinataire.');
    }

    final remoteSessionId = response.response?.sessionId;
    final taskResult = ref.redux(parentIsolateProvider).dispatchTakeResult(
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
    return ref.read(chatDatabaseProvider).upsertConversation(
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

/// Short, human-readable summary of a message used in the conversation
/// list (e.g. "📷 Photo" instead of the raw file name for media messages).
String _previewFor(ChatContentType contentType, String? text, String? attachmentFileName) {
  if (contentType == ChatContentType.text) {
    return text ?? '';
  }
  final label = switch (contentType) {
    ChatContentType.image => 'Photo',
    ChatContentType.video => 'Vidéo',
    ChatContentType.audio => 'Audio',
    ChatContentType.document => attachmentFileName ?? 'Document',
    ChatContentType.text => text ?? '',
  };
  return (text != null && text.isNotEmpty) ? '$label · $text' : label;
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
