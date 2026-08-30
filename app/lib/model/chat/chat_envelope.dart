import 'dart:convert';

import 'package:collection/collection.dart';

/// Schema version of the chat envelope protocol.
/// Bump this whenever the JSON shape below changes in a
/// backwards-incompatible way, and branch on it in [ChatEnvelope.tryDecode].
const chatEnvelopeSchemaVersion = 1;

/// Reserved file name used to smuggle a [ChatEnvelope] through the existing
/// file-transfer pipeline (see [FileDto.preview]).
///
/// A file with this exact name and [FileType.text] is never treated as a
/// "real" file: it is intercepted by the chat layer both on the sending side
/// (never shown in the normal send-file picker) and on the receiving side
/// (never surfaced in the generic "Accept files?" screen, never saved to
/// disk). The leading dot has no special meaning on any of our target
/// platforms; it is only there to make the convention visually obvious to
/// anyone reading logs or a captured request.
const kChatEnvelopeFileName = '.aika-chat.v1.json';

/// What a [ChatEnvelope] represents.
///
/// Every kind is delivered the exact same way: as the `preview` field of a
/// small, reserved-name [FileDto] inside a normal `prepare-upload` request.
/// This works because `prepare-upload` already carries the full JSON body of
/// every file's metadata (including `preview`) to the receiver *before* any
/// byte is uploaded - exactly the mechanism the original "send a text
/// message" feature already relies on. No Rust/FFI change is required.
enum ChatEnvelopeKind {
  /// A user-visible chat message (text and/or a companion media file that
  /// travels in the very same `prepare-upload` batch).
  message,

  /// "This device is currently typing in the conversation." Best-effort,
  /// never retried, never queued: if it does not arrive, the next one will.
  typing,

  /// "I received message X" / "I read message X" acknowledgements.
  receipt,
}

/// The delivery state a [ChatEnvelopeKind.receipt] acknowledges.
enum ChatReceiptStatus { delivered, read }

/// The kind of content carried by a [ChatEnvelopeKind.message] envelope.
enum ChatContentType { text, image, video, document, audio }

/// Result of [ChatEnvelope.tryDecode]: either a decoded envelope, or a
/// reason it could not be decoded. Mirrors the pattern already used by
/// `QrPairingPayload.tryDecode` for consistency across the codebase.
sealed class ChatEnvelopeDecodeResult {
  const ChatEnvelopeDecodeResult();
}

class ChatEnvelopeDecodeSuccess extends ChatEnvelopeDecodeResult {
  final ChatEnvelope envelope;

  const ChatEnvelopeDecodeSuccess(this.envelope);
}

class ChatEnvelopeDecodeFailure extends ChatEnvelopeDecodeResult {
  final String reason;

  const ChatEnvelopeDecodeFailure(this.reason);
}

/// The payload embedded in the `preview` field of the reserved
/// [kChatEnvelopeFileName] file of a `prepare-upload` request.
///
/// This is intentionally a small, hand-written JSON model (no `dart_mappable`
/// codegen) so it stays trivial to read/write on the wire and easy to reason
/// about independently of build_runner, mirroring `QrPairingPayload`.
class ChatEnvelope {
  /// Schema version, see [chatEnvelopeSchemaVersion].
  final int schemaVersion;

  final ChatEnvelopeKind kind;

  /// Unique id of the chat message this envelope is about.
  /// - For [ChatEnvelopeKind.message]: the id of the new message.
  /// - For [ChatEnvelopeKind.receipt]: the id of the message being acked.
  /// - For [ChatEnvelopeKind.typing]: unused (empty string).
  final String messageId;

  /// Sender-side timestamp (UTC), used for ordering and display.
  final DateTime timestamp;

  // --- message-only fields ---
  final ChatContentType? contentType;

  /// Plain text body. Populated for [ChatContentType.text], and optionally
  /// used as a caption for media messages.
  final String? text;

  /// The [FileDto.id] of the companion media file that travels in the same
  /// `prepare-upload` batch as this envelope, for non-text content types.
  final String? attachmentFileId;
  final String? attachmentFileName;
  final int? attachmentSize;

  // --- typing-only fields ---
  final bool? isTyping;

  // --- receipt-only fields ---
  final ChatReceiptStatus? receiptStatus;

