import 'dart:async';

import 'package:localsend_app/model/chat/chat_envelope.dart';
import 'package:localsend_app/model/chat/chat_frame.dart';
import 'package:localsend_app/provider/chat/peer_link_manager.dart';
import 'package:localsend_isolates/isolate.dart';
import 'package:test/test.dart';

const _me = 'BBBB';
const _peer = 'CCCC';
const _peerAddress = PeerAddress(fingerprint: _peer, ip: '192.168.1.20', port: 53317);
const _myHello = ChatHelloFrame(version: chatWsProtocolVersion, minVersion: chatWsMinProtocolVersion, alias: 'Me');
const _peerHello = ChatHelloFrame(version: chatWsProtocolVersion, minVersion: chatWsMinProtocolVersion, alias: 'Peer');

class _FakeTransport implements ChatLinkTransport {
  final events = StreamController<ChatLinkEvent>();
  final sent = <(String, String)>[];
  final closed = <String>[];
  int connects = 0;
  int _nextId = 0;

  /// What the next connect() does; by default the peer answers its hello.
  FutureOr<ChatLinkResultEvent> Function()? onConnect;

  @override
  Stream<ChatLinkEvent> start() => events.stream;

  @override
  Future<ChatLinkResultEvent> connect({required String ip, required int port, required String fingerprint}) async {
    connects++;
    return await (onConnect ?? () => ChatLinkResultEvent(connectionId: open(fingerprint, outbound: true, answerHello: true)))();
  }

  @override
  Future<ChatLinkResultEvent> send({required String connectionId, required String text}) async {
    if (closed.contains(connectionId)) {
      return ChatLinkResultEvent(error: const ChatLinkError(ChatLinkErrorKind.notConnected));
    }
    sent.add((connectionId, text));
    return ChatLinkResultEvent();
  }

  @override
  void close(String connectionId) {
    closed.add(connectionId);
    events.add(ChatLinkDisconnectedEvent(connectionId: connectionId, reason: 'closed locally'));
  }

  /// Simulates a new connection (announced by the hub).
  String open(String fingerprint, {required bool outbound, bool answerHello = false}) {
    final id = 'c${_nextId++}';
    events.add(ChatLinkConnectedEvent(connectionId: id, fingerprint: fingerprint, ip: '192.168.1.20', outbound: outbound));
    if (answerHello) {
      receive(id, _peerHello);
    }
    return id;
  }

  void receive(String connectionId, ChatFrame frame) {
    events.add(ChatLinkMessageEvent(connectionId: connectionId, text: frame.encode()));
  }

  List<ChatFrame> framesSentOn(String connectionId) => sent.where((s) => s.$1 == connectionId).map((s) => ChatFrame.tryDecode(s.$2)!).toList();
}

