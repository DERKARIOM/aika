import 'package:flutter/foundation.dart';
import 'package:localsend_app/config/update_config.dart';
import 'package:localsend_app/model/update/peer_update.dart';
import 'package:localsend_app/model/update/update_policy.dart';
import 'package:test/test.dart';

void main() {
  group('isPeerBuildNewer', () {
    test('local 18 / remote 18 -> nothing', () {
      expect(isPeerBuildNewer(localBuild: 18, peerBuild: 18), isFalse);
    });

    test('local 18 / remote 20 -> update available', () {
      expect(isPeerBuildNewer(localBuild: 18, peerBuild: 20), isTrue);
    });

    test('local 20 / remote 18 -> nothing', () {
      expect(isPeerBuildNewer(localBuild: 20, peerBuild: 18), isFalse);
    });

    test('compares build numbers, not version names', () {
      // 1.1.4+18 vs 1.1.5+20: only the "+N" part matters.
      expect(isPeerBuildNewer(localBuild: parseVersionCode('18'), peerBuild: parseVersionCode('20')), isTrue);
      expect(parseVersionCode('1.1.5'), isNull);
    });

    test('missing or invalid builds never count as newer', () {
      expect(isPeerBuildNewer(localBuild: 18, peerBuild: null), isFalse);
      expect(isPeerBuildNewer(localBuild: null, peerBuild: 20), isFalse);
      expect(isPeerBuildNewer(localBuild: 18, peerBuild: 0), isFalse);
      expect(isPeerBuildNewer(localBuild: 18, peerBuild: -5), isFalse);
      expect(isPeerBuildNewer(localBuild: 18, peerBuild: kMaxAppBuild + 1), isFalse);
    });
  });

  group('PeerUpdateTracker', () {
    PeerUpdateTracker tracker({int? local = 18}) => PeerUpdateTracker(localBuild: local);

    void remember(PeerUpdateTracker t, String session, {String peer = 'A', int? build = 20}) {
      t.remember(session, peerId: peer, peerAlias: 'Peer $peer', peerBuild: build);
    }

    test('successful transfer + newer remote -> hint', () {
      final t = tracker();
      remember(t, 's1');
      final hint = t.complete('s1', success: true);
      expect(hint, isNotNull);
      expect(hint!.peerBuild, 20);
      expect(hint.localBuild, 18);
    });

    test('failed transfer + newer remote -> no hint', () {
      final t = tracker();
      remember(t, 's1');
      expect(t.complete('s1', success: false), isNull);
    });

    test('cancelled transfer -> no hint', () {
      final t = tracker();
      remember(t, 's1');
      t.forget('s1');
      expect(t.complete('s1', success: true), isNull);
    });

    test('same or older remote -> no hint', () {
      final t = tracker();
      remember(t, 's1', build: 18);
      remember(t, 's2', build: 12);
      expect(t.complete('s1', success: true), isNull);
      expect(t.complete('s2', success: true), isNull);
    });

    test('old Aika without build / invalid build -> no hint, no crash', () {
      final t = tracker();
      remember(t, 's1', build: null);
      remember(t, 's2', build: -1);
      expect(t.complete('s1', success: true), isNull);
      expect(t.complete('s2', success: true), isNull);
      expect(t.complete('unknown', success: true), isNull);
    });

    test('unknown local build -> never a hint', () {
      final t = tracker(local: null);
      remember(t, 's1');
      expect(t.complete('s1', success: true), isNull);
    });

    test('shown once per device/build in a session', () {
      final t = tracker();
      remember(t, 's1');
      expect(t.complete('s1', success: true), isNotNull);
      remember(t, 's2');
      expect(t.complete('s2', success: true), isNull, reason: 'same device, same build');
      remember(t, 's3', build: 21);
      expect(t.complete('s3', success: true), isNotNull, reason: 'same device, newer build');
      remember(t, 's4', peer: 'B');
      expect(t.complete('s4', success: true), isNotNull, reason: 'another device');
    });

    test('a failed attempt does not consume the hint', () {
      final t = tracker();
      remember(t, 's1');
      expect(t.complete('s1', success: false), isNull);
      remember(t, 's2');
      expect(t.complete('s2', success: true), isNotNull);
    });

    test('concurrent transfers with several devices are kept apart', () {
      final t = tracker();
      remember(t, 's1', peer: 'A', build: 20);
      remember(t, 's2', peer: 'B', build: 17);
      expect(t.complete('s2', success: true), isNull);
      expect(t.complete('s1', success: true)?.peerId, 'A');
    });

    test('pending transfers are bounded', () {
      final t = PeerUpdateTracker(localBuild: 18, maxPending: 2);
      remember(t, 's1', peer: 'A');
      remember(t, 's2', peer: 'B');
      remember(t, 's3', peer: 'C');
      expect(t.complete('s1', success: true), isNull, reason: 'evicted');
      expect(t.complete('s3', success: true), isNotNull);
    });
  });

  group('update destination', () {
    test('Android -> Google Play first, website as fallback', () {
      expect(updateDestinationsFor(TargetPlatform.android), [
        Uri.parse('https://play.google.com/store/apps/details?id=com.naniger.aika'),
        Uri.parse('https://naniger.com/'),
      ]);
    });

    test('desktop and other platforms -> naniger.com', () {
      for (final platform in [TargetPlatform.windows, TargetPlatform.macOS, TargetPlatform.linux, TargetPlatform.iOS]) {
        expect(updateDestinationsFor(platform), [Uri.parse(UpdateConfig.websiteUrl)], reason: '$platform');
      }
    });

    test('falls back to the website when the store cannot be opened', () async {
      final tried = <Uri>[];
      final opened = await launchUpdatePage(TargetPlatform.android, (uri) async {
        tried.add(uri);
        if (uri.host == 'play.google.com') {
          throw Exception('No activity found');
        }
        return true;
      });
      expect(opened, isTrue);
      expect(tried.map((u) => u.host), ['play.google.com', 'naniger.com']);
    });

    test('reports failure when nothing can be opened (offline, no browser)', () async {
      expect(await launchUpdatePage(TargetPlatform.linux, (_) async => false), isFalse);
    });
  });
}
