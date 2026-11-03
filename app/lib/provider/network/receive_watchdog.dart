import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:localsend_app/provider/chat/chat_provider.dart';
import 'package:localsend_app/provider/local_ip_provider.dart';
import 'package:localsend_app/provider/network/nearby_devices_provider.dart';
import 'package:localsend_app/provider/network/server/server_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_isolates/api_route_builder.dart';
import 'package:localsend_isolates/constants.dart';
import 'package:localsend_isolates/isolate.dart';
import 'package:localsend_isolates/model/session_status.dart';
import 'package:localsend_isolates/util/network_interfaces.dart';
import 'package:logging/logging.dart';
import 'package:refena_flutter/refena_flutter.dart';

final _logger = Logger('ReceiveWatchdog');

/// Keeps reception (receive server + device discovery) working for as long
/// as Aika runs, whatever happens in the background.
///
/// - Android and iOS freeze a backgrounded app and may close its sockets
///   (Doze, Wi-Fi sleep): on return after a long stay, the server and the
///   discovery sockets are rebound.
/// - Desktops never freeze the app, but the system sleeps, Wi-Fi reconnects,
///   the network or the IP changes while Aika sits in the tray for hours.
///   A light periodic check (one loopback request, one interface listing)
///   and a check on every return to the foreground detect what actually
///   broke and repair only that, without restarting the app.
final receiveWatchdogProvider = Provider((ref) => ReceiveWatchdog(_RefenaReceiveServices(ref)));

/// State of the receive server, as far as the watchdog is concerned.
enum ReceiveServerStatus {
  /// Not running.
  stopped,

  /// Running, nothing in progress: can be restarted if broken.
  idle,

  /// A transfer or a share link is in progress: never restarted.
  busy,
}

/// The services the watchdog supervises (injected to unit test the decisions).
abstract class ReceiveServices {
  ReceiveServerStatus get serverStatus;

  /// Whether the server should run (it was not stopped by the user).
  bool get serverShouldRun;

  /// Whether the server answers HTTP requests on its port.
  Future<bool> probeServer();

  /// (Re)starts the server from the settings.
  Future<void> restartServer();

  /// Describes the current network interfaces (see [networkInterfacesFingerprint]).
  Future<String> networkFingerprint();

  /// The network changed: refreshes the local IPs and forgets the devices
  /// found on the previous network (their addresses are stale).
  void onNetworkChanged();

  /// Rebinds the discovery sockets, which also announces this device.
  void restartDiscovery();

  /// Announces this device: every other device answers, refreshing the lists.
  void announce();

  /// Reception was restarted: connections relying on it can retry now.
  void onReceptionRestarted();
}

class ReceiveWatchdog {
  /// Shorter stays keep their sockets: nothing to rebind.
  static const minBackground = Duration(seconds: 30);

  /// Period of the desktop health check.
  static const monitorInterval = Duration(seconds: 60);

  /// Returns to the foreground closer than this are not checked again.
  static const minCheckInterval = Duration(seconds: 10);

  final ReceiveServices _services;
  final DateTime Function() _clock;
  final bool _desktop;
  final bool _mobile;
  final Duration _probeRetryDelay;

  DateTime? _backgroundSince;
  bool _checking = false;
  DateTime? _lastCheck;
  DateTime? _lastTick;
  String? _networkFingerprint;
  Timer? _timer;

  ReceiveWatchdog(
    this._services, {
    DateTime Function()? clock,
    bool? desktop,
    bool? mobile,
    Duration probeRetryDelay = const Duration(seconds: 1),
  }) : _clock = clock ?? DateTime.now,
       _desktop = desktop ?? checkPlatformIsDesktop(),
       // Only phones and tablets suspend apps in the background.
       _mobile = mobile ?? checkPlatform([TargetPlatform.android, TargetPlatform.iOS]),
       _probeRetryDelay = probeRetryDelay;