void main() {
  late _FakeTransport transport;
  late PeerLinkManager manager;
  late List<(String, ChatFrame)> frames;
  late List<String> ready;
  late List<String> gone;
  late Set<String> blocked;
  late DateTime now;

  setUp(() {
    transport = _FakeTransport();
    frames = [];
    ready = [];
    gone = [];
    blocked = {};
    now = DateTime.utc(2026, 9, 30);
    manager =
        PeerLinkManager(
            transport: transport,
            ownFingerprint: _me,
            hello: () => _myHello,
            isBlocked: blocked.contains,
            helloTimeout: const Duration(milliseconds: 200),
            now: () => now,
          )
          ..onFrame = ((fp, frame) => frames.add((fp, frame)))
          ..onPeerReady = ((fp, version, hello, ip) => ready.add(fp))
          ..onPeerGone = gone.add
          ..start();
  });

  tearDown(() => manager.dispose());

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  group('inbound connection', () {
    test('Should send our hello, then become ready on the peer hello', () async {
      final id = transport.open(_peer, outbound: false);
      await settle();

      expect(transport.framesSentOn(id).single, isA<ChatHelloFrame>());
      expect(manager.isReady(_peer), false);

      transport.receive(id, _peerHello);
      await settle();

      expect(manager.isReady(_peer), true);
      expect(manager.versionOf(_peer), chatWsProtocolVersion);
      expect(ready, [_peer]);
    });

    test('Should drop frames received before the hello', () async {
      final id = transport.open(_peer, outbound: false);
      transport.receive(id, const ChatTypingFrame(isTyping: true));
      transport.receive(id, _peerHello);
      transport.receive(id, const ChatTypingFrame(isTyping: false));
      await settle();

      expect(frames.map((f) => (f.$2 as ChatTypingFrame).isTyping), [false]);
    });

    test('Should close a connection from a blocked device without saying hello', () async {
      blocked.add(_peer);
      final id = transport.open(_peer, outbound: false);
      await settle();

      expect(transport.closed, [id]);
      expect(transport.sent, isEmpty);
    });

    test('Should close a connection without hello after the timeout', () async {
      final id = transport.open(_peer, outbound: false);
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(transport.closed, [id]);
      expect(manager.isReady(_peer), false);
    });

    test('Should close an incompatible peer and mark it legacy', () async {
      final id = transport.open(_peer, outbound: false);
      transport.receive(id, const ChatHelloFrame(version: 99, minVersion: 99, alias: 'Future'));
      await settle();

      expect(transport.closed, [id]);
      expect(await manager.ensureLink(_peerAddress), PeerLinkStatus.legacy);
    });

    test('Should route frames and report the peer gone on disconnect', () async {
      final id = transport.open(_peer, outbound: false, answerHello: true);
      transport.receive(id, const ChatAckFrame(ids: ['m1'], status: ChatReceiptStatus.delivered));
      await settle();

      expect(frames.single.$1, _peer);
      expect((frames.single.$2 as ChatAckFrame).ids, ['m1']);

      transport.events.add(ChatLinkDisconnectedEvent(connectionId: id, reason: 'timed out'));
      await settle();

      expect(manager.isReady(_peer), false);
      expect(gone, [_peer]);
    });
  });

  group('ensureLink', () {
    test('Should connect and wait for the hello', () async {
      expect(await manager.ensureLink(_peerAddress), PeerLinkStatus.ready);
      expect(manager.readyPeers, {_peer});
    });

    test('Should reuse a ready link', () async {
      await manager.ensureLink(_peerAddress);
      expect(await manager.ensureLink(_peerAddress), PeerLinkStatus.ready);
      expect(transport.connects, 1);
    });

    test('Should share one attempt between concurrent callers', () async {
      final results = await Future.wait([manager.ensureLink(_peerAddress), manager.ensureLink(_peerAddress)]);

      expect(results, [PeerLinkStatus.ready, PeerLinkStatus.ready]);
      expect(transport.connects, 1);
    });

    test('Should fall back to legacy for a v1.0.3 peer and remember it', () async {
      transport.onConnect = () => ChatLinkResultEvent(error: const ChatLinkError(ChatLinkErrorKind.unsupported, status: 404));

      expect(await manager.ensureLink(_peerAddress), PeerLinkStatus.legacy);
      expect(await manager.ensureLink(_peerAddress), PeerLinkStatus.legacy);
      expect(transport.connects, 1);

      // Retried later: the peer may have been updated.
      now = now.add(const Duration(minutes: 11));
      transport.onConnect = null;
      expect(await manager.ensureLink(_peerAddress), PeerLinkStatus.ready);
    });

    test('Should report an impostor, never legacy', () async {
      transport.onConnect = () => ChatLinkResultEvent(error: const ChatLinkError(ChatLinkErrorKind.fingerprintMismatch));

      expect(await manager.ensureLink(_peerAddress), PeerLinkStatus.impostor);
    });

    test('Should report unreachable on network errors and missing hello', () async {
      transport.onConnect = () => ChatLinkResultEvent(error: const ChatLinkError(ChatLinkErrorKind.timeout));
      expect(await manager.ensureLink(_peerAddress), PeerLinkStatus.unreachable);

      transport.onConnect = () => ChatLinkResultEvent(connectionId: transport.open(_peer, outbound: true));
      expect(await manager.ensureLink(_peerAddress), PeerLinkStatus.unreachable);
    });
  });

  group('send', () {
    test('Should fail without a ready link', () async {
      expect(await manager.send(_peer, const ChatTypingFrame(isTyping: true)), false);
    });

    test('Should send the encoded frame on the active link', () async {
      await manager.ensureLink(_peerAddress);
      final id = transport.sent.first.$1;

      expect(await manager.send(_peer.toLowerCase(), const ChatTypingFrame(isTyping: true)), true);
      expect(transport.framesSentOn(id).last, isA<ChatTypingFrame>());
    });
  });

  group('duplicate links', () {
    Future<(String, String)> openBoth() async {
      final outbound = transport.open(_peer, outbound: true, answerHello: true);
      await settle();
      final inbound = transport.open(_peer, outbound: false, answerHello: true);
      await settle();
      return (outbound, inbound);
    }

    test('Should keep our outbound link when our fingerprint is smaller', () async {
      // _me (BBBB) < _peer (CCCC)
      final (outbound, inbound) = await openBoth();

      expect(transport.closed, [inbound]);
      await manager.send(_peer, const ChatTypingFrame(isTyping: true));
      expect(transport.framesSentOn(outbound).last, isA<ChatTypingFrame>());
      expect(gone, isEmpty);
    });

    test('Should keep the inbound link when the peer fingerprint is smaller', () async {
      const smallerPeer = 'AAAA';
      final outbound = transport.open(smallerPeer, outbound: true, answerHello: true);
      await settle();
      final inbound = transport.open(smallerPeer, outbound: false, answerHello: true);
      await settle();

      expect(transport.closed, [outbound]);
      expect(ready, [smallerPeer]);
      await manager.send(smallerPeer, const ChatTypingFrame(isTyping: true));
      expect(transport.framesSentOn(inbound).last, isA<ChatTypingFrame>());
    });
  });
}
