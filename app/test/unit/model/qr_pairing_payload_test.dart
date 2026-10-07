import 'package:localsend_app/model/qr_pairing_payload.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:test/test.dart';

/// The Receive tab shows this payload as its QR code: it must decode on the
/// scanning side exactly as generated, and stay small enough to scan.
void main() {
  QrPairingPayload generate({Duration ttl = qrPairingDefaultTtl}) {
    return QrPairingPayload.generate(
      protocolVersion: '2.1',
      alias: 'Mangue Fraîche',
      deviceModel: 'Samsung',
      deviceType: DeviceType.mobile,
      ip: '192.168.100.124',
      port: 53317,
      https: true,
      fingerprint: 'A3F1' * 16,
      ttl: ttl,
    );
  }

  test('round-trips through the scanner decoder', () {
    final payload = generate();
    final result = QrPairingPayload.tryDecode(payload.encode());

    expect(result.isSuccess, isTrue);
    final decoded = result.payload!;
    expect(decoded.alias, payload.alias);
    expect(decoded.ip, payload.ip);
    expect(decoded.port, payload.port);
    expect(decoded.https, payload.https);
    expect(decoded.fingerprint, payload.fingerprint);
    expect(decoded.deviceType, payload.deviceType);
    expect(decoded.wifiSsid, isNull);
  });

  test('an expired code is refused by the scanner', () {
    final payload = generate(ttl: const Duration(milliseconds: -1));
    expect(QrPairingPayload.tryDecode(payload.encode()).error, QrPairingError.expired);
  });

  test('fits a QR code that phone cameras read reliably', () {
    final qr = QrCode.fromData(data: generate().encode(), errorCorrectLevel: QrErrorCorrectLevel.M);
    // Version 14 = 73 modules: ~3.5 logical px per module at 260 px.
    expect(qr.typeNumber, lessThanOrEqualTo(16));
  });
}
