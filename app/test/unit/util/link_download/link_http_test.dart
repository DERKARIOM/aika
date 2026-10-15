import 'dart:async';
import 'dart:io';

import 'package:localsend_app/util/link_download/file_naming.dart';
import 'package:localsend_app/util/link_download/link_http.dart';
import 'package:localsend_app/util/link_download/link_problem.dart';
import 'package:test/test.dart';

/// Real HTTP server on 127.0.0.1: every test downloads real bytes over a
/// real socket (nothing is simulated).
late HttpServer _server;
late String _base;
late Directory _tmp;

final _png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, ...List.filled(2048, 7)];
final _pdf = [...'%PDF-1.7\n'.codeUnits, ...List.filled(4096, 32)];
final _big = List<int>.generate(6 * 1024 * 1024, (i) => i % 251);
const _etag = '"v1"';

/// The link downloader with 127.0.0.1 trusted (the app trusts nothing).
const _http = LinkHttp(trustedHosts: {'127.0.0.1'}, idleTimeout: Duration(seconds: 3));

Matcher _problem(LinkProblem problem) => throwsA(isA<LinkDownloadException>().having((e) => e.problem, 'problem', problem));

Future<void> _serveBytes(HttpRequest request, List<int> bytes, {String? type, bool ranges = false}) async {
  final response = request.response;
  if (type != null) {
    response.headers.contentType = ContentType.parse(type);
  }
  final range = request.headers.value(HttpHeaders.rangeHeader);
  if (ranges) {
    response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    response.headers.set(HttpHeaders.etagHeader, _etag);
  }
  if (ranges && range != null && request.headers.value(HttpHeaders.ifRangeHeader) == _etag) {
    final start = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
    if (start >= bytes.length) {
      response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      await response.close();
      return;
    }
    response.statusCode = HttpStatus.partialContent;
    response.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-${bytes.length - 1}/${bytes.length}');
    response.contentLength = bytes.length - start;
    response.add(bytes.sublist(start));
  } else {
    response.contentLength = bytes.length;
    response.add(bytes);
  }
  await response.close();
}

Future<void> _handle(HttpRequest request) async {
  final response = request.response;
  switch (request.uri.path) {
    case '/image.png':
      return _serveBytes(request, _png, type: 'image/png');
    case '/video.mp4':
      return _serveBytes(request, _big, type: 'video/mp4', ranges: true);
    case '/report':
      response.headers.set('content-disposition', "attachment; filename*=UTF-8''rapport%20%C3%A9t%C3%A9.pdf");
      return _serveBytes(request, _pdf, type: 'application/pdf');
    case '/no-type':
      return _serveBytes(request, _pdf);
    case '/page':
      return _serveBytes(request, '<!doctype html><html><body>Bonjour</body></html>'.codeUnits, type: 'text/html; charset=utf-8');
    case '/page-without-type':
      return _serveBytes(request, '<!DOCTYPE html><html></html>'.codeUnits);
    case '/evil-name':
      response.headers.set('content-disposition', r'attachment; filename="..\..\evil:name?.txt"');
      return _serveBytes(request, 'x'.codeUnits, type: 'text/plain');
    case '/private':
      response.statusCode = HttpStatus.forbidden;
      return response.close();
    case '/expired':
      response.statusCode = HttpStatus.gone;
      return response.close();
    case '/broken':
      response.statusCode = HttpStatus.internalServerError;
      return response.close();
    case '/redirect':
      return response.redirect(Uri.parse('/image.png'), status: HttpStatus.found);
    case '/loop':
      return response.redirect(Uri.parse('/loop'), status: HttpStatus.found);
    case '/to-metadata':
      return response.redirect(Uri.parse('http://169.254.169.254/latest/meta-data'));
    case '/to-localhost':
      return response.redirect(Uri.parse('http://localhost:${_server.port}/image.png'));
    case '/to-youtube':
      return response.redirect(Uri.parse('https://www.youtube.com/watch?v=abc'));
    case '/to-file-scheme':
      response.statusCode = HttpStatus.found;
      response.headers.set(HttpHeaders.locationHeader, 'file:///etc/passwd');
      return response.close();
    case '/drop':
      return _serveDropping(request);
    case '/json':
      final auth = request.headers.value(HttpHeaders.authorizationHeader);
      return _serveBytes(request, '{"name":"build","authorization":${auth == null ? 'null' : '"present"'}}'.codeUnits, type: 'application/json');
    case '/json-list':
      return _serveBytes(request, '[1,2,3]'.codeUnits, type: 'application/json');
    case '/json-huge':
      return _serveBytes(request, List.filled(2 * 1024 * 1024, 0x20), type: 'application/json');
    case '/file-with-auth-check':
      if (request.headers.value(HttpHeaders.authorizationHeader) != null) {
        response.statusCode = HttpStatus.badRequest; // Must never receive the token.
        return response.close();
      }
      return _serveBytes(request, _png, type: 'image/png');
    case '/stall':
      // Headers then silence: used for cancel and timeout.
      response.headers.contentType = ContentType.parse('video/mp4');
      response.contentLength = _big.length;
      response.add(_big.sublist(0, 1024));
      await response.flush();
      await Future<void>.delayed(const Duration(seconds: 30));
      return;
    case '/unknown-size':
      response.headers.contentType = ContentType.parse('application/zip');
      response.bufferOutput = false;
      for (var i = 0; i < 10; i++) {
        response.add(List.filled(100 * 1024, i));
      }
      return response.close();
  }
  response.statusCode = HttpStatus.notFound;
  await response.close();
}

