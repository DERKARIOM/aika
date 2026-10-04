import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/provider/chat/chat_attachment_progress.dart';
import 'package:localsend_app/widget/chat/chat_message_bubble.dart';

void main() {
  group('ChatAttachmentProgress', () {
    late DateTime now;
    late ChatAttachmentProgress progress;
    late List<double?> seen;

    setUp(() {
      now = DateTime.utc(2026, 10, 4, 12);
      progress = ChatAttachmentProgress(clock: () => now);
      seen = [];
      progress.of('m').addListener(() => seen.add(progress.of('m').value));
    });

    test('Should repaint on 1 % steps, not on every chunk', () {
      progress.set('m', 0.001);
      progress.set('m', 0.005);
      progress.set('m', 0.012);
      expect(seen, [0.001, 0.012]);
    });

    test('Should still repaint every half second for slow progress', () {
      progress.set('m', 0.1);
      now = now.add(const Duration(milliseconds: 600));
      progress.set('m', 0.101);
      expect(seen, [0.1, 0.101]);
    });

    test('Should measure the elapsed time until done', () {
      expect(progress.elapsed('m'), isNull);
      progress.set('m', 0.2);
      now = now.add(const Duration(seconds: 3));
      expect(progress.elapsed('m'), const Duration(seconds: 3));

      progress.done('m');
      expect(progress.elapsed('m'), isNull);
      expect(progress.of('m').value, isNull);
    });
  });

  group('chatTransferLabel', () {
    const mb = 1024 * 1024;

    test('Should show the percentage during the first second', () {
      expect(chatTransferLabel(size: 100 * mb, progress: 0.3, elapsed: Duration.zero), '30.0 MB / 100.0 MB · 30 %');
    });

    test('Should show speed and remaining time afterwards', () {
      // 30 MB in 10 s: 3 MB/s, 70 MB left: 24 s.
      expect(
        chatTransferLabel(size: 100 * mb, progress: 0.3, elapsed: const Duration(seconds: 10)),
        '30.0 MB / 100.0 MB · 3.0 MB/s · 24 s',
      );
    });

    test('Should show hours for very large files', () {
      // 100 GB at 10 MB/s.
      const gb = 1024 * mb;
      final label = chatTransferLabel(size: 100 * gb, progress: 0.01, elapsed: const Duration(seconds: 1024 ~/ 10));
      expect(label, endsWith('· 2 h 48'));
    });
  });
}
