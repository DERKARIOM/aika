import 'dart:async';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:localsend_app/model/chat/chat_database.dart';
import 'package:localsend_app/model/chat/chat_envelope.dart';
import 'package:localsend_app/model/chat/chat_frame.dart';
import 'package:localsend_app/provider/chat/chat_database_provider.dart';
import 'package:localsend_app/provider/chat/chat_link_provider.dart';
import 'package:localsend_app/provider/chat/chat_provider.dart';
import 'package:localsend_app/provider/chat/peer_link_manager.dart';
import 'package:localsend_app/provider/favorites_provider.dart';
import 'package:localsend_app/provider/logging/discovery_logs_provider.dart';
import 'package:localsend_app/provider/network/nearby_devices_provider.dart';
import 'package:localsend_app/provider/persistence_provider.dart';
import 'package:localsend_isolates/isolate.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/model/device_info_result.dart';
import 'package:localsend_isolates/model/dto/multicast_dto.dart';
import 'package:localsend_isolates/model/stored_security_context.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:test/test.dart';

import '../../../mocks.mocks.dart';

const _me = 'AAAA';
const _peer = 'CCCC';
const _peerHello = ChatHelloFrame(version: chatWsProtocolVersion, minVersion: chatWsMinProtocolVersion, alias: 'Bob');

/// The peer side of the chat links: answers hellos, records frames.
class _FakeTransport implements ChatLinkTransport {
  final events = StreamController<ChatLinkEvent>();
  final sent = <ChatFrame>[];
  int connects = 0;
  int _nextId = 0;

  /// When set, every connect() fails with it (the peer is not linkable).
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
    return ChatLinkResultEvent(connectionId: open());
  }

  @override
  Future<ChatLinkResultEvent> send({required String connectionId, required String text}) async {
    sent.add(ChatFrame.tryDecode(text)!);
    return ChatLinkResultEvent();
  }

  @override
  void close(String connectionId) {
    events.add(ChatLinkDisconnectedEvent(connectionId: connectionId, reason: 'closed'));
  }

  String open() {
    final id = 'c${_nextId++}';
    events
      ..add(ChatLinkConnectedEvent(connectionId: id, fingerprint: _peer, ip: '192.168.1.20', outbound: true))
      ..add(ChatLinkMessageEvent(connectionId: id, text: _peerHello.encode()));
    return id;
  }

  void receive(ChatFrame frame) {
    events.add(ChatLinkMessageEvent(connectionId: 'c${_nextId - 1}', text: frame.encode()));
  }

  List<T> sentOf<T extends ChatFrame>() => sent.whereType<T>().toList();
}

final _bob = Device.empty.copyWith(ip: '192.168.1.20', port: 53317, https: true, fingerprint: _peer, alias: 'Bob');