  /// Starts the periodic health check (desktop only, idempotent).
  void startMonitoring() {
    if (!_desktop || _timer != null) {
      return;
    }
    _logger.info('Starting the reception health monitor (every ${monitorInterval.inSeconds}s)');
    _lastTick = _clock();
    // ignore: discarded_futures
    _services.networkFingerprint().then((f) => _networkFingerprint ??= f).catchError((Object _) => '');
    _timer = Timer.periodic(monitorInterval, (_) {
      // ignore: discarded_futures
      onTick();
    });
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }

  /// The app left the foreground (paused / hidden / minimized / in the tray).
  void onBackground() {
    _backgroundSince ??= _clock();
  }

  /// The app is back. Returns whether something was restarted.
  Future<bool> onResumed() async {
    final since = _backgroundSince;
    _backgroundSince = null;
    final longBackground = since != null && _clock().difference(since) >= minBackground;

    if (_desktop) {
      return check(reason: 'back to the foreground', thorough: false, announce: longBackground);
    }

    if (!_mobile || !longBackground || _checking) {
      return false;
    }
    _checking = true;
    try {
      return await _recoverMobile();
    } finally {
      _checking = false;
    }
  }

  /// One tick of the periodic check. A tick much later than planned means
  /// that the system was asleep: multicast memberships and pooled
  /// connections did not survive it.
  @visibleForTesting
  Future<bool> onTick() async {
    final now = _clock();
    final last = _lastTick;
    _lastTick = now;
    final resumedFromSleep = last != null && now.difference(last) > monitorInterval * 3;
    if (resumedFromSleep) {
      _logger.info('The system resumed from sleep (${now.difference(last).inMinutes} min without tick)');
    }
    return check(
      reason: resumedFromSleep ? 'resumed from sleep' : 'periodic',
      thorough: resumedFromSleep,
      force: true,
    );
  }

  /// Checks every service and repairs only what is broken.
  ///
  /// - [thorough]: the discovery sockets are rebound even if the network
  ///   looks unchanged (after a system sleep).
  /// - [announce]: this device is announced again (after a long background
  ///   stay, so that the other devices list it again).
  /// - [force]: ignores [minCheckInterval].
  ///
  /// Returns whether something was restarted.
  Future<bool> check({required String reason, required bool thorough, bool announce = false, bool force = false}) async {
    final now = _clock();
    final last = _lastCheck;
    if (_checking || (!force && !thorough && last != null && now.difference(last) < minCheckInterval)) {
      return false;
    }
    _checking = true;
    _lastCheck = now;
    try {
      final networkChanged = await _checkNetwork();
      final serverRestarted = await _ensureServer(reason);

      var discoveryRestarted = false;
      if (thorough || networkChanged) {
        _logger.info('Rebinding the discovery sockets ($reason${networkChanged ? ', network changed' : ''})');
        _services.restartDiscovery();
        discoveryRestarted = true;
      } else if (announce || serverRestarted) {
        _services.announce();
      }

      final restarted = serverRestarted || discoveryRestarted;
      if (restarted) {
        _services.onReceptionRestarted();
      }
      return restarted;
    } catch (e, st) {
      _logger.warning('Reception health check failed ($reason)', e, st);
      return false;
    } finally {
      _checking = false;
    }
  }

  Future<bool> _checkNetwork() async {
    final fingerprint = await _services.networkFingerprint();
    final previous = _networkFingerprint;
    _networkFingerprint = fingerprint;
    if (previous == null || previous == fingerprint) {
      return false;
    }
    _logger.info('Network changed: [$previous] -> [$fingerprint]');
    _services.onNetworkChanged();
    return true;
  }

  /// Restarts the server if it should run but does not answer.
  Future<bool> _ensureServer(String reason) async {
    switch (_services.serverStatus) {
      case ReceiveServerStatus.busy:
        // Never cut a transfer or a share link.
        return false;
      case ReceiveServerStatus.stopped:
        if (!_services.serverShouldRun) {
          return false;
        }
        _logger.warning('The receive server is not running although it should ($reason), starting it');
        await _services.restartServer();
        return true;
      case ReceiveServerStatus.idle:
        if (await _services.probeServer()) {
          return false;
        }
        // One more try: a single failure may be a hiccup.
        await Future<void>.delayed(_probeRetryDelay);
        if (await _services.probeServer()) {
          return false;
        }
        _logger.warning('The receive server does not answer anymore ($reason), restarting it');
        await _services.restartServer();
        return true;
    }
  }