/// Without a Range header: announces the whole file, sends a third of it,
/// then drops the connection (network loss). With a Range: serves the rest.
Future<void> _serveDropping(HttpRequest request) async {
  if (request.headers.value(HttpHeaders.rangeHeader) != null) {
    return _serveBytes(request, _big, type: 'video/mp4', ranges: true);
  }
  final response = request.response;
  response.headers.contentType = ContentType.parse('video/mp4');
  response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
  response.headers.set(HttpHeaders.etagHeader, _etag);
  response.contentLength = _big.length;
  final socket = await response.detachSocket(writeHeaders: true);
  socket.add(_big.sublist(0, _big.length ~/ 3));
  await socket.flush();
  socket.destroy();
}

Uri _url(String path) => Uri.parse('$_base$path');

Future<(int, List<int>)> _download(DirectFileInfo info, {LinkCancelToken? token, int maxBytes = 1 << 40}) async {
  final part = File('${_tmp.path}/${DateTime.now().microsecondsSinceEpoch}.part');
  final size = await _http.download(info: info, partFile: part, cancelToken: token ?? LinkCancelToken(), onProgress: (_, _) {}, maxBytes: maxBytes);
  return (size, await part.readAsBytes());
}

void main() {
  setUpAll(() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _base = 'http://127.0.0.1:${_server.port}';
    // No default Content-Type, so "file without type" cases are real.
    _server.defaultResponseHeaders.clear();
    // The client often closes a connection on purpose (analysis reads only the
    // headers, cancel, network loss): the server's write errors are expected.
    _server.listen((request) => unawaited(_handle(request).catchError((Object _) {})));
    _tmp = await Directory.systemTemp.createTemp('aika_link_test');
  });

  tearDownAll(() async {
    await _server.close(force: true);
    await _tmp.delete(recursive: true);
  });

  group('analyze', () {
    test('direct image link', () async {
      final info = await _http.analyze(_url('/image.png'));
      expect(info.fileName, 'image.png');
      expect(info.mimeType, 'image/png');
      expect(info.kind, LinkMediaKind.image);
      expect(info.size, _png.length);
    });

    test('direct video link with resume support', () async {
      final info = await _http.analyze(_url('/video.mp4'));
      expect(info.kind, LinkMediaKind.video);
      expect(info.size, _big.length);
      expect(info.acceptsRanges, isTrue);
      expect(info.etag, _etag);
    });

    test('PDF with a UTF-8 file name from Content-Disposition', () async {
      final info = await _http.analyze(_url('/report'));
      expect(info.fileName, 'rapport été.pdf');
      expect(info.kind, LinkMediaKind.document);
    });

    test('file without Content-Type is recognised by its first bytes', () async {
      final info = await _http.analyze(_url('/no-type'));
      expect(info.mimeType, 'application/pdf');
      expect(info.fileName, 'no-type.pdf');
    });

    test('a web page is not presented as a file', () async {
      await expectLater(_http.analyze(_url('/page')), _problem(LinkProblem.webPageWithoutMedia));
      await expectLater(_http.analyze(_url('/page-without-type')), _problem(LinkProblem.webPageWithoutMedia));
    });

    test('a dangerous server file name is cleaned', () async {
      final info = await _http.analyze(_url('/evil-name'));
      expect(info.fileName, 'evil_name_.txt');
    });

    test('private, expired, missing and broken links', () async {
      await expectLater(_http.analyze(_url('/private')), _problem(LinkProblem.requiresAuth));
      await expectLater(_http.analyze(_url('/expired')), _problem(LinkProblem.notFound));
      await expectLater(_http.analyze(_url('/nothing-here')), _problem(LinkProblem.notFound));
      await expectLater(_http.analyze(_url('/broken')), _problem(LinkProblem.serverError));
    });

    test('follows a normal redirection', () async {
      final info = await _http.analyze(_url('/redirect'));
      expect(info.fileName, 'image.png');
      expect(info.sourceUri.path, '/redirect');
      expect(info.fileUri.path, '/image.png');
    });

    test('stops redirection loops', () async {
      await expectLater(_http.analyze(_url('/loop')), _problem(LinkProblem.tooManyRedirects));
    });

    test('refuses redirections to internal addresses and other schemes', () async {
      await expectLater(_http.analyze(_url('/to-metadata')), _problem(LinkProblem.localAddress));
      await expectLater(_http.analyze(_url('/to-localhost')), _problem(LinkProblem.localAddress));
      await expectLater(_http.analyze(_url('/to-file-scheme')), _problem(LinkProblem.unsupportedScheme));
    });

    test('a redirection to a known platform gets the platform message', () async {
      await expectLater(
        _http.analyze(_url('/to-youtube')),
        throwsA(isA<LinkDownloadException>().having((e) => e.platform, 'platform', 'YouTube')),
      );
    });

    test('the app configuration refuses this device', () async {
      await expectLater(const LinkHttp().analyze(_url('/image.png')), _problem(LinkProblem.localAddress));
    });

    test('an unreachable server is a network problem', () async {
      final closed = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = closed.port;
      await closed.close();
      await expectLater(_http.analyze(Uri.parse('http://127.0.0.1:$port/a.png')), _problem(LinkProblem.network));
    });
  });

  group('download', () {
    test('downloads the exact bytes of an image', () async {
      final (size, bytes) = await _download(await _http.analyze(_url('/image.png')));
      expect(size, _png.length);
      expect(bytes, _png);
    });

    test('streams a large file to disk', () async {
      final (size, bytes) = await _download(await _http.analyze(_url('/video.mp4')));
      expect(size, _big.length);
      expect(bytes, _big);
    });

    test('resumes after a lost connection without corrupting the file', () async {
      final info = await _http.analyze(_url('/drop'));
      final part = File('${_tmp.path}/resume.part');
      final progress = <int>[];

      await expectLater(
        _http.download(info: info, partFile: part, cancelToken: LinkCancelToken(), onProgress: (r, _) => progress.add(r), maxBytes: 1 << 40),
        _problem(LinkProblem.network),
      );
      final partial = part.lengthSync();
      expect(partial, greaterThan(0));
      expect(partial, lessThan(_big.length));

      final size = await _http.download(info: info, partFile: part, cancelToken: LinkCancelToken(), onProgress: (r, _) => progress.add(r), maxBytes: 1 << 40);
      expect(size, _big.length);
      expect(await part.readAsBytes(), _big);
      expect(progress.last, _big.length);
    });

    test('can be cancelled while running', () async {
      final info = await _http.analyze(_url('/stall'));
      final token = LinkCancelToken();
      final part = File('${_tmp.path}/cancel.part');
      final future = _http.download(info: info, partFile: part, cancelToken: token, onProgress: (_, _) {}, maxBytes: 1 << 40);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      token.cancel();
      await expectLater(future, throwsA(predicate<Object>(isLinkDownloadCancelled)));
    });

    test('a stalled server ends with a timeout', () async {
      final info = await _http.analyze(_url('/stall'));
      await expectLater(_download(info), _problem(LinkProblem.timeout));
    });

    test('an unknown size is stopped at the limit', () async {
      final info = await _http.analyze(_url('/unknown-size'));
      expect(info.size, isNull);
      await expectLater(_download(info, maxBytes: 300 * 1024), _problem(LinkProblem.tooLarge));
    });

    test('a known size above the limit is refused before writing', () async {
      final info = await _http.analyze(_url('/video.mp4'));
      await expectLater(_download(info, maxBytes: 1024), _problem(LinkProblem.tooLarge));
    });
  });

  group('official API and credentials', () {
    const auth = LinkAuth(host: '127.0.0.1', authorization: 'Bearer secret-token');

    test('reads a JSON answer', () async {
      final json = await _http.getJson(_url('/json'));
      expect(json['name'], 'build');
    });

    test('refuses non-object and oversized answers', () async {
      await expectLater(_http.getJson(_url('/json-list')), _problem(LinkProblem.serverError));
      await expectLater(_http.getJson(_url('/json-huge')), _problem(LinkProblem.serverError));
    });

    test('maps API errors', () async {
      await expectLater(_http.getJson(_url('/private')), _problem(LinkProblem.requiresAuth));
      await expectLater(_http.getJson(_url('/nothing')), _problem(LinkProblem.notFound));
    });

    test('never sends credentials over plain http', () async {
      final json = await _http.getJson(_url('/json'), auth: auth);
      expect(json['authorization'], isNull);
      final info = await _http.analyze(_url('/file-with-auth-check'), auth: auth);
      expect(info.auth, auth);
      final (size, _) = await _download(info);
      expect(size, _png.length);
    });

    test('credentials are never printed', () {
      expect(auth.toString(), isNot(contains('secret')));
    });
  });
}
