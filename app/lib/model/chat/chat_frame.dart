import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:localsend_app/model/chat/chat_envelope.dart';

/// Version of the chat WebSocket protocol spoken by this app, announced in
/// [ChatHelloFrame] and stored per peer in `chat_conversations.peer_chat_protocol`.
///
/// Compatibility rules: adding an optional field or a new frame type does
/// not need a new version (unknown fields and frame types are ignored);
/// changing the meaning of an existing field does.
const chatWsProtocolVersion = 1;

/// Oldest protocol version this app still speaks.
const chatWsMinProtocolVersion = 1;

/// Upper bound of ids in one [ChatAckFrame], keeps frames small.
const chatMaxIdsPerAck = 500;

/// Longest text of one [ChatMessageFrame], in UTF-16 code units (like
/// WhatsApp). Longer texts are split by the sender; a longer frame is
/// rejected as malformed.
const chatMaxTextLength = 65536;

/// Longest message id accepted (ids are UUIDs, 36 characters).
const chatMaxIdLength = 64;

/// Longer aliases and device models announced in a [ChatHelloFrame] are
/// cut to this length: they are displayed, never trusted.
const chatMaxNameLength = 64;

/// A frame of the chat WebSocket protocol: a JSON object whose `t` field
/// names the frame type.
///
/// Hand-written like [ChatEnvelope] so the wire format stays explicit.
sealed class ChatFrame {
  const ChatFrame();

  String get type;

  Map<String, dynamic> toJson();

  String encode() => jsonEncode(toJson());

  /// Returns `null` for malformed input and for frame types this version
  /// does not know (sent by a newer peer), which must both be ignored.
  static ChatFrame? tryDecode(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return null;
    }
    if (decoded is! Map<String, dynamic>) {
      return null;
    }
    try {
      return switch (decoded['t']) {
        ChatHelloFrame.frameType => ChatHelloFrame._fromJson(decoded),
        ChatMessageFrame.frameType => ChatMessageFrame._fromJson(decoded),
        ChatAckFrame.frameType => ChatAckFrame._fromJson(decoded),
        ChatTypingFrame.frameType => ChatTypingFrame._fromJson(decoded),
        _ => null,
      };
    } on _InvalidFrame {
      return null;
    } on TypeError {
      return null;
    }
  }
}

class _InvalidFrame implements Exception {
  const _InvalidFrame();
}

/// First frame sent by both sides of a new connection. Nothing else is
/// processed on a connection before the peer's hello arrived.
class ChatHelloFrame extends ChatFrame {
  static const frameType = 'hello';

  /// Highest protocol version the sender speaks.
  final int version;

  /// Oldest protocol version the sender still speaks.
  final int minVersion;

  /// Display name of the sender, used for a conversation that does not
  /// exist yet (the peer may not have been discovered).
  final String alias;
  final String? deviceModel;

  const ChatHelloFrame({
    required this.version,
    required this.minVersion,
    required this.alias,
    this.deviceModel,
  });

  factory ChatHelloFrame._fromJson(Map<String, dynamic> json) {
    final version = json['v'] as int;
    final minVersion = json['min'] as int? ?? version;
    final alias = json['alias'] as String;
    if (version < 1 || minVersion < 1 || minVersion > version) {
      throw const _InvalidFrame();
    }
    return ChatHelloFrame(
      version: version,
      minVersion: minVersion,
      alias: _cut(alias),
      deviceModel: switch (json['model'] as String?) {
        final String model => _cut(model),
        null => null,
      },
    );
  }

  /// The version both sides speak, or `null` if there is none.
  int? negotiate(ChatHelloFrame own) {
    final agreed = version < own.version ? version : own.version;
    final floor = minVersion > own.minVersion ? minVersion : own.minVersion;
    return agreed >= floor ? agreed : null;
  }

  @override
  String get type => frameType;

  @override
  Map<String, dynamic> toJson() => {
    't': frameType,
    'v': version,
    'min': minVersion,
    'alias': alias,
    if (deviceModel != null) 'model': deviceModel,
  };
}

