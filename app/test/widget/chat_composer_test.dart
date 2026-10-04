import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/widget/chat/chat_composer.dart';

void main() {
  setUpAll(() {
    LocaleSettings.setLocaleSync(AppLocale.en);
  });

  late TextEditingController controller;
  late List<String> sent;

  Future<void> pump(WidgetTester tester) async {
    controller = TextEditingController();
    sent = [];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatComposer(
            controller: controller,
            blocked: false,
            onChanged: (_) {},
            onSend: sent.add,
            onAttach: () {},
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'Salut');
  }

  testWidgets('Should send with Enter on desktop', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await pump(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(sent, ['Salut']);
    expect(controller.text, isEmpty);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Should not send with Shift+Enter on desktop', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await pump(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();

    expect(sent, isEmpty);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Should send with the button, never a blank text', (tester) async {
    await pump(tester);

    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();
    expect(sent, ['Salut']);

    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();
    expect(sent, ['Salut']);
  });
}
