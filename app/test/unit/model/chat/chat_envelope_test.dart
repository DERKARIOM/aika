import 'dart:convert';

import 'package:localsend_app/model/chat/chat_envelope.dart';
import 'package:localsend_isolates/model/dto/file_dto.dart';
import 'package:localsend_isolates/model/file_type.dart';
import 'package:localsend_isolates/util/rust.dart';
import 'package:test/test.dart';

ChatEnvelope _decode(String raw) {
  final result = ChatEnvelope.tryDecode(raw);
  expect(result, isA<ChatEnvelopeDecodeSuccess>());
  return (result as ChatEnvelopeDecodeSuccess).envelope;
}

String _failureReason(String raw) {
  final result = ChatEnvelope.tryDecode(raw);
  expect(result, isA<ChatEnvelopeDecodeFailure>());
  return (result as ChatEnvelopeDecodeFailure).reason;
}

void main() {
  group('isChatEnvelopeFile', () {
    FileDto file(String name, {String? preview}) => FileDto(
      id: 'f',
      fileName: name,
      size: 10,
      fileType: FileType.text,
      hash: null,
      preview: preview,
      metadata: null,
    );

    test('Should recognize the envelope as it arrives over the network', () {
      final envelope = ChatEnvelope.message(messageId: 'm1', contentType: ChatContentType.image, attachmentFileId: 'a1');
      // As sent then received: the type is re-derived from the `.json` name.
      final received = file(kChatEnvelopeFileName, preview: envelope.encode()).toRust().toDart();

      expect(received.fileType, isNot(FileType.text));
      expect(isChatEnvelopeFile(received), true);
    });

    test('Should not take an ordinary file for the envelope', () {
      expect(isChatEnvelopeFile(file('photo.json', preview: '{}')), false);
      expect(isChatEnvelopeFile(file(kChatEnvelopeFileName)), false);
    });
  });

  group('ChatEnvelope round trip', () {
    test('Should encode and decode a text message', () {
      final ts = DateTime.utc(2026, 9, 30, 12, 0, 0);
      final envelope = ChatEnvelope.message(messageId: 'm1', contentType: ChatContentType.text, text: 'Salut 👋', timestamp: ts);

      final decoded = _decode(envelope.encode());

      expect(decoded.schemaVersion, chatEnvelopeSchemaVersion);
      expect(decoded.kind, ChatEnvelopeKind.message);
      expect(decoded.messageId, 'm1');
      expect(decoded.timestamp, ts);
      expect(decoded.contentType, ChatContentType.text);
      expect(decoded.text, 'Salut 👋');
      expect(decoded.messageIds, isNull);
    });

    test('Should encode and decode a media message', () {
      final envelope = ChatEnvelope.message(
        messageId: 'm2',
        contentType: ChatContentType.image,
        text: 'légende',
        attachmentFileId: 'f1',
        attachmentFileName: 'photo.jpg',
        attachmentSize: 1234,
      );

      final decoded = _decode(envelope.encode());

      expect(decoded.contentType, ChatContentType.image);
      expect(decoded.text, 'légende');
      expect(decoded.attachmentFileId, 'f1');
      expect(decoded.attachmentFileName, 'photo.jpg');
      expect(decoded.attachmentSize, 1234);
    });

    test('Should encode and decode a typing signal', () {
      final decoded = _decode(ChatEnvelope.typing(isTyping: true).encode());

      expect(decoded.kind, ChatEnvelopeKind.typing);
      expect(decoded.isTyping, true);
      expect(decoded.messageId, '');
      expect(decoded.acknowledgedMessageIds, isEmpty);
    });

    test('Should encode a single receipt without mids', () {
      final envelope = ChatEnvelope.receipt(messageId: 'm1', status: ChatReceiptStatus.delivered);

      expect(envelope.toJson().containsKey('mids'), false);

      final decoded = _decode(envelope.encode());
      expect(decoded.receiptStatus, ChatReceiptStatus.delivered);
      expect(decoded.acknowledgedMessageIds, ['m1']);
    });

    test('Should encode a batched receipt with mids and the newest id as mid', () {
      final envelope = ChatEnvelope.batchReceipt(messageIds: ['a', 'b', 'c'], status: ChatReceiptStatus.read);

      final json = envelope.toJson();
      expect(json['mid'], 'c');
      expect(json['mids'], ['a', 'b', 'c']);

      final decoded = _decode(envelope.encode());
      expect(decoded.receiptStatus, ChatReceiptStatus.read);
      expect(decoded.messageId, 'c');
      expect(decoded.acknowledgedMessageIds, ['a', 'b', 'c']);
    });

    test('Should not add mids for a batch of one', () {
      final envelope = ChatEnvelope.batchReceipt(messageIds: ['a'], status: ChatReceiptStatus.read);

      expect(envelope.toJson().containsKey('mids'), false);
      expect(_decode(envelope.encode()).acknowledgedMessageIds, ['a']);
    });
  });

  group('ChatEnvelope compatibility', () {
    test('Should decode a v1.0.3 receipt (mid only)', () {
      final raw = jsonEncode({'v': 1, 'k': 'receipt', 'mid': 'm1', 'ts': 0, 'rst': 'read'});

      final decoded = _decode(raw);

      expect(decoded.messageIds, isNull);
      expect(decoded.acknowledgedMessageIds, ['m1']);
    });

    test('Should not duplicate mid when it is also listed in mids', () {
      final raw = jsonEncode({
        'v': 1,
        'k': 'receipt',
        'mid': 'b',
        'mids': ['a', 'b'],
        'ts': 0,
        'rst': 'read',
      });

      expect(_decode(raw).acknowledgedMessageIds, ['a', 'b']);
    });

    test('Should ignore unknown fields', () {
      final raw = jsonEncode({'v': 1, 'k': 'message', 'mid': 'm1', 'ts': 0, 'ct': 'text', 'txt': 'x', 'future': 42});

      expect(_decode(raw).text, 'x');
    });
  });

  group('ChatEnvelope malformed input', () {
    test('Should reject malformed JSON', () {
      expect(_failureReason('{not json'), 'malformed JSON');
    });

    test('Should reject a non-object', () {
      expect(_failureReason('[1, 2]'), 'not a JSON object');
    });

    test('Should reject an unsupported schema version', () {
      expect(_failureReason(jsonEncode({'v': 2, 'k': 'message', 'mid': 'm', 'ts': 0})), startsWith('unsupported schema version'));
    });

    test('Should reject an unknown kind', () {
      expect(_failureReason(jsonEncode({'v': 1, 'k': 'nope', 'mid': 'm', 'ts': 0})), 'unknown or missing kind');
    });

    test('Should reject a missing timestamp', () {
      expect(_failureReason(jsonEncode({'v': 1, 'k': 'message', 'mid': 'm'})), 'missing mid/ts');
    });

    test('Should reject mids that are not a list of strings', () {
      expect(_failureReason(jsonEncode({'v': 1, 'k': 'receipt', 'mid': 'm', 'ts': 0, 'mids': 'm'})), 'invalid mids');
      expect(
        _failureReason(
          jsonEncode({
            'v': 1,
            'k': 'receipt',
            'mid': 'm',
            'ts': 0,
            'mids': ['m', 3],
          }),
        ),
        'invalid mids',
      );
    });

    test('Should reject a wrongly-typed optional field instead of throwing', () {
      expect(_failureReason(jsonEncode({'v': 1, 'k': 'message', 'mid': 'm', 'ts': 0, 'txt': 5})), 'invalid field type');
      expect(_failureReason(jsonEncode({'v': 1, 'k': 'message', 'mid': 'm', 'ts': 0, 'asize': '10'})), 'invalid field type');
    });
  });
}
