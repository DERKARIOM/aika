import 'package:flutter/foundation.dart';
import 'package:localsend_app/config/update_config.dart';

/// Highest valid build number (Google Play's versionCode limit).
const int kMaxAppBuild = 2100000000;

/// Validates a build number. Builds received from another device are
/// untrusted: anything outside `1..kMaxAppBuild` is treated as unknown.
int? sanitizeAppBuild(int? build) {
  if (build == null || build < 1 || build > kMaxAppBuild) {
    return null;
  }
  return build;
}

/// Whether [peerBuild] is strictly newer than [localBuild].
///
/// Compares build numbers (versionCode, "18" in 1.1.4+18), never version
/// names. Unknown or invalid builds never count as newer, so a device
/// running an older Aika (which does not send its build) shows nothing.
bool isPeerBuildNewer({required int? localBuild, required int? peerBuild}) {
  final local = sanitizeAppBuild(localBuild);
  final peer = sanitizeAppBuild(peerBuild);
  return local != null && peer != null && peer > local;
}

/// A device met during a transfer that runs a newer Aika build.
class PeerUpdateHint {
  /// Stable identifier of the device (its fingerprint).
  final String peerId;
  final String peerAlias;
  final int peerBuild;
  final int localBuild;

  const PeerUpdateHint({
    required this.peerId,
    required this.peerAlias,
    required this.peerBuild,
    required this.localBuild,
  });

  /// Identifies a device/build pair: a hint is shown at most once per pair
  /// and per app session.
  String get key => '$peerId#$peerBuild';

  @override
  String toString() => 'PeerUpdateHint($peerAlias, build $peerBuild > $localBuild)';
}

/// Decides when the "update available" hint is shown.
///
/// The peer's build is recorded when a transfer starts ([remember]) and only
/// turned into a hint when that same transfer ends successfully
/// ([complete]). Failed, cancelled or never-finished transfers show nothing.
///
/// Pure Dart (no Flutter, no I/O) so it is unit tested and costs nothing
/// during the transfer itself.
class PeerUpdateTracker {
  /// This device's build, `null` when unknown (then nothing is ever shown).
  final int? localBuild;

  /// Bounds the transfers waiting for their end, so sessions that never
  /// complete (declined, interrupted...) cannot accumulate.
  final int maxPending;

  // Insertion ordered: the oldest pending transfer is evicted first.
  final Map<String, PeerUpdateHint> _pending = {};
  final Set<String> _shown = {};

  PeerUpdateTracker({required this.localBuild, this.maxPending = 16});

  /// Records the build of the device on the other end of transfer
  /// [sessionId]. Ignored unless that build is newer than ours.
  void remember(
    String sessionId, {
    required String peerId,
    required String peerAlias,
    required int? peerBuild,
  }) {
    final local = sanitizeAppBuild(localBuild);
    final peer = sanitizeAppBuild(peerBuild);
    if (local == null || peer == null || !isPeerBuildNewer(localBuild: local, peerBuild: peer)) {
      _pending.remove(sessionId);
      return;
    }

    _pending.remove(sessionId);
    while (_pending.length >= maxPending) {
      _pending.remove(_pending.keys.first);
    }
    _pending[sessionId] = PeerUpdateHint(
      peerId: peerId,
      peerAlias: peerAlias,
      peerBuild: peer,
      localBuild: local,
    );
  }

  /// Transfer [sessionId] ended. Returns the hint to show, or `null` when the
  /// transfer failed, the peer is not newer, or this device/build pair was
  /// already shown in this session.
  PeerUpdateHint? complete(String sessionId, {required bool success}) {
    final hint = _pending.remove(sessionId);
    if (hint == null || !success || !_shown.add(hint.key)) {
      return null;
    }
    return hint;
  }

  /// Transfer [sessionId] was cancelled or abandoned.
  void forget(String sessionId) => _pending.remove(sessionId);
}

/// The pages to try, in order, to update Aika on [platform]: its store page
/// (see [UpdateConfig.storeUrls]), then the website as a fallback.
List<Uri> updateDestinationsFor(TargetPlatform platform) {
  return {
    UpdateConfig.updatePageUrlFor(platform),
    UpdateConfig.websiteUrl,
  }.map(Uri.parse).toList();
}

/// Opens an external page (a store app or the browser). Returns `false`
/// when nothing could handle it.
typedef UrlOpener = Future<bool> Function(Uri uri);

/// Opens the update page for [platform] with [open], falling back to the
/// website when the store cannot be opened (no Play Store app, no browser
/// for that link...). Never throws; returns `false` when nothing opened.
Future<bool> launchUpdatePage(TargetPlatform platform, UrlOpener open) async {
  for (final uri in updateDestinationsFor(platform)) {
    try {
      if (await open(uri)) {
        return true;
      }
    } catch (_) {
      // Try the next destination.
    }
  }
  return false;
}
