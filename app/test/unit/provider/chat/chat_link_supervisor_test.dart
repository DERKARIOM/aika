import 'dart:async';

import 'package:localsend_app/model/chat/chat_frame.dart';
import 'package:localsend_app/provider/chat/chat_link_supervisor.dart';
import 'package:localsend_app/provider/chat/peer_link_manager.dart';
import 'package:localsend_isolates/isolate.dart';
import 'package:test/test.dart';

const _me = 'BBBB';
const _peer = 'CCCC';
const _peerAddress = PeerAddress(fingerprint: _peer, ip: '192.168.1.20', port: 53317);
const _hello = ChatHelloFrame(version: chatWsProtocolVersion, minVersion: chatWsMinProtocolVersion, alias: 'Peer');

/// A peer that is either reachable (answers its hello) or not.
class _FakeTransport implements ChatLinkTransport {
  final events = StreamController<ChatLinkEvent>();
  int connects = 0;
  int _nextId = 0;
  ChatLinkError? connectError;

  @override
  Stream<ChatLinkEvent> start() => events.stream;

  @override
  Future<ChatLinkResultEvent> connect({required String ip, required int port, required String fingerprint}) async {
    connects++;
    final error = connectError;
    if (error != null) {
      return ChatLinkResultEvent(error: error);
    }
    final id = 'c${_nextId++}';
    events
      ..add(ChatLinkConnectedEvent(connectionId: id, fingerprint: fingerprint, ip: ip, outbound: true))
      ..add(ChatLinkMessageEvent(connectionId: id, text: _hello.encode()));
    return ChatLinkResultEvent(connectionId: id);
  }

  @override
  Future<ChatLinkResultEvent> send({required String connectionId, required String text}) async => ChatLinkResultEvent();

  @override
  void close(String connectionId) {
    events.add(ChatLinkDisconnectedEvent(connectionId: connectionId, reason: 'closed'));
  }
}

void main() {
  late _FakeTransport transport;
  late PeerLinkManager links;
  late ChatLinkSupervisor supervisor;
  late Set<String> blocked;

  setUp(() {
    transport = _FakeTransport();
    blocked = {};
    links = PeerLinkManager(
      transport: transport,
      ownFingerprint: _me,
      hello: () => const ChatHelloFrame(version: chatWsProtocolVersion, minVersion: chatWsMinProtocolVersion, alias: 'Me'),
      isBlocked: (_) => false,
      helloTimeout: const Duration(milliseconds: 100),
    );
    supervisor = ChatLinkSupervisor(
      links: links,
      isAllowed: (fp) => !blocked.contains(fp),
      baseDelay: const Duration(milliseconds: 10),
      maxDelay: const Duration(milliseconds: 40),
      legacyDelay: const Duration(seconds: 30),
      random: () => 0,
    );
    links
      ..onPeerGone = supervisor.onPeerGone
      ..start();
  });

  tearDown(() async {
    supervisor.dispose();
    await links.dispose();
  });

  Future<void> wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

  test('Should link a contact as soon as it is on the network', () async {
    supervisor.setCandidates([_peerAddress]);
    await wait(5);

    expect(links.isReady(_peer), true);
    expect(transport.connects, 1);
  });

  test('Should retry an unreachable contact with growing delays', () async {
    transport.connectError = const ChatLinkError(ChatLinkErrorKind.timeout);
    supervisor.setCandidates([_peerAddress]);
    await wait(5);
    expect(transport.connects, 1);

    // Retries after 20 ms, then 40 ms (capped).
    await wait(30);
    expect(transport.connects, 2);

    transport.connectError = null;
    await wait(50);
    expect(links.isReady(_peer), true);
    expect(transport.connects, 3);
  });

  test('Should reconnect shortly after the link drops', () async {
    supervisor.setCandidates([_peerAddress]);
    await wait(5);
    links.disconnect(_peer);
    await wait(5);
    expect(links.isReady(_peer), false);

    await wait(20);
    expect(links.isReady(_peer), true);
    expect(transport.connects, 2);
  });

  test('Should stop retrying a contact that left the network', () async {
    transport.connectError = const ChatLinkError(ChatLinkErrorKind.timeout);
    supervisor.setCandidates([_peerAddress]);
    await wait(5);

    supervisor.setCandidates(const []);
    await wait(60);

    expect(transport.connects, 1);
  });

  test('Should wait long before asking an older app again', () async {
    transport.connectError = const ChatLinkError(ChatLinkErrorKind.unsupported, status: 404);
    supervisor.setCandidates([_peerAddress]);
    await wait(60);

    expect(transport.connects, 1);
  });

  test('Should never dial a blocked contact', () async {
    blocked.add(_peer);
    supervisor.setCandidates([_peerAddress]);
    await wait(20);

    expect(transport.connects, 0);
  });

  test('Should retry at once when asked', () async {
    transport.connectError = const ChatLinkError(ChatLinkErrorKind.timeout);
    supervisor.setCandidates([_peerAddress]);
    await wait(5);

    transport.connectError = null;
    supervisor.retryNow();
    await wait(5);

    expect(links.isReady(_peer), true);
    expect(transport.connects, 2);
  });
}
