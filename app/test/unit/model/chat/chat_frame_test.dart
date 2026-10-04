import 'dart:convert';

import 'package:localsend_app/model/chat/chat_envelope.dart';
import 'package:localsend_app/model/chat/chat_frame.dart';
import 'package:test/test.dart';

T _roundTrip<T extends ChatFrame>(T frame) {
  final decoded = ChatFrame.tryDecode(frame.encode());
  expect(decoded, isA<T>());
  return decoded as T;
}

void main() {
  group('ChatFrame round trip', () {
    test('Should encode and decode hello', () {
      final hello = _roundTrip(const ChatHelloFrame(version: 3, minVersion: 1, alias: 'Alice', deviceModel: 'Pixel'));

      expect(hello.version, 3);
      expect(hello.minVersion, 1);
      expect(hello.alias, 'Alice');
      expect(hello.deviceModel, 'Pixel');
    });

    test('Should encode and decode a text message', () {
      final ts = DateTime.utc(2026, 9, 30, 12);
      final msg = _roundTrip(ChatMessageFrame(id: 'm1', timestamp: ts, contentType: ChatContentType.text, text: 'Salut 👋'));

      expect(msg.id, 'm1');
      expect(msg.timestamp, ts);
      expect(msg.contentType, ChatContentType.text);
      expect(msg.text, 'Salut 👋');
    });

    test('Should encode and decode an ack', () {
      final ack = _roundTrip(const ChatAckFrame(ids: ['a', 'b'], status: ChatReceiptStatus.read));

      expect(ack.ids, ['a', 'b']);
      expect(ack.status, ChatReceiptStatus.read);
    });

    test('Should encode and decode typing', () {
      expect(_roundTrip(const ChatTypingFrame(isTyping: true)).isTyping, true);
    });
  });

  group('ChatFrame decoding', () {
    test('Should ignore an unknown frame type from a newer peer', () {
      expect(ChatFrame.tryDecode(jsonEncode({'t': 'reaction', 'id': 'm1'})), isNull);
    });

    test('Should ignore unknown fields', () {
      final frame = ChatFrame.tryDecode(jsonEncode({'t': 'typing', 'on': false, 'future': 1}));
      expect((frame! as ChatTypingFrame).isTyping, false);
    });

    test('Should reject malformed input', () {
      expect(ChatFrame.tryDecode('not json'), isNull);
      expect(ChatFrame.tryDecode('[1]'), isNull);
      expect(ChatFrame.tryDecode(jsonEncode({'t': 'msg', 'id': 'm1'})), isNull);
      expect(ChatFrame.tryDecode(jsonEncode({'t': 'msg', 'id': '', 'ts': 0, 'ct': 'text'})), isNull);
      expect(ChatFrame.tryDecode(jsonEncode({'t': 'msg', 'id': 'm', 'ts': 0, 'ct': 'hologram'})), isNull);
      expect(ChatFrame.tryDecode(jsonEncode({'t': 'hello', 'v': 1, 'min': 2, 'alias': 'x'})), isNull);
      expect(ChatFrame.tryDecode(jsonEncode({'t': 'typing', 'on': 'yes'})), isNull);
    });

    test('Should bound acks', () {
      expect(ChatFrame.tryDecode(jsonEncode({'t': 'ack', 'ids': <String>[], 'st': 'read'})), isNull);
      expect(ChatFrame.tryDecode(jsonEncode({'t': 'ack', 'ids': List.filled(chatMaxIdsPerAck + 1, 'x'), 'st': 'read'})), isNull);
      expect(
        ChatFrame.tryDecode(
          jsonEncode({
            't': 'ack',
            'ids': ['a', 1],
            'st': 'read',
          }),
        ),
        isNull,
      );
      expect(
        ChatFrame.tryDecode(
          jsonEncode({
            't': 'ack',
            'ids': ['a'],
            'st': 'seen',
          }),
        ),
        isNull,
      );
    });
  });

  group('ChatFrame limits', () {
    String message({String id = 'm1', String? text}) => jsonEncode({
      't': 'msg',
      'id': id,
      'ts': 0,
      'ct': 'text',
      'txt': ?text,
    });

    test('Should accept a text of the maximum length', () {
      final frame = ChatFrame.tryDecode(message(text: 'a' * chatMaxTextLength));
      expect(frame, isA<ChatMessageFrame>());
    });

    test('Should reject a longer text or id', () {
      expect(ChatFrame.tryDecode(message(text: 'a' * (chatMaxTextLength + 1))), isNull);
      expect(ChatFrame.tryDecode(message(id: 'i' * (chatMaxIdLength + 1))), isNull);
      expect(
        ChatFrame.tryDecode(
          jsonEncode({
            't': 'ack',
            'ids': ['i' * (chatMaxIdLength + 1)],
            'st': 'read',
          }),
        ),
        isNull,
      );
    });

    test('Should cut a long alias and device model without breaking an emoji', () {
      final alias = '${'a' * (chatMaxNameLength - 1)}👋';
      final hello = ChatFrame.tryDecode(jsonEncode({'t': 'hello', 'v': 1, 'alias': alias, 'model': 'm' * 500})) as ChatHelloFrame;

      expect(hello.alias, 'a' * (chatMaxNameLength - 1));
      expect(hello.deviceModel!.length, chatMaxNameLength);
    });

    test('Should split a long text without breaking an emoji', () {
      final text = '${'a' * (chatMaxTextLength - 1)}👋 fin';
      final parts = splitChatText(text);

      expect(parts, ['a' * (chatMaxTextLength - 1), '👋 fin']);
      expect(parts.join(), text);
      expect(splitChatText('court'), ['court']);
    });
  });

  group('ChatHelloFrame.negotiate', () {
    const own = ChatHelloFrame(version: 3, minVersion: 2, alias: 'me');

    test('Should agree on the highest common version', () {
      expect(const ChatHelloFrame(version: 5, minVersion: 1, alias: 'p').negotiate(own), 3);
      expect(const ChatHelloFrame(version: 2, minVersion: 1, alias: 'p').negotiate(own), 2);
    });

    test('Should return null without a common version', () {
      expect(const ChatHelloFrame(version: 1, minVersion: 1, alias: 'p').negotiate(own), isNull);
      expect(const ChatHelloFrame(version: 9, minVersion: 4, alias: 'p').negotiate(own), isNull);
    });
  });
}
