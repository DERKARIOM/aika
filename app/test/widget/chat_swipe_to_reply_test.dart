import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/widget/chat/chat_swipe_to_reply.dart';

void main() {
  late int replies;

  Future<void> pump(WidgetTester tester) {
    replies = 0;
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatSwipeToReply(
            onReply: () => replies++,
            child: const SizedBox(width: 200, height: 40, child: Text('bulle')),
          ),
        ),
      ),
    );
  }

  testWidgets('Should reply when swiped far enough to the right', (tester) async {
    await pump(tester);

    await tester.drag(find.text('bulle'), const Offset(90, 0));
    await tester.pumpAndSettle();

    expect(replies, 1);
  });

  testWidgets('Should not reply on a short swipe nor a swipe to the left', (tester) async {
    await pump(tester);

    await tester.drag(find.text('bulle'), const Offset(30, 0));
    await tester.drag(find.text('bulle'), const Offset(-90, 0));
    await tester.pumpAndSettle();

    expect(replies, 0);
  });
}
