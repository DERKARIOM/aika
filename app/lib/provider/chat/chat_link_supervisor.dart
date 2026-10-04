import 'dart:async';
import 'dart:math';

import 'package:localsend_app/provider/chat/peer_link_manager.dart';

/// Keeps a chat link open with every contact that is on the network, so
/// messages flow both ways without waiting for someone to write first.
///
/// [setCandidates] says who to stay linked with (contacts discovered right
/// now, with their address). For each one without a ready link, a link is
/// opened; a failed attempt is retried after a growing, jittered delay
/// ([delayFor]): 2 s, 4 s, 8 s … up to [maxDelay] by default. A peer whose app has no
/// chat link (an older version) is asked again only after [legacyDelay].
///
/// Cheap when idle: one [Timer] per contact that is on the network but not
/// linked, and nothing at all once every link is up.
class ChatLinkSupervisor {
  final PeerLinkManager _links;

  /// Whether links to a peer are allowed at all (e.g. not blocked).
  final bool Function(String fingerprint) _isAllowed;
  final Duration baseDelay;
  final Duration maxDelay;
  final Duration legacyDelay;

  /// Random number in [0, 1), spreads the retries of several devices.
  final double Function() _random;

  final Map<String, PeerAddress> _candidates = {};
  final Map<String, int> _failures = {};
  final Map<String, Timer> _timers = {};
  final Set<String> _inFlight = {};
  bool _disposed = false;

  ChatLinkSupervisor({
    required PeerLinkManager links,
    required bool Function(String fingerprint) isAllowed,
    this.baseDelay = const Duration(seconds: 2),
    this.maxDelay = const Duration(seconds: 60),
    this.legacyDelay = const Duration(minutes: 10),
    double Function()? random,
  }) : _links = links,
       _isAllowed = isAllowed,
       _random = random ?? Random().nextDouble;

  /// Fingerprints currently supervised.
  Set<String> get candidates => _candidates.keys.toSet();

  /// Replaces the set of peers to stay linked with. Peers that left are
  /// forgotten (no more retries); new or unlinked ones are dialed now.
  void setCandidates(Iterable<PeerAddress> peers) {
    if (_disposed) {
      return;
    }
    final next = {for (final peer in peers) peer.fingerprint.toUpperCase(): peer};
    for (final fingerprint in _candidates.keys.where((fp) => !next.containsKey(fp)).toList()) {
      _forget(fingerprint);
    }
    _candidates
      ..clear()
      ..addAll(next);
    for (final fingerprint in next.keys) {
      if (!_timers.containsKey(fingerprint)) {
        unawaited(_attempt(fingerprint));
      }
    }
  }

  /// A peer lost its last link: if it is still on the network, try again
  /// shortly (it may just be restarting or switching networks).
  void onPeerGone(String fingerprint) {
    final fp = fingerprint.toUpperCase();
    if (_candidates.containsKey(fp)) {
      _schedule(fp, delayFor(_failures[fp] ?? 0));
    }
  }

  /// Retries every unlinked peer right away, e.g. when the app comes back
  /// to the foreground or the network changed.
  void retryNow() {
    for (final fingerprint in _candidates.keys) {
      _timers.remove(fingerprint)?.cancel();
      _failures.remove(fingerprint);
      unawaited(_attempt(fingerprint));
    }
  }

  void dispose() {
    _disposed = true;
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    _candidates.clear();
  }

  /// Delay before the next attempt after [failures] failed ones:
  /// [baseDelay] doubling up to [maxDelay], plus up to 20 % of jitter.
  Duration delayFor(int failures) {
    final base = baseDelay * pow(2, failures.clamp(0, 10));
    final capped = base > maxDelay ? maxDelay : base;
    return capped + capped * (0.2 * _random());
  }

  Future<void> _attempt(String fingerprint) async {
    final peer = _candidates[fingerprint];
    if (_disposed || peer == null || _inFlight.contains(fingerprint) || _links.isReady(fingerprint) || !_isAllowed(fingerprint)) {
      return;
    }

    _inFlight.add(fingerprint);
    final PeerLinkStatus status;
    try {
      status = await _links.ensureLink(peer);
    } finally {
      _inFlight.remove(fingerprint);
    }
    if (_disposed || !_candidates.containsKey(fingerprint)) {
      return;
    }

    switch (status) {
      case PeerLinkStatus.ready:
        _failures.remove(fingerprint);
      case PeerLinkStatus.legacy:
        _schedule(fingerprint, legacyDelay);
      case PeerLinkStatus.unreachable:
      case PeerLinkStatus.impostor:
        final failures = (_failures[fingerprint] ?? 0) + 1;
        _failures[fingerprint] = failures;
        _schedule(fingerprint, delayFor(failures));
    }
  }

  void _schedule(String fingerprint, Duration delay) {
    _timers[fingerprint]?.cancel();
    _timers[fingerprint] = Timer(delay, () {
      _timers.remove(fingerprint);
      unawaited(_attempt(fingerprint));
    });
  }

  void _forget(String fingerprint) {
    _timers.remove(fingerprint)?.cancel();
    _failures.remove(fingerprint);
  }
}
