import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:localsend_isolates/constants.dart';
import 'package:localsend_isolates/isolate.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/model/dto/multicast_dto.dart';
import 'package:localsend_isolates/src/isolate/child/http_provider.dart';
import 'package:localsend_isolates/util/network_interfaces.dart';
import 'package:localsend_isolates/util/rust.dart';
import 'package:localsend_isolates/util/sleep.dart';
import 'package:logging/logging.dart';
import 'package:refena_flutter/refena_flutter.dart';

final _logger = Logger('Multicast');

final multicastDiscoveryProvider = Provider((ref) {
  return MulticastService(ref);
});

class MulticastService {
  MulticastService(this._ref);

  /// How often the bound network interfaces are compared with the current ones.
  /// Desktops are never suspended, so they rely on this check alone to follow
  /// Wi-Fi reconnections, network changes and sleep/resume cycles.
  static final Duration watchInterval = Platform.isAndroid || Platform.isIOS ? const Duration(seconds: 30) : const Duration(seconds: 15);

  final Ref _ref;
  Completer<void> _cancelCompleter = Completer();
  bool _listening = false;

  /// Binds the UDP port and listen to UDP multicast packages
  /// It will automatically answer announcement messages
  ///
  /// The sockets are rebound automatically when:
  /// - the network interfaces change (Wi-Fi reconnected, new network, new IP,
  ///   or no network at all when the app started, e.g. autostart on login),
  /// - the system resumed from sleep (Windows drops multicast memberships),
  /// - a socket was closed by the OS.
  Stream<Device> startListener() async* {
    if (_listening) {
      _logger.info('Already listening to multicast');
      return;
    }

    _listening = true;

    while (true) {
      final streamController = StreamController<Device>();
      final syncState = _ref.read(syncProvider);

      final interfaces = await getNetworkInterfaces(
        whitelist: syncState.networkWhitelist,
        blacklist: syncState.networkBlacklist,
      );
      final boundFingerprint = networkInterfacesFingerprint(interfaces);
      final sockets = await _bindSockets(
        interfaces: interfaces,
        multicastGroup: syncState.multicastGroup,
        port: syncState.port,
      );

      // Local to this binding: events of sockets that were closed on purpose
      // must never restart the next binding.
      final cancel = Completer<void>();
      _cancelCompleter = cancel;

      for (final socket in sockets) {
        socket.socket.listen(
          (event) {
            switch (event) {
              case RawSocketEvent.read:
                _onReadable(socket.socket, streamController);
                break;
              case RawSocketEvent.closed:
              case RawSocketEvent.readClosed:
                if (!cancel.isCompleted) {
                  _logger.warning('UDP multicast socket closed by the system (${_describe(socket.interface)}), rebinding');
                  cancel.complete();
                }
                break;
              default:
                break;
            }
          },
          onError: (Object e) {
            // Windows reports ICMP "port unreachable" replies to earlier sends
            // as WSAECONNRESET on the next read. The socket is still usable:
            // never let it kill the listener (or the isolate).
            _logger.warning('UDP multicast socket error (${_describe(socket.interface)})', e);
          },
          cancelOnError: false,
        );
        _logger.info(
          'Bind UDP multicast port (ip: ${socket.interface.addresses.map((a) => a.address).toList()}, group: ${syncState.multicastGroup}, port: ${syncState.port})',
        );
      }

      if (sockets.isEmpty) {
        _logger.warning('No network interface to listen on yet, waiting for a network');
      } else {
        // Tell everyone in the network that I am online
        sendAnnouncement(); // ignore: unawaited_futures
      }

      final watcher = _watchNetwork(boundFingerprint, cancel);

      // ignore: unawaited_futures
      cancel.future.then((_) {
        watcher.cancel();
        // ignore: discarded_futures
        streamController.close();
        for (final socket in sockets) {
          socket.socket.close();
        }
      });

      yield* streamController.stream;

      // streamController is closed because of cancel
      // wait for resources to be released (it works without on macOS, but who knows)
      await sleepAsync(500);
    }
  }

  /// Rebinds the sockets (also announces this device again).
  void restartListener() {
    _logger.info('Restarting the multicast listener on request');
    _restart();
  }

  void _restart() {
    if (!_cancelCompleter.isCompleted) {
      _cancelCompleter.complete();
    }
  }

  void _onReadable(RawDatagramSocket socket, StreamController<Device> streamController) {
    while (true) {
      final datagram = socket.receive();
      if (datagram == null) {
        return;
      }

      // Read fresh: the port, protocol and server state change at runtime.
      final syncState = _ref.read(syncProvider);
      try {
        final dto = MulticastDto.fromJson(jsonDecode(utf8.decode(datagram.data)));
        if (dto.fingerprint == syncState.securityContext.certificateHash) {
          continue;
        }

        final ip = datagram.address.address;
        final peer = dto.toDevice(ip, syncState.port, syncState.protocol == ProtocolType.https);
        if (!streamController.isClosed) {
          streamController.add(peer);
        }
        if ((dto.announcement == true || dto.announce == true) && syncState.serverRunning) {
          // only respond when server is running
          // ignore: discarded_futures
          _answerAnnouncement(peer);
        }
      } catch (e) {
        _logger.warning('Could not parse multicast message', e);
      }
    }
  }