  const ChatEnvelope({
    required this.schemaVersion,
    required this.kind,
    required this.messageId,
    required this.timestamp,
    this.contentType,
    this.text,
    this.attachmentFileId,
    this.attachmentFileName,
    this.attachmentSize,
    this.isTyping,
    this.receiptStatus,
  });

  factory ChatEnvelope.message({
    required String messageId,
    required ChatContentType contentType,
    String? text,
    String? attachmentFileId,
    String? attachmentFileName,
    int? attachmentSize,
    DateTime? timestamp,
  }) {
    return ChatEnvelope(
      schemaVersion: chatEnvelopeSchemaVersion,
      kind: ChatEnvelopeKind.message,
      messageId: messageId,
      timestamp: timestamp ?? DateTime.now().toUtc(),
      contentType: contentType,
      text: text,
      attachmentFileId: attachmentFileId,
      attachmentFileName: attachmentFileName,
      attachmentSize: attachmentSize,
    );
  }

  factory ChatEnvelope.typing({required bool isTyping}) {
    return ChatEnvelope(
      schemaVersion: chatEnvelopeSchemaVersion,
      kind: ChatEnvelopeKind.typing,
      messageId: '',
      timestamp: DateTime.now().toUtc(),
      isTyping: isTyping,
    );
  }

  factory ChatEnvelope.receipt({
    required String messageId,
    required ChatReceiptStatus status,
  }) {
    return ChatEnvelope(
      schemaVersion: chatEnvelopeSchemaVersion,
      kind: ChatEnvelopeKind.receipt,
      messageId: messageId,
      timestamp: DateTime.now().toUtc(),
      receiptStatus: status,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'v': schemaVersion,
      'k': kind.name,
      'mid': messageId,
      'ts': timestamp.millisecondsSinceEpoch,
      if (contentType != null) 'ct': contentType!.name,
      if (text != null) 'txt': text,
      if (attachmentFileId != null) 'aid': attachmentFileId,
      if (attachmentFileName != null) 'aname': attachmentFileName,
      if (attachmentSize != null) 'asize': attachmentSize,
      if (isTyping != null) 'typ': isTyping,
      if (receiptStatus != null) 'rst': receiptStatus!.name,
    };
  }

  /// Compact JSON string, meant to be put directly into [FileDto.preview].
  String encode() => jsonEncode(toJson());

  static ChatEnvelopeDecodeResult tryDecode(String raw) {
    final Map<String, dynamic> json;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return const ChatEnvelopeDecodeFailure('not a JSON object');
      }
      json = decoded;
    } catch (_) {
      return const ChatEnvelopeDecodeFailure('malformed JSON');
    }

    final version = json['v'];
    if (version is! int || version != chatEnvelopeSchemaVersion) {
      // Forward-compatibility note: when this grows a v2, add a migration
      // branch here instead of outright rejecting - for now, phase 1 only
      // ever produced v1 envelopes.
      return ChatEnvelopeDecodeFailure('unsupported schema version: $version');
    }

    final kind = ChatEnvelopeKind.values.firstWhereOrNull((k) => k.name == json['k']);
    if (kind == null) {
      return const ChatEnvelopeDecodeFailure('unknown or missing kind');
    }

    final messageId = json['mid'];
    final tsRaw = json['ts'];
    if (messageId is! String || tsRaw is! int) {
      return const ChatEnvelopeDecodeFailure('missing mid/ts');
    }

    ChatContentType? contentType;
    if (json['ct'] is String) {
      contentType = ChatContentType.values.firstWhereOrNull((c) => c.name == json['ct']);
    }

    ChatReceiptStatus? receiptStatus;
    if (json['rst'] is String) {
      receiptStatus = ChatReceiptStatus.values.firstWhereOrNull((s) => s.name == json['rst']);
    }

    return ChatEnvelopeDecodeSuccess(
      ChatEnvelope(
        schemaVersion: version,
        kind: kind,
        messageId: messageId,
        timestamp: DateTime.fromMillisecondsSinceEpoch(tsRaw, isUtc: true),
        contentType: contentType,
        text: json['txt'] as String?,
        attachmentFileId: json['aid'] as String?,
        attachmentFileName: json['aname'] as String?,
        attachmentSize: json['asize'] as int?,
        isTyping: json['typ'] as bool?,
        receiptStatus: receiptStatus,
      ),
    );
  }
}
