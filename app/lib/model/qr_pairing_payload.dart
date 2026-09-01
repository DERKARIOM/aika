import 'dart:convert';

import 'package:localsend_isolates/model/device.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Schema version of the QR pairing payload.
/// Bump this whenever the payload shape changes in a way that is not
/// backwards-compatible, and branch on it in [QrPairingPayload.tryDecode].
const qrPairingSchemaVersion = 1;

/// Magic marker embedded in every QR pairing payload.
///
/// It lets us cheaply recognize (and reject) a QR code that is not an Aika
/// pairing code (e.g. a URL, a Wi-Fi QR code, ...) before trying to
/// interpret its fields, and to give the user a clear error message instead
/// of a confusing crash.
const _qrPairingMagic = 'aika.pair';

/// Default lifetime of a freshly generated pairing QR code.
/// Kept short on purpose: the code is meant to be scanned right away by a
/// device that is physically next to the emitter.
const qrPairingDefaultTtl = Duration(minutes: 5);

/// Selectable lifetimes offered to the user on the "Generate QR code" screen.
const qrPairingTtlOptions = <Duration>[
  Duration(minutes: 1),
  Duration(minutes: 5),
  Duration(minutes: 15),
  Duration(hours: 1),
];

/// Why a scanned QR code was rejected before even attempting a connection.
enum QrPairingError {
  /// The scanned content is not a valid Aika pairing QR code at all
  /// (wrong format, foreign QR code, corrupted data, ...).
  malformed,

  /// The payload was produced by a version of Aika that this app does not
  /// understand (schema mismatch).
  unsupportedVersion,

  /// The code is well-formed but its `expiresAt` timestamp is in the past.
  expired,
}

/// Result of [QrPairingPayload.tryDecode]: either a valid [payload], or an
/// [error] explaining why it was rejected.
class QrPairingDecodeResult {
  final QrPairingPayload? payload;
  final QrPairingError? error;

  const QrPairingDecodeResult._({this.payload, this.error});

  factory QrPairingDecodeResult.success(QrPairingPayload payload) => QrPairingDecodeResult._(payload: payload);

  factory QrPairingDecodeResult.failure(QrPairingError error) => QrPairingDecodeResult._(error: error);

  bool get isSuccess => payload != null;
}

/// The data encoded inside an Aika "Smart QR Code" pairing code.
///
/// Design notes (see also the "QR Code intelligent" feature documentation):
/// - It only contains what a user would otherwise type by hand in "Manual
///   sending" ([alias], [ip], [port], [https]), plus enough context
///   ([deviceModel], [deviceType], [protocolVersion]) to show a meaningful
///   confirmation screen and to fail fast on an incompatible peer.
/// - [fingerprint] is the SHA-256 fingerprint of the emitter's TLS
///   certificate. It is the actual trust anchor of this feature: once the
///   scanning device connects to [ip]:[port], it compares the fingerprint
///   returned by the live TLS handshake / register response against this
///   value. A mismatch means the device answering at that address is NOT
///   the one that generated the QR code (e.g. the IP was reassigned to
///   another device, or a spoofing attempt), and the pairing is refused.
///   This is exactly the trust model Aika already uses for "Favorites".
/// - [issuedAt] / [expiresAt] let the scanning device reject a stale code
///   (an old screenshot, a printed code left lying around, ...) without
///   even attempting a network connection.
///
/// There is intentionally **no cryptographic signature field**. A signature
/// computed from data that is fully visible inside the QR code cannot prove
/// anything to a third party: the "secret" needed to verify it would have
/// to travel inside the same QR code, so anyone can recompute it. Real
/// authenticity is guaranteed by the live [fingerprint] check above, not by
/// a checksum. Adding one would only create a false sense of security.
///
/// [wifiSsid] / [wifiPassphrase] are a deliberately narrow exception to "only what's
/// needed to reach the device": they are populated *only* when [ip]/[port] belong to a
/// local-only Wi-Fi hotspot Aika itself just created for this pairing (never the user's
/// regular Wi-Fi network), so a second device with no network of its own can join it
/// automatically instead of the user typing the SSID/password by hand. This adds no new
/// exposure versus the emitter's screen, which already shows both in plain text next to
/// the QR code; it inherits the same TTL-based expiry as everything else in this payload.
class QrPairingPayload {
  /// Random identifier for this particular QR code, regenerated every time
  /// the user (re)generates a code. Only used client-side for correlation.
  final String pairId;

  /// LocalSend wire protocol version (e.g. "2.1"), not the schema version.
  final String protocolVersion;

  final String alias;
  final String? deviceModel;
  final DeviceType deviceType;

  final String ip;
  final int port;
  final bool https;