  /// Periodically compares the network interfaces with the ones the sockets
  /// are bound to, and detects a resume from sleep (the timer fires late).
  /// Only rebinds when something actually changed.
  Timer _watchNetwork(String boundFingerprint, Completer<void> cancel) {
    var lastTick = DateTime.now();
    var checking = false;
    return Timer.periodic(watchInterval, (_) async {
      if (checking || cancel.isCompleted) {
        return;
      }
      checking = true;
      try {
        final now = DateTime.now();
        final sinceLastTick = now.difference(lastTick);
        lastTick = now;
        if (sinceLastTick > watchInterval * 3) {
          _logger.info('Resumed from sleep (timer late by ${sinceLastTick.inSeconds}s), rebinding multicast sockets');
          cancel.complete();
          return;
        }

        final syncState = _ref.read(syncProvider);
        final current = networkInterfacesFingerprint(
          await getNetworkInterfaces(
            whitelist: syncState.networkWhitelist,
            blacklist: syncState.networkBlacklist,
            log: false,
          ),
        );
        if (current != boundFingerprint && !cancel.isCompleted) {
          _logger.info('Network interfaces changed ($boundFingerprint -> $current), rebinding multicast sockets');
          cancel.complete();
        }
      } catch (e) {
        _logger.warning('Could not check the network interfaces', e);
      } finally {
        checking = false;
      }
    });
  }

  /// Sends an announcement which triggers a response on every LocalSend member of the network.
  Future<void> sendAnnouncement() async {
    final syncState = _ref.read(syncProvider);
    final sockets = await _getSockets(
      whitelist: syncState.networkWhitelist,
      blacklist: syncState.networkBlacklist,
      multicastGroup: syncState.multicastGroup,
    );
    final dto = _getMulticastDto(announcement: true);
    try {
      // The sockets are kept open for all the attempts: closing them after
      // the first one made the two retries fail silently.
      for (final wait in [100, 500, 2000]) {
        await sleepAsync(wait);

        _logger.info('Announce via UDP');
        for (final socket in sockets) {
          try {
            socket.socket.send(dto, InternetAddress(syncState.multicastGroup), syncState.port);
          } catch (e) {
            _logger.warning('Could not send multicast message (${_describe(socket.interface)})', e);
          }
        }
      }
    } finally {
      for (final socket in sockets) {
        socket.socket.close();
      }
    }
  }

  /// Responds to an announcement.
  Future<void> _answerAnnouncement(Device peer) async {
    try {
      // Answer with TCP
      await _ref
          .read(httpProvider)
          .discovery
          .register(
            protocol: peer.getProtocolType(),
            ip: peer.ip!,
            port: peer.port,
            payload: _ref.read(syncProvider).toRegisterDto(),
          );
      _logger.info('Respond to announcement of ${peer.alias} (${peer.ip}, model: ${peer.deviceModel}) via TCP');
    } catch (e) {
      // Fallback: Answer with UDP
      final syncState = _ref.read(syncProvider);
      final sockets = await _getSockets(
        whitelist: syncState.networkWhitelist,
        blacklist: syncState.networkBlacklist,
        multicastGroup: syncState.multicastGroup,
      );
      final dto = _getMulticastDto(announcement: false);
      for (final socket in sockets) {
        try {
          socket.socket.send(dto, InternetAddress(syncState.multicastGroup), syncState.port);
          socket.socket.close();
        } catch (e) {
          _logger.warning('Could not send multicast message', e);
        }
      }
      _logger.info('Respond to announcement of ${peer.alias} (${peer.ip}, model: ${peer.deviceModel}) with UDP because TCP failed');
    }
  }

  /// Returns the MulticastDto of this device in bytes.
  List<int> _getMulticastDto({required bool announcement}) {
    final syncState = _ref.read(syncProvider);
    final dto = MulticastDto(
      alias: syncState.alias,
      version: protocolVersion,
      deviceModel: syncState.deviceInfo.deviceModel,
      deviceType: syncState.deviceInfo.deviceType,
      fingerprint: syncState.securityContext.certificateHash,
      port: syncState.port,
      protocol: syncState.protocol,
      download: syncState.download,
      announcement: announcement,
      announce: announcement,
    );
    return utf8.encode(jsonEncode(dto.toJson()));
  }
}

class _SocketResult {
  final NetworkInterface interface;
  final RawDatagramSocket socket;

  _SocketResult(this.interface, this.socket);
}

Future<List<_SocketResult>> _getSockets({
  required List<String>? whitelist,
  required List<String>? blacklist,
  required String multicastGroup,
  int? port,
}) async {
  final interfaces = await getNetworkInterfaces(
    whitelist: whitelist,
    blacklist: blacklist,
  );
  return _bindSockets(interfaces: interfaces, multicastGroup: multicastGroup, port: port);
}

Future<List<_SocketResult>> _bindSockets({
  required List<NetworkInterface> interfaces,
  required String multicastGroup,
  int? port,
}) async {
  final sockets = <_SocketResult>[];
  for (final interface in interfaces) {
    try {
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port ?? 0);
      try {
        socket.joinMulticast(InternetAddress(multicastGroup), interface);
      } catch (_) {
        socket.close();
        rethrow;
      }
      sockets.add(_SocketResult(interface, socket));
    } catch (e) {
      _logger.warning(
        'Could not bind UDP multicast port (ip: ${interface.addresses.map((a) => a.address).toList()}, group: $multicastGroup, port: $port)',
        e,
      );
    }
  }

  return sockets;
}

String _describe(NetworkInterface interface) => '${interface.name}: ${interface.addresses.map((a) => a.address).join(', ')}';
