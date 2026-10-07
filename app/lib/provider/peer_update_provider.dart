import 'package:flutter/foundation.dart';
import 'package:localsend_app/model/update/peer_update.dart';
import 'package:localsend_app/provider/device_info_provider.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// The "a newer Aika is available" hint learned from the device on the other
/// end of a successful transfer. `null` while there is nothing to show.
///
/// Senders learn the receiver's build from the `prepare-upload` response,
/// receivers learn the sender's from its request (optional `appBuild`
/// field, absent on older versions). Informational only: it never affects
/// the transfer.
final peerUpdateProvider = NotifierProvider<PeerUpdateNotifier, PeerUpdateHint?>((ref) {
  return PeerUpdateNotifier(localBuild: ref.read(deviceRawInfoProvider).appBuild);
});

class PeerUpdateNotifier extends Notifier<PeerUpdateHint?> {
  final PeerUpdateTracker _tracker;
  final UrlOpener _open;

  PeerUpdateNotifier({required int? localBuild, UrlOpener? open})
    : _tracker = PeerUpdateTracker(localBuild: localBuild),
      _open = open ?? _launchExternal;

  @override
  PeerUpdateHint? init() => null;

  /// A transfer with [peerId] starts: records its (untrusted) build.
  void rememberPeer(
    String sessionId, {
    required String peerId,
    required String peerAlias,
    required int? peerBuild,
  }) {
    _tracker.remember(sessionId, peerId: peerId, peerAlias: peerAlias, peerBuild: peerBuild);
  }

  /// A transfer ended: shows the hint if it succeeded with a newer device.
  void onTransferEnded(String sessionId, {required bool success}) {
    final hint = _tracker.complete(sessionId, success: success);
    if (hint != null) {
      state = hint;
    }
  }

  /// A transfer was cancelled before its end.
  void onTransferCancelled(String sessionId) => _tracker.forget(sessionId);

  /// Hides the banner (it is not shown again for the same device/build).
  void dismiss() => state = null;

  /// Opens the store or website for this platform. Returns `false` when
  /// nothing could be opened; the banner then stays visible.
  Future<bool> openUpdatePage({TargetPlatform? platform}) async {
    final opened = await launchUpdatePage(platform ?? defaultTargetPlatform, _open);
    if (opened) {
      state = null;
    }
    return opened;
  }
}

Future<bool> _launchExternal(Uri uri) => launchUrl(uri, mode: LaunchMode.externalApplication);
