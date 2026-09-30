import 'package:localsend_isolates/rust/api/chat.dart';
import 'package:localsend_isolates/src/task/server/http_server.dart';
import 'package:refena_flutter/refena_flutter.dart';

final chatHubProvider = Provider((ref) => ChatHubService());

/// Wraps the Rust chat hub (persistent chat WebSocket connections).
/// Lives next to the HTTP server, which accepts the inbound connections.
class ChatHubService {
  RsChatHub? _hub;

  RsChatHub? get hub => _hub;

  /// Creates the hub with this device's TLS identity and returns its event
  /// stream. Can only be called once per isolate.
  Stream<RsChatEvent> start({required String cert, required String privateKey}) {
    if (_hub != null) {
      throw StateError('Chat hub already started');
    }
    final hub = createChatHub(cert: cert, privateKey: privateKey);
    _hub = hub;
    return hub.listen();
  }

  /// Lets [server] accept chat connections into the hub, if both exist.
  void attachTo(HttpServerService server) {
    final hub = _hub;
    if (hub != null) {
      server.attachChatHub(hub);
    }
  }

  Future<String> connect({required String ip, required int port, required String fingerprint}) {
    return _requireHub().connect(ip: ip, port: port, fingerprint: fingerprint);
  }

  Future<void> send({required String connectionId, required String text}) {
    return _requireHub().send(connectionId: connectionId, text: text);
  }

  Future<void> close({required String connectionId}) async {
    await _hub?.close(connectionId: connectionId);
  }

  RsChatHub _requireHub() {
    final hub = _hub;
    if (hub == null) {
      throw const RsChatError.other(message: 'Chat hub not started');
    }
    return hub;
  }
}
