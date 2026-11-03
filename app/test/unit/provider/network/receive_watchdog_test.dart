import 'package:localsend_app/provider/network/receive_watchdog.dart';
import 'package:test/test.dart';

/// Records what the watchdog does, with a scriptable state.
class _FakeServices implements ReceiveServices {
  ReceiveServerStatus status = ReceiveServerStatus.idle;
  bool shouldRun = true;
  List<bool> probeResults = [];
  String fingerprint = 'wlan0=192.168.1.10';

  int probes = 0;
  int serverRestarts = 0;
  int networkChanges = 0;
  int discoveryRestarts = 0;
  int announcements = 0;
  int receptionRestarts = 0;

  @override
  ReceiveServerStatus get serverStatus => status;

  @override
  bool get serverShouldRun => shouldRun;

  @override
  Future<bool> probeServer() async {
    probes++;
    return probeResults.isEmpty ? true : probeResults.removeAt(0);
  }

  @override
  Future<void> restartServer() async {
    serverRestarts++;
    status = ReceiveServerStatus.idle;
  }

  @override
  Future<String> networkFingerprint() async => fingerprint;

  @override
  void onNetworkChanged() => networkChanges++;

  @override
  void restartDiscovery() => discoveryRestarts++;

  @override
  void announce() => announcements++;

  @override
  void onReceptionRestarted() => receptionRestarts++;
}

void main() {
  late _FakeServices services;
  late DateTime now;
  late ReceiveWatchdog watchdog;

  ReceiveWatchdog create({required bool desktop}) => ReceiveWatchdog(
    services,
    clock: () => now,
    desktop: desktop,
    mobile: !desktop,
    probeRetryDelay: Duration.zero,
  );

  setUp(() {
    services = _FakeServices();
    now = DateTime(2026, 11, 3, 10);
    watchdog = create(desktop: true);
  });

  group('desktop', () {
    test('a healthy reception is left alone', () async {
      await watchdog.onTick(); // remembers the network
      now = now.add(ReceiveWatchdog.monitorInterval);

      expect(await watchdog.onTick(), false);
      expect(services.probes, 2);
      expect(services.serverRestarts, 0);
      expect(services.discoveryRestarts, 0);
      expect(services.networkChanges, 0);
    });

    test('a server that does not answer twice is restarted', () async {
      services.probeResults = [false, false];

      expect(await watchdog.onTick(), true);
      expect(services.serverRestarts, 1);
      expect(services.announcements, 1, reason: 'peers learn that we are back');
      expect(services.receptionRestarts, 1);
    });

    test('a single failed probe is a hiccup, not a restart', () async {
      services.probeResults = [false, true];

      expect(await watchdog.onTick(), false);
      expect(services.probes, 2);
      expect(services.serverRestarts, 0);
    });

    test('a transfer in progress is never cut', () async {
      services.status = ReceiveServerStatus.busy;
      services.probeResults = [false, false];

      await watchdog.onTick();
      expect(services.probes, 0);
      expect(services.serverRestarts, 0);
    });

    test('a server that stopped on its own is started again', () async {
      services.status = ReceiveServerStatus.stopped;

      expect(await watchdog.onTick(), true);
      expect(services.serverRestarts, 1);
    });

    test('a server stopped by the user stays stopped', () async {
      services.status = ReceiveServerStatus.stopped;
      services.shouldRun = false;

      expect(await watchdog.onTick(), false);
      expect(services.serverRestarts, 0);
    });

    test('a network change refreshes the IPs and rebinds discovery', () async {
      await watchdog.onTick();
      services.fingerprint = 'wlan0=10.0.0.5';
      now = now.add(ReceiveWatchdog.monitorInterval);

      expect(await watchdog.onTick(), true);
      expect(services.networkChanges, 1);
      expect(services.discoveryRestarts, 1);
      expect(services.serverRestarts, 0, reason: 'the server listens on all interfaces');
    });

    test('a late tick (system sleep) rebinds discovery even on the same network', () async {
      await watchdog.onTick();
      now = now.add(const Duration(hours: 3));

      expect(await watchdog.onTick(), true);
      expect(services.discoveryRestarts, 1);
      expect(services.networkChanges, 0);
    });

    test('returning after a long background stay announces this device', () async {
      watchdog.onBackground();
      now = now.add(const Duration(minutes: 30));

      expect(await watchdog.onResumed(), false);
      expect(services.probes, 1);
      expect(services.announcements, 1);
      expect(services.discoveryRestarts, 0, reason: 'nothing is broken: no blind restart');
    });

    test('quick returns to the foreground are throttled', () async {
      await watchdog.onResumed();
      now = now.add(const Duration(seconds: 2));
      await watchdog.onResumed();
      now = now.add(ReceiveWatchdog.minCheckInterval);
      await watchdog.onResumed();

      expect(services.probes, 2);
    });

    test('repeated minimize / restore cycles never restart anything', () async {
      for (var i = 0; i < 20; i++) {
        watchdog.onBackground();
        now = now.add(const Duration(minutes: 1));
        await watchdog.onResumed();
      }
      expect(services.serverRestarts, 0);
      expect(services.discoveryRestarts, 0);
    });
  });

  group('mobile', () {
    setUp(() => watchdog = create(desktop: false));

    test('short background stays keep their sockets', () async {
      watchdog.onBackground();
      now = now.add(const Duration(seconds: 10));

      expect(await watchdog.onResumed(), false);
      expect(services.serverRestarts, 0);
      expect(services.discoveryRestarts, 0);
    });

    test('a long background stay rebinds the server and discovery', () async {
      watchdog.onBackground();
      now = now.add(const Duration(minutes: 5));

      expect(await watchdog.onResumed(), true);
      expect(services.serverRestarts, 1);
      expect(services.discoveryRestarts, 1);
    });

    test('a transfer in progress is kept after a long background stay', () async {
      services.status = ReceiveServerStatus.busy;
      watchdog.onBackground();
      now = now.add(const Duration(minutes: 5));

      await watchdog.onResumed();
      expect(services.serverRestarts, 0);
      expect(services.discoveryRestarts, 1);
    });

    test('the periodic monitor is desktop only', () {
      watchdog.startMonitoring();
      watchdog.dispose();
      expect(services.probes, 0);
    });
  });
}
