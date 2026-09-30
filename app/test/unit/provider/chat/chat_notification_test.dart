import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/chat/chat_envelope.dart';
import 'package:localsend_app/provider/chat/chat_notification_service.dart';
import 'package:localsend_app/util/chat/chat_preview.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(() {
    LocaleSettings.setLocaleSync(AppLocale.en);
  });

  group('chatNotificationId', () {
    test('Should be stable and derived from the fingerprint', () {
      expect(chatNotificationId('A1B2C3D4E5F6'), 0xA1B2C3D);
      expect(chatNotificationId('A1B2C3D4E5F6'), chatNotificationId('A1B2C3D4E5F6'));
      expect(chatNotificationId('A1B2C3D4E5F6'), isNot(chatNotificationId('FFB2C3D4E5F6')));
    });

    test('Should stay a positive 32-bit id for any input', () {
      expect(chatNotificationId('not-hex-at-all'), inInclusiveRange(0, 0x7FFFFFFF));
      expect(chatNotificationId('FFFFFFFFFF'), inInclusiveRange(0, 0x7FFFFFFF));
    });
  });

  group('ChatNotificationInbox', () {
    test('Should count every message and show the latest ones', () {
      final inbox = ChatNotificationInbox();
      final at = DateTime(2026, 9, 30);
      ({List<(String, DateTime)> shown, int count})? last;
      for (var i = 1; i <= ChatNotificationInbox.maxShown + 2; i++) {
        last = inbox.add('fp', 'm$i', at);
      }

      expect(last!.count, ChatNotificationInbox.maxShown + 2);
      expect(last.shown.length, ChatNotificationInbox.maxShown);
      expect(last.shown.first.$1, 'm3');
      expect(last.shown.last.$1, 'm${ChatNotificationInbox.maxShown + 2}');
    });

    test('Should keep conversations apart and start over once read', () {
      final inbox = ChatNotificationInbox();
      final at = DateTime(2026, 9, 30);
      inbox.add('alice', 'a', at);
      inbox.add('bob', 'b', at);

      inbox.clear('alice');

      expect(inbox.add('alice', 'again', at).count, 1);
      expect(inbox.add('bob', 'b2', at).count, 2);
    });
  });

  group('chatPreviewText', () {
    test('Should summarize each content type', () {
      expect(chatPreviewText(ChatContentType.text, text: 'hi'), 'hi');
      expect(chatPreviewText(ChatContentType.image), 'Photo');
      expect(chatPreviewText(ChatContentType.image, text: 'beach'), 'Photo · beach');
      expect(chatPreviewText(ChatContentType.document, attachmentFileName: 'cv.pdf'), 'cv.pdf');
      expect(chatPreviewText(ChatContentType.document), 'Document');
    });

    test('Should be translated', () async {
      await LocaleSettings.setLocale(AppLocale.fr);
      addTearDown(() => LocaleSettings.setLocaleSync(AppLocale.en));

      expect(chatPreviewText(ChatContentType.video), 'Vidéo');
    });
  });
}
