import 'dart:async';

import 'package:localsend_app/model/chat/chat_frame.dart';
import 'package:localsend_isolates/isolate.dart';
import 'package:logging/logging.dart';

final _logger = Logger('PeerLink');

/// The raw chat connection layer (the Rust chat hub in production).
abstract class ChatLinkTransport {
  /// Connection events for the lifetime of the app. Called once.
  Stream<ChatLinkEvent> start();

  Future<ChatLinkResultEvent> connect({required String ip, required int port, required String fingerprint});

  Future<ChatLinkResultEvent> send({required String connectionId, required String text});

  void close(String connectionId);
}

/// Outcome of [PeerLinkManager.ensureLink].
enum PeerLinkStatus {
  /// A link is ready: frames can be sent with [PeerLinkManager.send].
  ready,

  /// The peer has no chat WebSocket (e.g. v1.0.3): use the legacy
  /// file-transfer envelope.
  legacy,

  /// The device answering at that address is *not* the expected peer
  /// (certificate fingerprint mismatch). Nothing must be sent to it, over
  /// any transport.
  impostor,

  /// Not reachable right now (offline, timeout, too many connections).
  unreachable,
}

/// Where to reach a peer.
class PeerAddress {
  final String fingerprint;
  final String ip;
  final int port;

  const PeerAddress({required this.fingerprint, required this.ip, required this.port});
}

class _Link {
  final String connectionId;
  final String fingerprint;
  final String ip;
  final bool outbound;
  ChatHelloFrame? peerHello;
  int? version;
  Timer? helloTimeout;

  _Link({required this.connectionId, required this.fingerprint, required this.ip, required this.outbound});

  bool get ready => version != null;
}

/// Keeps at most one ready chat link per peer on top of a [ChatLinkTransport]:
/// runs the hello handshake, resolves duplicate connections, remembers which
/// peers only speak the legacy transport, and routes incoming frames.
///
/// Fingerprints are compared in uppercase, the format of the Rust side.
class PeerLinkManager {
  final ChatLinkTransport _transport;
  final String _ownFingerprint;
  final ChatHelloFrame Function() _hello;
  final bool Function(String fingerprint) _isBlocked;
  final Duration _helloTimeout;
  final Duration _legacyRetryAfter;
  final DateTime Function() _now;

  /// A frame (other than hello) received from a peer on its active link.
  void Function(String fingerprint, ChatFrame frame)? onFrame;

  /// A peer got its first ready link (it is online and speaks [version]).
  void Function(String fingerprint, int version, ChatHelloFrame hello, String ip)? onPeerReady;

  /// A peer lost its last ready link.
  void Function(String fingerprint)? onPeerGone;

  final Map<String, _Link> _links = {};

  /// fingerprint -> connection ID of the ready link frames are sent on.
  final Map<String, String> _active = {};
  final Map<String, DateTime> _legacyUntil = {};
  final Map<String, Future<PeerLinkStatus>> _connecting = {};
  final Map<String, List<Completer<void>>> _readyWaiters = {};
  StreamSubscription<ChatLinkEvent>? _subscription;

  PeerLinkManager({
    required ChatLinkTransport transport,
    required String ownFingerprint,
    required ChatHelloFrame Function() hello,
    required bool Function(String fingerprint) isBlocked,
    Duration helloTimeout = const Duration(seconds: 5),
    Duration legacyRetryAfter = const Duration(minutes: 10),
    DateTime Function()? now,
  }) : _transport = transport,
       _ownFingerprint = ownFingerprint.toUpperCase(),
       _hello = hello,
       _isBlocked = isBlocked,
       _helloTimeout = helloTimeout,
       _legacyRetryAfter = legacyRetryAfter,
       _now = now ?? DateTime.now;

  /// Peers with a ready link, i.e. online right now.
  Set<String> get readyPeers => _active.keys.toSet();

  bool isReady(String fingerprint) => _active.containsKey(fingerprint.toUpperCase());

