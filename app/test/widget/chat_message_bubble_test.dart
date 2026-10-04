import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/chat/chat_database.dart';
import 'package:localsend_app/provider/chat/chat_attachment_progress.dart';
import 'package:localsend_app/widget/chat/chat_message_bubble.dart';
import 'package:refena_flutter/refena_flutter.dart';

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
    final delivered = tester.widget<Icon>(find.byIcon(Icons.done_all_rounded));

    await _pump(tester, _message(status: ChatMessageStatusColumn.read));
    final read = tester.widget<Icon>(find.byIcon(Icons.done_all_rounded));

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
    await tester.tap(find.textContaining('Bonjour'));
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

    await tester.longPress(find.textContaining('Bonjour'));
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

    await tester.longPress(find.textContaining('Bonjour'));
    await tester.pumpAndSettle();

    expect(find.text(t.chat.copy), findsOneWidget);
    expect(find.text(t.chat.retry), findsNothing);
  });

  testWidgets('Should show the transfer progress of an attachment, then its icon', (tester) async {
    final container = RefenaContainer();
    final progress = container.read(chatAttachmentProgressProvider);
    final message = ChatMessage(
      id: 'f1',
      conversationId: 'fp',
      direction: ChatMessageDirectionColumn.outgoing,
      contentType: 'file',
      body: '',
      status: ChatMessageStatusColumn.pending,
      attachmentFileName: 'rapport.pdf',
      attachmentSize: 1000,
      attachmentPath: '/tmp/rapport.pdf',
      createdAt: DateTime.utc(2026, 10, 4, 12),
    );
    await tester.pumpWidget(
      RefenaScope.withContainer(
        container: container,
        child: MaterialApp(
          home: Scaffold(body: ChatMessageBubble(message: message)),
        ),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);

    progress.set('f1', 0.42);
    await tester.pump();
    final ring = tester.widget<CircularProgressIndicator>(find.byType(CircularProgressIndicator));
    expect(ring.value, 0.42);
    expect(find.textContaining('42 %'), findsOneWidget);

    progress.done('f1');
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.insert_drive_file_outlined), findsOneWidget);
  });

  testWidgets('Should cancel a running upload from its ring, never an incoming one', (tester) async {
    final container = RefenaContainer();
    final progress = container.read(chatAttachmentProgressProvider);
    var cancels = 0;
    ChatMessage file(ChatMessageDirectionColumn direction) => ChatMessage(
      id: 'f2',
      conversationId: 'fp',
      direction: direction,
      contentType: 'file',
      body: '',
      status: ChatMessageStatusColumn.pending,
      attachmentFileName: 'video.mp4',
      attachmentSize: 1000,
      attachmentPath: '/tmp/video.mp4',
      createdAt: DateTime.utc(2026, 10, 4, 12),
    );
    Future<void> pump(ChatMessageDirectionColumn direction) => tester.pumpWidget(
      RefenaScope.withContainer(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: ChatMessageBubble(message: file(direction), onCancelTransfer: () => cancels++),
          ),
        ),
      ),
    );

    await pump(ChatMessageDirectionColumn.outgoing);
    expect(find.byIcon(Icons.close_rounded), findsNothing);

    progress.set('f2', 0.3);
    await tester.pump();
    await tester.tap(find.byIcon(Icons.close_rounded));
    expect(cancels, 1);

    await pump(ChatMessageDirectionColumn.incoming);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsNothing);
  });
}