/// A chat message. Media still travels through the file-transfer pipeline
/// (legacy envelope), so V1 only sends text over the WebSocket.
class ChatMessageFrame extends ChatFrame {
  static const frameType = 'msg';

  /// Globally unique message id, the key for acknowledgements and dedup.
  final String id;

  /// Sender-side creation time (UTC).
  final DateTime timestamp;
  final ChatContentType contentType;
  final String? text;

  const ChatMessageFrame({
    required this.id,
    required this.timestamp,
    required this.contentType,
    this.text,
  });

  factory ChatMessageFrame._fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String;
    if (!_isValidId(id)) {
      throw const _InvalidFrame();
    }
    final contentType = ChatContentType.values.firstWhereOrNull((c) => c.name == json['ct']);
    if (contentType == null) {
      throw const _InvalidFrame();
    }
    final text = json['txt'] as String?;
    if (text != null && text.length > chatMaxTextLength) {
      throw const _InvalidFrame();
    }
    return ChatMessageFrame(
      id: id,
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['ts'] as int, isUtc: true),
      contentType: contentType,
      text: text,
    );
  }

  @override
  String get type => frameType;

  @override
  Map<String, dynamic> toJson() => {
    't': frameType,
    'id': id,
    'ts': timestamp.millisecondsSinceEpoch,
    'ct': contentType.name,
    if (text != null) 'txt': text,
  };
}

/// "I received / read these messages". A `delivered` ack is what takes a
/// message out of the sender's outbox: until then it is retransmitted
/// (the receiver deduplicates by id and acknowledges again).
class ChatAckFrame extends ChatFrame {
  static const frameType = 'ack';

  final List<String> ids;
  final ChatReceiptStatus status;

  const ChatAckFrame({required this.ids, required this.status});

  factory ChatAckFrame._fromJson(Map<String, dynamic> json) {
    final raw = json['ids'];
    if (raw is! List || raw.isEmpty || raw.length > chatMaxIdsPerAck || raw.any((e) => e is! String || !_isValidId(e))) {
      throw const _InvalidFrame();
    }
    final status = ChatReceiptStatus.values.firstWhereOrNull((s) => s.name == json['st']);
    if (status == null) {
      throw const _InvalidFrame();
    }
    return ChatAckFrame(ids: List.unmodifiable(raw.cast<String>()), status: status);
  }

  @override
  String get type => frameType;

  @override
  Map<String, dynamic> toJson() => {
    't': frameType,
    'ids': ids,
    'st': status.name,
  };
}

/// Best-effort typing indicator, never retransmitted.
class ChatTypingFrame extends ChatFrame {
  static const frameType = 'typing';

  final bool isTyping;

  const ChatTypingFrame({required this.isTyping});

  factory ChatTypingFrame._fromJson(Map<String, dynamic> json) => ChatTypingFrame(isTyping: json['on'] as bool);

  @override
  String get type => frameType;

  @override
  Map<String, dynamic> toJson() => {'t': frameType, 'on': isTyping};
}

bool _isValidId(String id) => id.isNotEmpty && id.length <= chatMaxIdLength;

/// [value] cut to [chatMaxNameLength], without splitting a surrogate pair.
String _cut(String value) {
  if (value.length <= chatMaxNameLength) {
    return value;
  }
  final end = _isHighSurrogate(value.codeUnitAt(chatMaxNameLength - 1)) ? chatMaxNameLength - 1 : chatMaxNameLength;
  return value.substring(0, end);
}

bool _isHighSurrogate(int codeUnit) => codeUnit >= 0xD800 && codeUnit <= 0xDBFF;

/// Splits [text] into parts of at most [chatMaxTextLength] code units,
/// never inside a surrogate pair (an emoji stays whole).
List<String> splitChatText(String text) {
  final parts = <String>[];
  var start = 0;
  while (text.length - start > chatMaxTextLength) {
    var end = start + chatMaxTextLength;
    if (_isHighSurrogate(text.codeUnitAt(end - 1))) {
      end--;
    }
    parts.add(text.substring(start, end));
    start = end;
  }
  parts.add(text.substring(start));
  return parts;
}
