import 'package:flutter/foundation.dart';
import 'package:localsend_app/provider/network/server/server_provider.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_isolates/isolate.dart';
import 'package:logging/logging.dart';
import 'package:refena_flutter/refena_flutter.dart';

final _logger = Logger('ReceiveWatchdog');

/// Brings reception back when Aika returns from a long stay in the
/// background.
///
/// Android and iOS freeze a backgrounded app and may close its network
/// sockets (Doze, Wi-Fi sleep, network change) while the app still shows
/// "Prêt à recevoir": the other devices then neither find this one nor reach
/// its server. On return, the receive server and the discovery (UDP
/// multicast) sockets are rebound, and this device announces itself again.
final receiveWatchdogProvider = Provider((ref) => ReceiveWatchdog(ref));

class ReceiveWatchdog {
  /// Shorter stays keep their sockets: nothing to do.
  static const minBackground = Duration(seconds: 30);

  final Ref _ref;
  final DateTime Function() _clock;
  DateTime? _backgroundSince;
  bool _recovering = false;

  ReceiveWatchdog(this._ref, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  /// Only phones and tablets suspend apps in the background.
  static bool get _applies => checkPlatform([TargetPlatform.android, TargetPlatform.iOS]);

  /// The app left the foreground (paused / hidden).
  void onBackground() {
    _backgroundSince ??= _clock();
  }

  /// The app is back. Returns whether reception was restarted.
  Future<bool> onResumed() async {
    final since = _backgroundSince;
    _backgroundSince = null;
    if (!_applies || since == null || _recovering || _clock().difference(since) < minBackground) {
      return false;
    }
    _recovering = true;
    try {
      return await _recover();
    } finally {
      _recovering = false;
    }
  }

  Future<bool> _recover() async {
    final server = _ref.read(serverProvider);
    var restarted = false;

    // The receive server, unless a transfer or a share link is in progress
    // (restarting would cut it).
    if (server != null && server.session == null && server.webSendState == null) {
      try {
        _logger.info('Back from the background: restarting the receive server');
        await _ref.notifier(serverProvider).restartServerFromSettings();
        restarted = true;
      } catch (e) {
        _logger.warning('Could not restart the receive server', e);
      }
    }

    // The discovery sockets: rebinding them also announces this device on
    // the network again, so the other devices find it right away.
    try {
      _ref.redux(parentIsolateProvider).dispatch(IsolateSendMulticastRestartListenerAction());
      restarted = true;
    } catch (e) {
      _logger.warning('Could not restart the discovery listener', e);
    }
    return restarted;
  }
}
