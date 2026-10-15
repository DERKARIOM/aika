import 'dart:convert';
import 'dart:io';

import 'package:localsend_app/util/link_download/browser_bridge.dart';
import 'package:test/test.dart';

late BrowserBridgeServer _bridge;
late String _base;
const _token = 'K7QM-29XD-HC4T-PW8N';
final _received = <BridgeDownloadRequest>[];

/// Real HTTP request to the bridge on 127.0.0.1.
Future<(int, Map<String, dynamic>)> _call(
  String method,
  String path, {
  String? token = _token,
  String? origin = 'chrome-extension://abcdefghijklmnop',
  String? host,
  Object? body,
  List<int>? rawBody,
}) async {
  final client = HttpClient();
  try {
    final request = await client.openUrl(method, Uri.parse('$_base$path'));
    if (token != null) {
      request.headers.set('x-aika-token', token);
    }
    if (origin != null) {
      request.headers.set('origin', origin);
    }
    if (host != null) {
      request.headers.host = host;
    }
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    } else if (rawBody != null) {
      request.add(rawBody);
    }
    final response = await request.close();
    final text = await utf8.decodeStream(response);
    return (response.statusCode, text.isEmpty ? <String, dynamic>{} : jsonDecode(text) as Map<String, dynamic>);
  } finally {
    client.close(force: true);
  }
}

void main() {
  setUpAll(() async {
    _bridge = BrowserBridgeServer(
      token: () => _token,
      onDownload: (request) async {
        _received.add(request);
        return const BridgeAnswer(202, {'accepted': true});
      },
    );
    await _bridge.start(port: 0);
    _base = 'http://127.0.0.1:${_bridge.port}';
  });

  tearDownAll(() async => _bridge.stop());

  group('pairing code', () {
    test('has the expected format and is random', () {
      final a = generateBridgeToken();
      expect(a, matches(RegExp(r'^[A-Z2-9]{4}-[A-Z2-9]{4}-[A-Z2-9]{4}-[A-Z2-9]{4}$')));
      expect(a, isNot(contains('0')));
      expect(generateBridgeToken(), isNot(a));
    });

    test('ignores dashes, spaces and case', () {
      expect(normalizeBridgeToken('k7qm 29xd-hc4t-pw8n'), 'K7QM29XDHC4TPW8N');
    });
  });

  group('access control', () {
    test('answers the extension with the right code', () async {
      final (status, json) = await _call('GET', '/aika/ping');
      expect(status, 200);
      expect(json['app'], 'aika');
    });

    test('accepts the code typed with spaces or lower case', () async {
      final (status, _) = await _call('GET', '/aika/ping', token: 'k7qm 29xd hc4t pw8n');
      expect(status, 200);
    });

    test('refuses a missing or wrong code', () async {
      expect((await _call('GET', '/aika/ping', token: null)).$1, 401);
      expect((await _call('GET', '/aika/ping', token: 'AAAA-BBBB-CCCC-DDDD')).$1, 401);
    });

    test('refuses web pages, even with the right code', () async {
      expect((await _call('GET', '/aika/ping', origin: 'https://evil.example')).$1, 403);
      expect((await _call('POST', '/aika/download', origin: 'null', body: {'url': 'https://a.example/f.zip'})).$1, 403);
    });

    test('refuses a foreign Host (DNS rebinding)', () async {
      expect((await _call('GET', '/aika/ping', host: 'evil.example')).$1, 403);
    });

    test('never answers CORS pre-flights', () async {
      expect((await _call('OPTIONS', '/aika/download')).$1, 405);
    });

    test('unknown paths', () async {
      expect((await _call('GET', '/nothing')).$1, 404);
    });
  });

  group('downloads', () {
    test('hands the link, name and size to Aika', () async {
      _received.clear();
      final (status, json) = await _call(
        'POST',
        '/aika/download',
        body: {'url': 'https://cdn.example/setup.exe', 'fileName': 'setup.exe', 'size': 1234},
      );
      expect(status, 202);
      expect(json['accepted'], isTrue);
      expect(_received.single.url.toString(), 'https://cdn.example/setup.exe');
      expect(_received.single.fileName, 'setup.exe');
      expect(_received.single.size, 1234);
    });

    test('refuses malformed and oversized requests', () async {
      _received.clear();
      expect((await _call('POST', '/aika/download', rawBody: utf8.encode('not json'))).$1, 400);
      expect((await _call('POST', '/aika/download', body: {'link': 'x'})).$1, 400);
      expect((await _call('POST', '/aika/download', body: [1, 2])).$1, 400);
      expect((await _call('POST', '/aika/download', rawBody: List.filled(20 * 1024, 0x20))).$1, 400);
      expect(_received, isEmpty);
    });

    test('a request without the code never reaches Aika', () async {
      _received.clear();
      await _call('POST', '/aika/download', token: null, body: {'url': 'https://cdn.example/a.zip'});
      expect(_received, isEmpty);
    });
  });
}
