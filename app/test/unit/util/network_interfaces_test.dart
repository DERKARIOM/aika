import 'dart:io';

import 'package:localsend_isolates/util/network_interfaces.dart';
import 'package:test/test.dart';

void main() {
  test('Should allow any IP', () {
    ignored(String ip) => isNetworkIgnoredRaw(networkWhitelist: null, networkBlacklist: null, interface: [ip]);

    expect(ignored('1.2.3.4'), false);
    expect(ignored('1::1'), false);
  });

  test('Should only allow explicit whitelisted IP', () {
    ignored(String ip) => isNetworkIgnoredRaw(networkWhitelist: ['2.2.2.3'], networkBlacklist: null, interface: [ip]);

    expect(ignored('2.2.2.2'), true);
    expect(ignored('2.2.2.3'), false);
  });

  test('Should allow wildcard whitelisted IP', () {
    ignored(String ip) => isNetworkIgnoredRaw(networkWhitelist: ['3.3.3.*'], networkBlacklist: null, interface: [ip]);

    expect(ignored('3.3.3.1'), false);
    expect(ignored('3.3.3.2'), false);
    expect(ignored('3.3.4.3'), true);
  });

  test('Should allow wildcard whitelisted ipv6', () {
    ignored(String ip) => isNetworkIgnoredRaw(networkWhitelist: ['1::1:*'], networkBlacklist: null, interface: [ip]);

    expect(ignored('1::1:1'), false);
    expect(ignored('1::1:2'), false);
    expect(ignored('1::2:1'), true);
  });

  test('Should ignore explicit blacklisted IP', () {
    ignored(String ip) => isNetworkIgnoredRaw(networkWhitelist: null, networkBlacklist: ['3.3.3.4'], interface: [ip]);

    expect(ignored('3.3.3.3'), false);
    expect(ignored('3.3.3.4'), true);
  });

  test('Should ignore wildcard blacklisted IP', () {
    ignored(String ip) => isNetworkIgnoredRaw(networkWhitelist: null, networkBlacklist: ['3.3.3.*'], interface: [ip]);

    expect(ignored('3.3.3.3'), true);
    expect(ignored('3.3.3.4'), true);
    expect(ignored('4.3.3.3'), false);
  });

  group('networkFingerprintOf', () {
    List<InternetAddress> ips(List<String> ips) => ips.map((ip) => InternetAddress(ip)).toList();

    test('does not depend on the order of interfaces and addresses', () {
      final a = networkFingerprintOf({
        'wlan0': ips(['192.168.1.10', '10.0.0.2']),
        'eth0': ips(['172.16.0.4']),
      });
      final b = networkFingerprintOf({
        'eth0': ips(['172.16.0.4']),
        'wlan0': ips(['10.0.0.2', '192.168.1.10']),
      });
      expect(a, b);
    });

    test('changes with a new IP, a new interface or no network at all', () {
      final base = networkFingerprintOf({
        'wlan0': ips(['192.168.1.10']),
      });
      expect(
        networkFingerprintOf({
          'wlan0': ips(['192.168.1.11']),
        }),
        isNot(base),
      );
      expect(
        networkFingerprintOf({
          'wlan0': ips(['192.168.1.10']),
          'eth0': ips(['10.0.0.1']),
        }),
        isNot(base),
      );
      expect(networkFingerprintOf({}), isNot(base));
    });

    test('ignores IPv6 addresses (privacy addresses rotate)', () {
      expect(
        networkFingerprintOf({
          'wlan0': ips(['192.168.1.10', 'fe80::1']),
        }),
        networkFingerprintOf({
          'wlan0': ips(['192.168.1.10', 'fe80::2']),
        }),
      );
    });

    test('works on the real interfaces of this machine', () async {
      final interfaces = await NetworkInterface.list();
      expect(networkInterfacesFingerprint(interfaces), networkInterfacesFingerprint(interfaces.reversed));
    });
  });
}