void main() {
  late ChatDatabase db;
  late _FakeTransport transport;
  late RefenaContainer container;
  late ChatService chat;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  setUp(() async {
    db = ChatDatabase(NativeDatabase.memory());
    transport = _FakeTransport();
    final links = PeerLinkManager(
      transport: transport,
      ownFingerprint: _me,
      hello: () => const ChatHelloFrame(version: chatWsProtocolVersion, minVersion: chatWsMinProtocolVersion, alias: 'Me'),
      isBlocked: (_) => false,
    );
    container = RefenaContainer(
      overrides: [
        chatDatabaseProvider.overrideWithValue(db),
        persistenceProvider.overrideWithValue(MockPersistenceService()),
        peerLinkManagerProvider.overrideWithValue(links),
        nearbyDevicesProvider.overrideWithNotifier(
          (ref) => NearbyDevicesService(
            isolateController: IsolateController(initialState: ParentIsolateState.initial(_syncState)),
            favoriteService: ref.notifier(favoritesProvider),
            discoveryLogs: ref.notifier(discoveryLoggerProvider),
          ),
        ),
      ],
    );
    chat = container.notifier(chatProvider)..startLinks();
    // An existing conversation: no new-contact dialog.
    await db.upsertConversation(peerFingerprint: _peer, peerAlias: 'Bob');
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> settle() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<ChatMessage> onlyMessage() async => (await db.watchMessages(_peer).first).single;

  test('Should send a text over the link and keep it queued until acked', () async {
    await chat.sendText(target: _bob, text: 'salut');
    await settle();

    final msg = transport.sentOf<ChatMessageFrame>().single;
    expect(msg.text, 'salut');
    final row = await onlyMessage();
    expect(row.id, msg.id);
    expect(row.status, ChatMessageStatusColumn.sent);
    expect(row.sentAt, isNotNull);
    // Still queued, due again after the ack timeout.
    expect(await db.watchOutboxSize().first, 1);
    expect(await db.dueOutboxMessages(DateTime.now().toUtc()), isEmpty);

    transport.receive(ChatAckFrame(ids: [msg.id], status: ChatReceiptStatus.delivered));
    await settle();

    expect((await onlyMessage()).status, ChatMessageStatusColumn.delivered);
    expect(await db.watchOutboxSize().first, 0);
  });

  test('Should send a queued message as soon as the peer comes online', () async {
    // Written while Bob was offline: pending, retry scheduled far away.
    await db.insertMessage(
      ChatMessagesCompanion.insert(
        id: 'queued',
        conversationId: _peer,
        direction: ChatMessageDirectionColumn.outgoing,
        contentType: ChatContentType.text.name,
        status: ChatMessageStatusColumn.pending,
        createdAt: DateTime.utc(2026),
        body: const Value('tu es là ?'),
      ),
    );
    await db.enqueueOutbox('queued', nextAttemptAt: DateTime.now().toUtc().add(const Duration(hours: 1)));

    transport.open();
    await settle();

    expect(transport.sentOf<ChatMessageFrame>().single.id, 'queued');
    expect((await onlyMessage()).status, ChatMessageStatusColumn.sent);
  });

  test('Should send a failed message again on retry', () async {
    transport.open();
    await settle();
    await db.insertMessage(
      ChatMessagesCompanion.insert(
        id: 'refused',
        conversationId: _peer,
        direction: ChatMessageDirectionColumn.outgoing,
        contentType: ChatContentType.text.name,
        status: ChatMessageStatusColumn.failed,
        createdAt: DateTime.utc(2026),
        body: const Value('encore'),
        errorMessage: const Value('Message refusé par le destinataire.'),
      ),
    );

    await chat.retryMessage('refused');
    await settle();

    expect(transport.sentOf<ChatMessageFrame>().single.id, 'refused');
    final row = await onlyMessage();
    expect(row.status, ChatMessageStatusColumn.sent);
    expect(row.errorMessage, isNull);
  });

  test('Should record the peer protocol and presence', () async {
    transport.open();
    await settle();

    expect(chat.state.onlinePeerFingerprints, {_peer});
    expect((await db.getConversation(_peer))!.peerChatProtocol, chatWsProtocolVersion);
  });

  test('Should store an incoming message once and ack every copy', () async {
    transport.open();
    await settle();
    final frame = ChatMessageFrame(id: 'm1', timestamp: DateTime.utc(2026, 9, 30), contentType: ChatContentType.text, text: 'coucou');

    transport.receive(frame);
    await settle();
    transport.receive(frame); // retransmission: our ack got lost
    await settle();

    final row = await onlyMessage();
    expect(row.body, 'coucou');
    expect(row.direction, ChatMessageDirectionColumn.incoming);
    expect((await db.getConversation(_peer))!.unreadCount, 1);
    final acks = transport.sentOf<ChatAckFrame>();
    expect(acks.map((a) => (a.ids.single, a.status)), [('m1', ChatReceiptStatus.delivered), ('m1', ChatReceiptStatus.delivered)]);
  });

  test('Should send read receipts over the link when opening the conversation', () async {
    transport.open();
    await settle();
    transport.receive(ChatMessageFrame(id: 'm1', timestamp: DateTime.utc(2026), contentType: ChatContentType.text, text: 'a'));
    transport.receive(ChatMessageFrame(id: 'm2', timestamp: DateTime.utc(2026, 2), contentType: ChatContentType.text, text: 'b'));
    await settle();

    final cleared = <String>[];
    chat.onConversationRead = cleared.add;
    await chat.markConversationRead(_bob);
    await settle();

    // Lets the notification layer clear this conversation's notification.
    expect(cleared, [_peer]);

    final read = transport.sentOf<ChatAckFrame>().where((a) => a.status == ChatReceiptStatus.read).single;
    expect(read.ids, ['m1', 'm2']);
  });

  test('Should delete only the retracted messages this peer sent us', () async {
    transport.open();
    await settle();
    transport.receive(ChatMessageFrame(id: 'm1', timestamp: DateTime.utc(2026), contentType: ChatContentType.text, text: 'a'));
    await settle();
    // Our own message, and a message from another contact: a peer must
    // never be able to delete those.
    await db.insertMessage(
      ChatMessagesCompanion.insert(
        id: 'mine',
        conversationId: _peer,
        direction: ChatMessageDirectionColumn.outgoing,
        contentType: ChatContentType.text.name,
        status: ChatMessageStatusColumn.sent,
        createdAt: DateTime.utc(2025),
        body: const Value('moi'),
      ),
    );
    await db.upsertConversation(peerFingerprint: 'DDDD', peerAlias: 'Eve');
    await db.insertMessage(
      ChatMessagesCompanion.insert(
        id: 'other',
        conversationId: 'DDDD',
        direction: ChatMessageDirectionColumn.incoming,
        contentType: ChatContentType.text.name,
        status: ChatMessageStatusColumn.delivered,
        createdAt: DateTime.utc(2025),
      ),
    );
    expect((await db.getConversation(_peer))!.unreadCount, 1);

    transport.receive(const ChatRetractFrame(ids: ['m1', 'mine', 'other']));
    await settle();

    expect(await db.getMessage('m1'), isNull);
    expect(await db.getMessage('mine'), isNotNull);
    expect(await db.getMessage('other'), isNotNull);
    final conversation = (await db.getConversation(_peer))!;
    expect(conversation.unreadCount, 0);
    expect(conversation.lastMessagePreview, 'moi');
  });

  test('Should send a retraction stored while the link was down once it is back', () async {
    // E.g. an attachment cancelled offline, then the app restarted.
    await db.addPendingRetraction(_peer, 'gone');

    transport.open();
    await settle();
    await settle();

    expect(transport.sentOf<ChatRetractFrame>().single.ids, ['gone']);
    expect(await db.pendingRetractions(_peer, limit: 10), isEmpty);
  });

  test('Should file a message dated in the future at its reception time', () async {
    transport.open();
    await settle();
    final now = DateTime.now().toUtc();
    transport.receive(ChatMessageFrame(id: 'future', timestamp: now.add(const Duration(days: 1)), contentType: ChatContentType.text, text: 'a'));
    await settle();

    final row = await onlyMessage();
    expect(row.createdAt.difference(now).inMinutes.abs(), lessThan(1));
  });

  test('Should split a too long text into ordered messages', () async {
    transport.open();
    await settle();

    await chat.sendText(target: _bob, text: '${'a' * chatMaxTextLength}fin');
    await settle();

    final sent = transport.sentOf<ChatMessageFrame>();
    expect(sent.map((m) => m.text), ['a' * chatMaxTextLength, 'fin']);
    expect(sent[1].timestamp.isAfter(sent[0].timestamp), true);
  });

  test('Should send on reconnection the read receipts lost with the link', () async {
    transport.open();
    await settle();
    transport.close('c0');
    await settle();

    // Read while offline: the receipt cannot leave.
    transport.connectError = const ChatLinkError(ChatLinkErrorKind.timeout);
    await db.insertMessage(
      ChatMessagesCompanion.insert(
        id: 'offline',
        conversationId: _peer,
        direction: ChatMessageDirectionColumn.incoming,
        contentType: ChatContentType.text.name,
        status: ChatMessageStatusColumn.delivered,
        createdAt: DateTime.now().toUtc(),
        body: const Value('lu hors ligne'),
      ),
    );
    await chat.markConversationRead(_bob);
    await settle();
    expect(transport.sentOf<ChatAckFrame>().where((a) => a.status == ChatReceiptStatus.read), isEmpty);

    transport.connectError = null;
    transport.open();
    await settle();

    final read = transport.sentOf<ChatAckFrame>().where((a) => a.status == ChatReceiptStatus.read).single;
    expect(read.ids, ['offline']);
  });

  group('without a chat link', () {
    /// The message is kept, unsent, for a later attempt: never handed to the
    /// file-transfer pipeline (no HTTP client is even available here).
    Future<ChatMessage> expectHeldInOutbox() async {
      final row = await onlyMessage();
      expect(row.status, ChatMessageStatusColumn.pending);
      expect(transport.sentOf<ChatMessageFrame>(), isEmpty);
      expect(await db.watchOutboxSize().first, 1);
      expect(await db.dueOutboxMessages(DateTime.now().toUtc()), isEmpty);
      return row;
    }

    test('Should keep a message for an unreachable peer, without an error', () async {
      transport.connectError = const ChatLinkError(ChatLinkErrorKind.timeout);

      await chat.sendText(target: _bob, text: 'salut');
      await settle();

      expect((await expectHeldInOutbox()).errorMessage, isNull);
    });

    test('Should tell when the peer app has no instant messaging', () async {
      transport.connectError = const ChatLinkError(ChatLinkErrorKind.unsupported, status: 404);

      await chat.sendText(target: _bob, text: 'salut');
      await settle();

      expect((await expectHeldInOutbox()).errorMessage, contains('Mettez-le à jour'));
    });

    test('Should tell when the peer has encryption off, without dialing it', () async {
      await chat.sendText(target: _bob.copyWith(https: false), text: 'salut');
      await settle();

      expect((await expectHeldInOutbox()).errorMessage, contains('chiffrement'));
      expect(transport.connects, 0);
    });

    test('Should hold back a message for an impostor', () async {
      transport.connectError = const ChatLinkError(ChatLinkErrorKind.fingerprintMismatch);

      await chat.sendText(target: _bob, text: 'salut');
      await settle();

      expect((await expectHeldInOutbox()).errorMessage, contains('identité'));
    });

    test('Should dial an offline peer once per outbox pass', () async {
      transport.connectError = const ChatLinkError(ChatLinkErrorKind.timeout);
      for (final id in ['q1', 'q2', 'q3']) {
        await db.insertMessage(
          ChatMessagesCompanion.insert(
            id: id,
            conversationId: _peer,
            direction: ChatMessageDirectionColumn.outgoing,
            contentType: ChatContentType.text.name,
            status: ChatMessageStatusColumn.pending,
            createdAt: DateTime.utc(2026),
            body: Value(id),
          ),
        );
        await db.enqueueOutbox(id);
      }
      // Bob is on the network, but its chat link cannot be opened.
      await container.redux(nearbyDevicesProvider).dispatchAsync(RegisterDeviceAction(_bob));

      await chat.retryDueOutbox();
      await settle();

      expect(transport.connects, 1);
      expect(transport.sentOf<ChatMessageFrame>(), isEmpty);
      expect(await db.dueOutboxMessages(DateTime.now().toUtc()), isEmpty);
    });

    test('Should not send nor dial for a typing signal', () async {
      await chat.setTyping(target: _bob, isTyping: true);
      await settle();

      expect(transport.connects, 0);
      expect(transport.sent, isEmpty);
    });
  });

  test('Should forget presence and typing when the link goes', () async {
    transport.open();
    await settle();
    transport.receive(const ChatTypingFrame(isTyping: true));
    await settle();
    expect(chat.state.typingPeerFingerprints, {_peer});

    transport.close('c0');
    await settle();

    expect(chat.state.onlinePeerFingerprints, isEmpty);
    expect(chat.state.typingPeerFingerprints, isEmpty);
  });
}

final _syncState = SyncState(
  rootIsolateToken: Object(),
  securityContext: const StoredSecurityContext(privateKey: '', publicKey: '', certificate: '', certificateHash: _me),
  deviceInfo: DeviceInfoResult(deviceType: DeviceType.desktop, deviceModel: null, androidSdkInt: null),
  alias: 'Me',
  port: 53317,
  networkWhitelist: null,
  networkBlacklist: null,
  protocol: ProtocolType.https,
  multicastGroup: '224.0.0.167',
  discoveryTimeout: 500,
  serverRunning: true,
  download: false,
);