  /// Negotiated protocol version with a peer, if it is connected.
  int? versionOf(String fingerprint) {
    final id = _active[fingerprint.toUpperCase()];
    return id == null ? null : _links[id]?.version;
  }

  void start() {
    _subscription ??= _transport.start().listen(_onEvent, onError: (Object e) => _logger.warning('Chat hub error: $e'));
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    for (final link in _links.values) {
      link.helloTimeout?.cancel();
    }
  }

  /// Returns a ready link to [peer], connecting if needed. Concurrent calls
  /// for the same peer share one attempt.
  Future<PeerLinkStatus> ensureLink(PeerAddress peer) async {
    final fingerprint = peer.fingerprint.toUpperCase();
    if (_active.containsKey(fingerprint)) {
      return PeerLinkStatus.ready;
    }
    final legacyUntil = _legacyUntil[fingerprint];
    if (legacyUntil != null && _now().isBefore(legacyUntil)) {
      return PeerLinkStatus.legacy;
    }
    final pending = _connecting[fingerprint];
    if (pending != null) {
      return pending;
    }
    final attempt = _connect(fingerprint, peer);
    _connecting[fingerprint] = attempt;
    try {
      return await attempt;
    } finally {
      // Discards the returned future on purpose: it is `attempt` itself.
      unawaited(_connecting.remove(fingerprint));
    }
  }

  Future<PeerLinkStatus> _connect(String fingerprint, PeerAddress peer) async {
    // Registered before connecting: the hello may complete before connect()
    // itself returns.
    final ready = _waitReady(fingerprint);
    final result = await _transport.connect(ip: peer.ip, port: peer.port, fingerprint: fingerprint);
    final error = result.error;
    if (error != null) {
      _cancelWaiter(fingerprint, ready);
      switch (error.kind) {
        case ChatLinkErrorKind.unsupported:
          _markLegacy(fingerprint);
          return PeerLinkStatus.legacy;
        case ChatLinkErrorKind.fingerprintMismatch:
          _logger.warning('Device at ${peer.ip}:${peer.port} is not $fingerprint (certificate mismatch)');
          return PeerLinkStatus.impostor;
        default:
          _logger.fine('Chat link to ${peer.ip}:${peer.port} failed: $error');
          return PeerLinkStatus.unreachable;
      }
    }

    try {
      await ready.future.timeout(_helloTimeout);
    } on TimeoutException {
      _cancelWaiter(fingerprint, ready);
    }
    if (_active.containsKey(fingerprint)) {
      return PeerLinkStatus.ready;
    }
    // Connected but no compatible hello: treat like an old peer.
    if (_legacyUntil.containsKey(fingerprint)) {
      return PeerLinkStatus.legacy;
    }
    return PeerLinkStatus.unreachable;
  }

  /// Sends [frame] on the active link of [fingerprint].
  /// Returns `false` if there is none or it just closed.
  Future<bool> send(String fingerprint, ChatFrame frame) async {
    final id = _active[fingerprint.toUpperCase()];
    if (id == null) {
      return false;
    }
    final result = await _transport.send(connectionId: id, text: frame.encode());
    return result.error == null;
  }

  /// Closes every link to [fingerprint] (e.g. the user blocked it).
  void disconnect(String fingerprint) {
    final fp = fingerprint.toUpperCase();
    for (final link in _links.values.where((l) => l.fingerprint == fp).toList()) {
      _transport.close(link.connectionId);
    }
  }

  void _onEvent(ChatLinkEvent event) {
    switch (event) {
      case ChatLinkConnectedEvent():
        _onConnected(event);
      case ChatLinkMessageEvent():
        _onMessage(event);
      case ChatLinkDisconnectedEvent():
        _onDisconnected(event);
    }
  }

