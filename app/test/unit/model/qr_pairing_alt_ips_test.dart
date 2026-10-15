import 'dart:convert';

import 'package:localsend_app/model/qr_pairing_payload.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:test/test.dart';

QrPairingPayload _payload({String ip = '192.168.1.20', List<String> altIps = const []}) {
  return QrPairingPayload.generate(
    protocolVersion: '2.1',
    alias: 'Téléphone',
    deviceModel: 'Pixel',
    deviceType: DeviceType.mobile,
    ip: ip,
    port: 53317,
    https: true,
    fingerprint: 'abc',
    wifiSsid: 'DIRECT-aika',
    wifiPassphrase: 'secret123',
    altIps: altIps,
  );
}

void main() {
  group('alternative addresses', () {
    test('survive encoding, primary address first, no duplicates', () {
      final encoded = _payload(altIps: ['10.0.0.5', '192.168.1.20', '10.0.0.5', '192.168.43.1']).encode();
      final decoded = QrPairingPayload.tryDecode(encoded).payload!;
      expect(decoded.ip, '192.168.1.20');
      expect(decoded.altIps, ['10.0.0.5', '192.168.43.1']);
      expect(decoded.candidateIps, ['192.168.1.20', '10.0.0.5', '192.168.43.1']);
      expect(decoded.wifiSsid, 'DIRECT-aika');
    });

    test('are limited so the code stays easy to scan', () {
      final payload = _payload(altIps: [for (var i = 2; i < 20; i++) '10.0.0.$i']);
      expect(payload.altIps.length, qrPairingMaxAltIps);
    });

    test('older codes without the field still work', () {
      final json = jsonDecode(_payload().encode()) as Map<String, dynamic>..remove('ips');
      final decoded = QrPairingPayload.tryDecode(jsonEncode(json)).payload!;
      expect(decoded.altIps, isEmpty);
      expect(decoded.candidateIps, ['192.168.1.20']);
    });

    test('host names are never accepted (only IP addresses)', () {
      final json = jsonDecode(_payload(altIps: ['10.0.0.5']).encode()) as Map<String, dynamic>;
      json['ips'] = ['evil.example', '10.0.0.6', 42];
      final decoded = QrPairingPayload.tryDecode(jsonEncode(json)).payload!;
      expect(decoded.altIps, ['10.0.0.6']);

      json['ip'] = 'evil.example';
      expect(QrPairingPayload.tryDecode(jsonEncode(json)).error, QrPairingError.malformed);
    });
  });

  group('hotspot security', () {
    test('WPA3 is carried so the scanner joins with the right security', () {
      final payload = QrPairingPayload.generate(
        protocolVersion: '2.1',
        alias: 'A',
        deviceModel: null,
        deviceType: DeviceType.mobile,
        ip: '10.0.0.1',
        port: 53317,
        https: true,
        fingerprint: 'f',
        wifiSsid: 'AndroidShare_1234',
        wifiPassphrase: 'pw',
        wifiSecurity: 'wpa3',
      );
      expect(QrPairingPayload.tryDecode(payload.encode()).payload!.wifiSecurity, 'wpa3');
    });

    test('unknown or missing values mean WPA2', () {
      final json = jsonDecode(_payload().encode()) as Map<String, dynamic>;
      expect(QrPairingPayload.tryDecode(jsonEncode(json)).payload!.wifiSecurity, isNull);
      json['wifiSecurity'] = 'wep';
      expect(QrPairingPayload.tryDecode(jsonEncode(json)).payload!.wifiSecurity, isNull);
    });
  });
}