  /// SHA-256 fingerprint (hex) of the emitter's certificate at generation time.
  final String fingerprint;

  final DateTime issuedAt;
  final DateTime expiresAt;

  /// SSID of a local-only hotspot the emitter created for this pairing, if any. Never the
  /// user's regular/personal Wi-Fi network — see the class doc for the scoping rationale.
  final String? wifiSsid;

  /// Passphrase of the hotspot named by [wifiSsid], if any.
  final String? wifiPassphrase;

  const QrPairingPayload({
    required this.pairId,
    required this.protocolVersion,
    required this.alias,
    required this.deviceModel,
    required this.deviceType,
    required this.ip,
    required this.port,
    required this.https,
    required this.fingerprint,
    required this.issuedAt,
    required this.expiresAt,
    this.wifiSsid,
    this.wifiPassphrase,
  });

  /// Builds a fresh payload for the current device, valid for [ttl].
  factory QrPairingPayload.generate({
    required String protocolVersion,
    required String alias,
    required String? deviceModel,
    required DeviceType deviceType,
    required String ip,
    required int port,
    required bool https,
    required String fingerprint,
    Duration ttl = qrPairingDefaultTtl,
    String? wifiSsid,
    String? wifiPassphrase,
  }) {
    final now = DateTime.now();
    return QrPairingPayload(
      pairId: _uuid.v4(),
      protocolVersion: protocolVersion,
      alias: alias,
      deviceModel: deviceModel,
      deviceType: deviceType,
      ip: ip,
      port: port,
      https: https,
      fingerprint: fingerprint,
      issuedAt: now,
      expiresAt: now.add(ttl),
      wifiSsid: wifiSsid,
      wifiPassphrase: wifiPassphrase,
    );
  }

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  Duration get remaining {
    final diff = expiresAt.difference(DateTime.now());
    return diff.isNegative ? Duration.zero : diff;
  }

  /// Encodes this payload as compact JSON, ready to be embedded in a QR code.
  String encode() {
    return jsonEncode({
      'kind': _qrPairingMagic,
      'schema': qrPairingSchemaVersion,
      'pairId': pairId,
      'protocolVersion': protocolVersion,
      'alias': alias,
      'deviceModel': deviceModel,
      'deviceType': deviceType.name,
      'ip': ip,
      'port': port,
      'https': https,
      'fingerprint': fingerprint,
      'issuedAt': issuedAt.toUtc().millisecondsSinceEpoch,
      'expiresAt': expiresAt.toUtc().millisecondsSinceEpoch,
      if (wifiSsid != null) 'wifiSsid': wifiSsid,
      if (wifiPassphrase != null) 'wifiPassphrase': wifiPassphrase,
    });
  }

  /// Tries to decode [raw] (the raw string content scanned from a QR code)
  /// into a [QrPairingPayload]. Never throws: any parsing issue is reported
  /// as a [QrPairingDecodeResult.failure].
  static QrPairingDecodeResult tryDecode(String raw) {
    final Map<String, dynamic> json;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return QrPairingDecodeResult.failure(QrPairingError.malformed);
      }
      json = decoded;
    } catch (_) {
      return QrPairingDecodeResult.failure(QrPairingError.malformed);
    }

    if (json['kind'] != _qrPairingMagic) {
      return QrPairingDecodeResult.failure(QrPairingError.malformed);
    }

    final schema = json['schema'];
    if (schema is! int || schema != qrPairingSchemaVersion) {
      return QrPairingDecodeResult.failure(QrPairingError.unsupportedVersion);
    }

    try {
      final deviceTypeName = json['deviceType'] as String?;
      final payload = QrPairingPayload(
        pairId: json['pairId'] as String,
        protocolVersion: json['protocolVersion'] as String,
        alias: json['alias'] as String,
        deviceModel: json['deviceModel'] as String?,
        deviceType: DeviceType.values.firstWhere(
          (e) => e.name == deviceTypeName,
          orElse: () => DeviceType.desktop,
        ),
        ip: json['ip'] as String,
        port: json['port'] as int,
        https: json['https'] as bool,
        fingerprint: json['fingerprint'] as String,
        issuedAt: DateTime.fromMillisecondsSinceEpoch(json['issuedAt'] as int, isUtc: true),
        expiresAt: DateTime.fromMillisecondsSinceEpoch(json['expiresAt'] as int, isUtc: true),
        wifiSsid: json['wifiSsid'] as String?,
        wifiPassphrase: json['wifiPassphrase'] as String?,
      );

      if (payload.isExpired) {
        return QrPairingDecodeResult.failure(QrPairingError.expired);
      }

      return QrPairingDecodeResult.success(payload);
    } catch (_) {
      return QrPairingDecodeResult.failure(QrPairingError.malformed);
    }
  }
}