  void _onConnected(ChatLinkConnectedEvent event) {
    final fingerprint = event.fingerprint.toUpperCase();
    if (_isBlocked(fingerprint) || fingerprint == _ownFingerprint) {
      _transport.close(event.connectionId);
      return;
    }
    final link = _Link(connectionId: event.connectionId, fingerprint: fingerprint, ip: event.ip, outbound: event.outbound);
    _links[event.connectionId] = link;
    link.helloTimeout = Timer(_helloTimeout, () {
      if (!link.ready) {
        _logger.fine('No hello from $fingerprint, closing ${link.connectionId}');
        _transport.close(link.connectionId);
      }
    });
    unawaited(_transport.send(connectionId: event.connectionId, text: _hello().encode()));
  }

  void _onMessage(ChatLinkMessageEvent event) {
    final link = _links[event.connectionId];
    if (link == null) {
      return;
    }
    final frame = ChatFrame.tryDecode(event.text);
    if (frame == null) {
      _logger.fine('Ignoring unknown or malformed chat frame from ${link.fingerprint}');
      return;
    }

    if (!link.ready) {
      if (frame is ChatHelloFrame) {
        _onHello(link, frame);
      }
      // Anything before the hello is dropped.
      return;
    }

    // A repeated hello is ignored. Frames are delivered even on a duplicate
    // link about to be closed: messages are deduplicated by id anyway.
    if (frame is! ChatHelloFrame) {
      onFrame?.call(link.fingerprint, frame);
    }
  }

  void _onHello(_Link link, ChatHelloFrame hello) {
    link.helloTimeout?.cancel();
    final version = hello.negotiate(_hello());
    if (version == null) {
      _logger.info('Chat protocol of ${link.fingerprint} (v${hello.minVersion}-${hello.version}) is incompatible');
      _markLegacy(link.fingerprint);
      _transport.close(link.connectionId);
      return;
    }
    link
      ..peerHello = hello
      ..version = version;
    _legacyUntil.remove(link.fingerprint);

    final currentId = _active[link.fingerprint];
    final current = currentId == null ? null : _links[currentId];
    if (current == null) {
      _active[link.fingerprint] = link.connectionId;
      onPeerReady?.call(link.fingerprint, version, hello, link.ip);
      _completeWaiters(link.fingerprint);
      return;
    }

    // Two links to the same peer (both sides dialed at once): both devices
    // must keep the same one. When they differ in direction, the link
    // opened by the device with the smaller fingerprint wins; otherwise the
    // existing one stays.
    final keepNew = link.outbound != current.outbound && link.outbound == (_ownFingerprint.compareTo(link.fingerprint) < 0);
    if (keepNew) {
      _active[link.fingerprint] = link.connectionId;
      _transport.close(current.connectionId);
    } else {
      _transport.close(link.connectionId);
    }
  }

  void _onDisconnected(ChatLinkDisconnectedEvent event) {
    final link = _links.remove(event.connectionId);
    if (link == null) {
      return;
    }
    link.helloTimeout?.cancel();
    if (_active[link.fingerprint] != link.connectionId) {
      return;
    }
    _active.remove(link.fingerprint);
    final replacement = _links.values.firstWhereOrNullReady(link.fingerprint);
    if (replacement != null) {
      _active[link.fingerprint] = replacement.connectionId;
    } else {
      onPeerGone?.call(link.fingerprint);
    }
  }

  void _markLegacy(String fingerprint) {
    _legacyUntil[fingerprint] = _now().add(_legacyRetryAfter);
  }

  Completer<void> _waitReady(String fingerprint) {
    final completer = Completer<void>();
    (_readyWaiters[fingerprint] ??= []).add(completer);
    return completer;
  }

  void _cancelWaiter(String fingerprint, Completer<void> completer) {
    _readyWaiters[fingerprint]?.remove(completer);
  }

  void _completeWaiters(String fingerprint) {
    for (final waiter in _readyWaiters.remove(fingerprint) ?? const <Completer<void>>[]) {
      if (!waiter.isCompleted) {
        waiter.complete();
      }
    }
  }
}

extension on Iterable<_Link> {
  _Link? firstWhereOrNullReady(String fingerprint) {
    for (final link in this) {
      if (link.fingerprint == fingerprint && link.ready) {
        return link;
      }
    }
    return null;
  }
}
