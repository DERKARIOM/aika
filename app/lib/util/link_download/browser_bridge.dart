import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Port of the browser bridge, also written in the extension
/// (`browser_extension/background.js`). Different from the LocalSend
/// transfer port (53317).
const browserBridgePort = 53319;

/// Version of the small HTTP API spoken with the extension.
const browserBridgeApi = 1;

const _maxBodyBytes = 16 * 1024;
const _maxDrainBytes = 1024 * 1024;
const _tokenAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // No 0/O, 1/I.

/// Origins of browser extensions (Chrome, Edge, Firefox). Requests from web
/// pages carry an `https://…` origin and are refused.
final _extensionOrigin = RegExp(r'^(chrome-extension|moz-extension|extension)://[a-z0-9-]+$', caseSensitive: false);

/// New random pairing code shown in Aika and typed once in the extension,
/// e.g. `K7QM-29XD-HC4T-PW8N`.
String generateBridgeToken() {
  final random = Random.secure();
  final chars = List.generate(16, (_) => _tokenAlphabet[random.nextInt(_tokenAlphabet.length)]);
  return [for (var i = 0; i < 16; i += 4) chars.sublist(i, i + 4).join()].join('-');
}

/// `k7qm 29xd-hc4t…` → `K7QM29XDHC4T…` (dashes, spaces and case ignored).
String normalizeBridgeToken(String token) => token.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

/// A download handed over by the browser extension.
class BridgeDownloadRequest {
  /// Final link of the file, after the browser followed the redirections.
  final Uri url;

  /// File name chosen by the browser, when already known.
  final String? fileName;

  /// Size announced to the browser, when known.
  final int? size;

  const BridgeDownloadRequest({required this.url, this.fileName, this.size});
}

/// Answer sent back to the extension.
class BridgeAnswer {
  final int status;
  final Map<String, Object?> body;

  const BridgeAnswer(this.status, this.body);
}

/// Local receiver for the "Aika" browser extension (computers only):
/// when the user clicks a download in Chrome / Edge, the extension sends
/// the file's link here and Aika downloads it instead of the browser.
///
/// Security:
/// - listens on 127.0.0.1 only: unreachable from the network;
/// - checks the `Host` header (blocks DNS-rebinding pages);
/// - refuses every request with a web-page `Origin` and never answers CORS
///   pre-flights, so no website can call it from the browser;
/// - requires the pairing code ([token]) in `X-Aika-Token`, compared in
///   constant time;
/// - only receives a link: cookies or credentials are never accepted, and
///   the link then goes through Aika's usual checks (no local address,
///   verified redirections, ...).
class BrowserBridgeServer {
  final String Function() token;
  final Future<BridgeAnswer> Function(BridgeDownloadRequest request) onDownload;
  HttpServer? _server;

  BrowserBridgeServer({required this.token, required this.onDownload});

  bool get running => _server != null;
  int? get port => _server?.port;

  /// Throws a [SocketException] when the port is already taken.
  Future<void> start({int port = browserBridgePort}) async {
    if (_server != null) {
      return;
    }
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    server.defaultResponseHeaders.clear();
    server.listen((request) => unawaited(_handle(request).catchError((Object _) {})));
    _server = server;
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    try {
      final origin = request.headers.value('origin');
      if (origin != null && !_extensionOrigin.hasMatch(origin)) {
        return await _send(response, HttpStatus.forbidden, {'error': 'origin'});
      }
      if (!_isLocalHost(request.headers.value(HttpHeaders.hostHeader))) {
        return await _send(response, HttpStatus.forbidden, {'error': 'host'});
      }
      if (request.method == 'OPTIONS') {
        return await _send(response, HttpStatus.methodNotAllowed, {'error': 'method'});
      }
      if (!_tokenMatches(request.headers.value('x-aika-token'))) {
        return await _send(response, HttpStatus.unauthorized, {'error': 'token'});
      }

      switch ((request.method, request.uri.path)) {
        case ('GET', '/aika/ping'):
          return await _send(response, HttpStatus.ok, {'app': 'aika', 'api': browserBridgeApi});
        case ('POST', '/aika/download'):
          final download = await _readDownload(request);
          if (download == null) {
            return await _send(response, HttpStatus.badRequest, {'error': 'request'});
          }
          final answer = await onDownload(download);
          return await _send(response, answer.status, answer.body);
      }
      await _send(response, HttpStatus.notFound, {'error': 'path'});
    } catch (_) {
      await _send(response, HttpStatus.internalServerError, {'error': 'internal'});
    }
  }

  bool _isLocalHost(String? host) {
    final port = _server?.port;
    return host == '127.0.0.1:$port' || host == 'localhost:$port';
  }

  bool _tokenMatches(String? received) {
    final expected = normalizeBridgeToken(token());
    final given = normalizeBridgeToken(received ?? '');
    if (expected.isEmpty || given.length != expected.length) {
      return false;
    }
    var diff = 0;
    for (var i = 0; i < expected.length; i++) {
      diff |= expected.codeUnitAt(i) ^ given.codeUnitAt(i);
    }
    return diff == 0;
  }

  Future<BridgeDownloadRequest?> _readDownload(HttpRequest request) async {
    final bytes = <int>[];
    var total = 0;
    await for (final chunk in request.timeout(const Duration(seconds: 10))) {
      total += chunk.length;
      if (total > _maxDrainBytes) {
        return null; // Abusive request: stop reading.
      }
      if (total <= _maxBodyBytes) {
        bytes.addAll(chunk);
      }
      // Too large: the rest is read and dropped so the client receives a
      // clean "400" instead of a reset connection.
    }
    if (total > _maxBodyBytes) {
      return null;
    }
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      return null;
    }
    if (json is! Map<String, dynamic>) {
      return null;
    }
    final url = json['url'];
    final uri = url is String && url.length <= 8192 ? Uri.tryParse(url) : null;
    if (uri == null) {
      return null;
    }
    final fileName = json['fileName'];
    final size = json['size'];
    return BridgeDownloadRequest(
      url: uri,
      fileName: fileName is String && fileName.isNotEmpty && fileName.length <= 512 ? fileName : null,
      size: size is int && size > 0 ? size : null,
    );
  }

  Future<void> _send(HttpResponse response, int status, Map<String, Object?> body) async {
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    response.headers.set('cache-control', 'no-store');
    response.write(jsonEncode(body));
    await response.close();
  }
}