  Future<bool> _recoverMobile() async {
    var restarted = false;

    // The receive server, unless a transfer or a share link is in progress
    // (restarting would cut it).
    if (_services.serverStatus == ReceiveServerStatus.idle) {
      try {
        _logger.info('Back from the background: restarting the receive server');
        await _services.restartServer();
        restarted = true;
      } catch (e) {
        _logger.warning('Could not restart the receive server', e);
      }
    }

    // The discovery sockets: rebinding them also announces this device on
    // the network again, so the other devices find it right away.
    try {
      _services.restartDiscovery();
      restarted = true;
    } catch (e) {
      _logger.warning('Could not restart the discovery listener', e);
    }
    return restarted;
  }
}

class _RefenaReceiveServices implements ReceiveServices {
  final Ref _ref;

  _RefenaReceiveServices(this._ref);

  @override
  ReceiveServerStatus get serverStatus {
    final server = _ref.read(serverProvider);
    if (server == null) {
      return ReceiveServerStatus.stopped;
    }
    final session = server.session;
    final transferring = session != null && (session.status == SessionStatus.waiting || session.status == SessionStatus.sending);
    if (server.webSendState != null || transferring) {
      return ReceiveServerStatus.busy;
    }
    return ReceiveServerStatus.idle;
  }

  @override
  bool get serverShouldRun => _ref.notifier(serverProvider).shouldRun;

  @override
  Future<bool> probeServer() async {
    final server = _ref.read(serverProvider);
    if (server == null) {
      return false;
    }
    return probeLocalServer(port: server.port, https: server.https);
  }

  @override
  Future<void> restartServer() async {
    await _ref.notifier(serverProvider).recoverServer();
  }

  @override
  Future<String> networkFingerprint() async {
    final settings = _ref.read(settingsProvider);
    final interfaces = await getNetworkInterfaces(
      whitelist: settings.networkWhitelist,
      blacklist: settings.networkBlacklist,
      log: false,
    );
    return networkInterfacesFingerprint(interfaces);
  }

  @override
  void onNetworkChanged() {
    // Windows has no connectivity listener (see InitLocalIpAction).
    // ignore: discarded_futures
    _ref.redux(localIpProvider).dispatchAsync(FetchLocalIpAction());
    _ref.redux(nearbyDevicesProvider).dispatch(ClearFoundDevicesAction());
  }

  @override
  void restartDiscovery() {
    _ref.redux(parentIsolateProvider).dispatch(IsolateSendMulticastRestartListenerAction());
  }

  @override
  void announce() {
    _ref.redux(nearbyDevicesProvider).dispatch(StartMulticastScan());
  }

  @override
  void onReceptionRestarted() {
    _ref.notifier(chatProvider).retryLinksNow();
  }
}

/// Whether the receive server answers on the loopback interface.
///
/// Any HTTP response proves that the listener accepts and serves
/// connections; only the absence of an answer means it is dead. Nothing is
/// sent but a request for the public device info, so the certificate is not
/// checked (the request never leaves this machine).
Future<bool> probeLocalServer({
  required int port,
  required bool https,
  Duration timeout = const Duration(seconds: 3),
}) async {
  final client = HttpClient()
    ..connectionTimeout = timeout
    ..badCertificateCallback = (cert, host, p) => host == '127.0.0.1' && p == port;
  try {
    final uri = Uri.parse(ApiRoute.info.targetRaw('127.0.0.1', port, https, protocolVersion));
    final request = await client.getUrl(uri).timeout(timeout);
    final response = await request.close().timeout(timeout);
    await response.drain<void>().timeout(timeout);
    return true;
  } catch (e) {
    _logger.info('The receive server did not answer on 127.0.0.1:$port', e);
    return false;
  } finally {
    client.close(force: true);
  }
}
