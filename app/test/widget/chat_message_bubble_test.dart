import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/chat/chat_database.dart';
import 'package:localsend_app/widget/chat/chat_message_bubble.dart';

ChatMessage _message({
  ChatMessageDirectionColumn direction = ChatMessageDirectionColumn.outgoing,
  ChatMessageStatusColumn status = ChatMessageStatusColumn.sent,
  String? error,
}) {
  return ChatMessage(
    id: 'm1',
    conversationId: 'fp',
    direction: direction,
    contentType: 'text',
    body: 'Bonjour',
    status: status,
    errorMessage: error,
    createdAt: DateTime.utc(2026, 9, 30, 12),
  );
}

Future<void> _pump(WidgetTester tester, ChatMessage message, {VoidCallback? onRetry}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ChatMessageBubble(message: message, onRetry: onRetry),
      ),
    ),
  );
}

void main() {
  setUpAll(() {
    LocaleSettings.setLocaleSync(AppLocale.en);
  });

  testWidgets('Should tell read from delivered', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, _message(status: ChatMessageStatusColumn.delivered));
    final delivered = tester.widget<Icon>(find.byIcon(Icons.done_all));

    await _pump(tester, _message(status: ChatMessageStatusColumn.read));
    final read = tester.widget<Icon>(find.byIcon(Icons.done_all));

    expect(read.color, isNot(delivered.color));
    // Merged with the text and time into one node, read out as a whole.
    expect(tester.getSemantics(find.byType(ChatMessageBubble)).label, contains('Read'));
    semantics.dispose();
  });

  testWidgets('Should offer a retry for a message that could not be sent', (tester) async {
    var retries = 0;
    await _pump(
      tester,
      _message(status: ChatMessageStatusColumn.pending, error: 'Peer busy'),
      onRetry: () => retries++,
    );

    expect(find.text(t.chat.notSentTapToRetry), findsOneWidget);
    await tester.tap(find.text('Bonjour'));
    expect(retries, 1);
  });

  testWidgets('Should not show an error for a message simply waiting', (tester) async {
    await _pump(tester, _message(status: ChatMessageStatusColumn.pending), onRetry: () {});

    expect(find.text(t.chat.notSentTapToRetry), findsNothing);
  });

  testWidgets('Should show the cause and actions on long press', (tester) async {
    await _pump(
      tester,
      _message(status: ChatMessageStatusColumn.failed, error: 'Refused by the recipient.'),
      onRetry: () {},
    );

    await tester.longPress(find.text('Bonjour'));
    await tester.pumpAndSettle();

    expect(find.text('Refused by the recipient.'), findsOneWidget);
    expect(find.text(t.chat.copy), findsOneWidget);
    expect(find.text(t.chat.retry), findsOneWidget);
  });

  testWidgets('Should not offer retry for incoming messages', (tester) async {
    await _pump(
      tester,
      _message(direction: ChatMessageDirectionColumn.incoming, status: ChatMessageStatusColumn.delivered),
      onRetry: () {},
    );

    await tester.longPress(find.text('Bonjour'));
    await tester.pumpAndSettle();

    expect(find.text(t.chat.copy), findsOneWidget);
    expect(find.text(t.chat.retry), findsNothing);
  });
}
