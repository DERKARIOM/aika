import 'package:localsend_app/model/chat/chat_frame.dart';
import 'package:localsend_app/provider/chat/blocked_devices_provider.dart';
import 'package:localsend_app/provider/chat/peer_link_manager.dart';
import 'package:localsend_app/provider/device_info_provider.dart';
import 'package:localsend_app/provider/security_provider.dart';
import 'package:localsend_isolates/isolate.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// [ChatLinkTransport] backed by the Rust chat hub running in the server
/// isolate.
class IsolateChatLinkTransport implements ChatLinkTransport {
  final Ref _ref;

  IsolateChatLinkTransport(this._ref);

  @override
  Stream<ChatLinkEvent> start() => _ref.redux(parentIsolateProvider).dispatchTakeResult(IsolateChatHubStartAction());

  @override
  Future<ChatLinkResultEvent> connect({required String ip, required int port, required String fingerprint}) {
    return _ref.redux(parentIsolateProvider).dispatchTakeResult(IsolateChatConnectAction(ip: ip, port: port, fingerprint: fingerprint));
  }

  @override
  Future<ChatLinkResultEvent> send({required String connectionId, required String text}) {
    return _ref.redux(parentIsolateProvider).dispatchTakeResult(IsolateChatSendAction(connectionId: connectionId, text: text));
  }

  @override
  void close(String connectionId) {
    _ref.redux(parentIsolateProvider).dispatch(IsolateChatCloseAction(connectionId: connectionId));
  }
}

/// The app-wide chat link manager. Started by `ChatService.startLinks`.
final peerLinkManagerProvider = Provider<PeerLinkManager>((ref) {
  return PeerLinkManager(
    transport: IsolateChatLinkTransport(ref),
    ownFingerprint: ref.read(securityProvider).certificateHash,
    hello: () {
      final device = ref.read(deviceFullInfoProvider);
      return ChatHelloFrame(
        version: chatWsProtocolVersion,
        minVersion: chatWsMinProtocolVersion,
        alias: device.alias,
        deviceModel: device.deviceModel,
      );
    },
    isBlocked: (fingerprint) => ref.read(blockedDevicesProvider).isFingerprintBlocked(fingerprint),
  );
});
