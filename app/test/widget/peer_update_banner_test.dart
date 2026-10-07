import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/config/theme.dart';
import 'package:localsend_app/provider/peer_update_provider.dart';
import 'package:localsend_app/widget/peer_update_banner.dart';
import 'package:refena_flutter/refena_flutter.dart';

void main() {
  late List<Uri> opened;
  late bool openSucceeds;
  late PeerUpdateNotifier notifier;

  setUp(() {
    opened = [];
    openSucceeds = true;
    notifier = PeerUpdateNotifier(
      localBuild: 18,
      open: (uri) async {
        opened.add(uri);
        return openSucceeds;
      },
    );
  });

  Future<void> pump(WidgetTester tester, {Brightness brightness = Brightness.light, double width = 800}) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      RefenaScope(
        overrides: [peerUpdateProvider.overrideWithNotifier((ref) => notifier)],
        child: MaterialApp(
          theme: ThemeData(colorSchemeSeed: seedColor, brightness: brightness),
          home: const Scaffold(
            body: PeerUpdateBannerHost(child: Center(child: Text('content'))),
          ),
        ),
      ),
    );
  }

  /// Simulates a successful transfer with a device on build [peerBuild].
  Future<void> transfer(WidgetTester tester, {int? peerBuild = 20, bool success = true, String session = 's1'}) async {
    notifier.rememberPeer(session, peerId: 'peer', peerAlias: 'Peer', peerBuild: peerBuild);
    notifier.onTransferEnded(session, success: success);
    await tester.pumpAndSettle();
  }

  testWidgets('hidden until a successful transfer with a newer device', (tester) async {
    await pump(tester);
    expect(find.byType(PeerUpdateBanner), findsNothing);
    expect(find.text('content'), findsOneWidget);

    await transfer(tester, success: false);
    expect(find.byType(PeerUpdateBanner), findsNothing);

    await transfer(tester, peerBuild: 18, session: 's2');
    expect(find.byType(PeerUpdateBanner), findsNothing);

    await transfer(tester, peerBuild: null, session: 's3');
    expect(find.byType(PeerUpdateBanner), findsNothing);

    await transfer(tester, session: 's4');
    expect(find.byType(PeerUpdateBanner), findsOneWidget);
    expect(find.text('content'), findsOneWidget);
  });

  for (final brightness in Brightness.values) {
    testWidgets('renders without overflow in $brightness theme, wide and narrow', (tester) async {
      await pump(tester, brightness: brightness);
      for (final width in [800.0, 320.0]) {
        tester.view.physicalSize = Size(width, 900);
        await transfer(tester, session: 'w$width', peerBuild: width.toInt());
        expect(find.byType(PeerUpdateBanner), findsOneWidget);
        expect(tester.takeException(), isNull);
        notifier.dismiss();
        await tester.pumpAndSettle();
        expect(find.byType(PeerUpdateBanner), findsNothing);
      }
    });
  }

  testWidgets('tap opens Google Play on Android', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await pump(tester);
      await transfer(tester);
      await tester.tap(find.byType(PeerUpdateBanner));
      await tester.pumpAndSettle();
      expect(opened, [Uri.parse('https://play.google.com/store/apps/details?id=com.naniger.aika')]);
      expect(find.byType(PeerUpdateBanner), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('tap opens naniger.com on desktop', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await pump(tester);
      await transfer(tester);
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(opened, [Uri.parse('https://naniger.com/')]);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('stays visible with a message when nothing can be opened', (tester) async {
    openSucceeds = false;
    await pump(tester);
    await transfer(tester);
    await tester.tap(find.byType(PeerUpdateBanner));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.byType(PeerUpdateBanner), findsOneWidget);
  });

  testWidgets('can be closed and is not shown again for the same device/build', (tester) async {
    await pump(tester);
    await transfer(tester);
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(find.byType(PeerUpdateBanner), findsNothing);

    await transfer(tester, session: 's2');
    expect(find.byType(PeerUpdateBanner), findsNothing);
  });
}
