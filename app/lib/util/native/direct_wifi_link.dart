import 'dart:async';

import 'package:localsend_app/provider/network/send_provider.dart';
import 'package:localsend_app/util/native/hotspot_helper.dart';
import 'package:localsend_isolates/model/session_status.dart';
import 'package:logging/logging.dart';
import 'package:refena_flutter/refena_flutter.dart';

final _logger = Logger('DirectWifiLink');

/// Keeps Aika on the Wi-Fi network of a receiver joined from its QR code
/// (its own hotspot) for as long as files are being sent to it, then gives
/// the network back.
///
/// Joining binds the whole app to that Wi-Fi (no Internet there). Releasing
/// it right after pairing, as before, sent the files through mobile data,
/// where the receiver cannot be reached: the transfer never started.
///
/// Released when:
/// - every send session has ended (finished, declined, cancelled…) or was
///   closed, once at least one had started;
/// - no session started within [_startTimeout] (pairing done, nothing sent);
/// - [release] is called (new scan, app closing).
class DirectWifiLink {
  DirectWifiLink._();

  static const _checkInterval = Duration(seconds: 2);
  static const _startTimeout = Duration(minutes: 3);

  static Timer? _timer;
  static bool _sawSession = false;
  static DateTime _since = DateTime.now();

  /// Whether Aika is currently held on a receiver's Wi-Fi.
  static bool get active => _timer != null;

  /// Takes over the network joined by [tryAutoJoinWifiNetwork] and watches
  /// the send sessions to release it at the right time.
  static void hold(Ref ref) {
    _timer?.cancel();
    _sawSession = false;
    _since = DateTime.now();
    _timer = Timer.periodic(_checkInterval, (_) => _check(ref));
    _logger.info('Holding the receiver Wi-Fi for the transfer');
  }

  static void _check(Ref ref) {
    final sessions = ref.read(sendProvider).values;
    if (sessions.any((s) => !isFinalSessionStatus(s.status))) {
      _sawSession = true;
      return;
    }
    if (_sawSession || DateTime.now().difference(_since) > _startTimeout) {
      unawaited(release());
    }
  }

  /// Gives the normal network back. Safe to call at any time.
  static Future<void> release() async {
    final wasActive = _timer != null;
    _timer?.cancel();
    _timer = null;
    if (wasActive) {
      _logger.info('Releasing the receiver Wi-Fi');
      await unbindAutoJoinedWifiNetwork();
    }
  }
}

/// Whether a session in [status] is over (nothing more will be sent).
bool isFinalSessionStatus(SessionStatus status) {
  return switch (status) {
    SessionStatus.waiting || SessionStatus.sending => false,
    _ => true,
  };
}
