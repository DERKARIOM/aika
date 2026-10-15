import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:localsend_app/util/link_download/link_http.dart';
import 'package:localsend_app/util/link_download/segmented_download.dart';
import 'package:test/test.dart';

/// Real HTTP server on 127.0.0.1 serving a 12 MB file in small, slightly
/// delayed chunks, with `Range` support, so several connections really run
/// at the same time.
late HttpServer _server;
late Directory _tmp;
final _data = Uint8List.fromList(List<int>.generate(12 * 1024 * 1024, (i) => (i * 7 + i ~/ 4096) % 256));
const _etag = '"seg-v1"';
const _http = LinkHttp(trustedHosts: {'127.0.0.1'}, idleTimeout: Duration(seconds: 5));
var _rangeRequests = 0;

Future<void> _handle(HttpRequest request) async {
  final response = request.response;
  final ignoreRanges = request.uri.path == '/no-ranges.bin';
  response.headers.contentType = ContentType.binary;
  response.headers.set(HttpHeaders.etagHeader, _etag);
  if (!ignoreRanges) {
    response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
  }
  var start = 0;
  var end = _data.length - 1;
  final range = request.headers.value(HttpHeaders.rangeHeader);
  if (range != null && !ignoreRanges && request.headers.value(HttpHeaders.ifRangeHeader) == _etag) {
    final match = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(range)!;
    start = int.parse(match.group(1)!);
    end = match.group(2)!.isEmpty ? _data.length - 1 : int.parse(match.group(2)!);
    _rangeRequests++;
    response.statusCode = HttpStatus.partialContent;
    response.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/${_data.length}');
  }
  response.contentLength = end - start + 1;
  try {
    for (var pos = start; pos <= end; pos += 64 * 1024) {
      response.add(_data.sublist(pos, (pos + 64 * 1024).clamp(0, end + 1)));
      await response.flush();
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    await response.close();
  } catch (_) {
    // Client went away (pause / cancel / split).
  }
}

Future<DirectFileInfo> _info(String path) => _http.analyze(Uri.parse('http://127.0.0.1:${_server.port}$path'));

File _newFile(String name) => File('${_tmp.path}/$name');

SegmentedDownload _download(DirectFileInfo info, File file, List<RangeSegment> segments, LinkCancelToken token, {int connections = 4}) {
  return SegmentedDownload(
    http: _http,
    info: info,
    file: file,
    segments: segments,
    connections: connections,
    cancelToken: token,
    onProgress: (_, _) {},
    onCheckpoint: (_) async {},
  );
}

void main() {
  setUpAll(() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.defaultResponseHeaders.clear();
    _server.listen((request) => unawaited(_handle(request)));
    _tmp = await Directory.systemTemp.createTemp('aika_segmented_test');
  });

  tearDownAll(() async {
    await _server.close(force: true);
    await _tmp.delete(recursive: true);
  });

  group('planSegments', () {
    test('covers the whole file with equal ranges', () {
      final segments = planSegments(10 * 1024 * 1024 + 3, 4);
      expect(segments.length, 4);
      expect(segmentsCoverFile(segments, 10 * 1024 * 1024 + 3), isTrue);
    });

    test('never makes ranges smaller than 1 MB', () {
      expect(planSegments(3 * 1024 * 1024, 16).length, 3);
      expect(planSegments(100, 8).length, 1);
    });

    test('detects holes and overlaps', () {
      expect(segmentsCoverFile([RangeSegment(start: 0, end: 9), RangeSegment(start: 11, end: 20)], 21), isFalse);
      expect(segmentsCoverFile([RangeSegment(start: 0, end: 10), RangeSegment(start: 10, end: 20)], 21), isFalse);
      expect(segmentsCoverFile([RangeSegment(start: 10, end: 20), RangeSegment(start: 0, end: 9)], 21), isTrue);
    });

    test('saved ranges are validated', () {
      expect(RangeSegment.tryFromJson([0, 99, 50])?.position, 50);
      expect(RangeSegment.tryFromJson([0, 99, 500]), isNull);
      expect(RangeSegment.tryFromJson(['a', 1, 2]), isNull);
      expect(RangeSegment.tryFromJson(null), isNull);
    });
  });

  test('downloads with several connections and gets the exact bytes', () async {
    final info = await _info('/file.bin');
    final file = _newFile('multi.bin');
    _rangeRequests = 0;
    await _download(info, file, planSegments(info.size!, 4), LinkCancelToken()).run();
    expect(_rangeRequests, greaterThanOrEqualTo(4));
    expect(await file.readAsBytes(), _data);
  });

  test('an idle connection splits a running range (one range, four connections)', () async {
    final info = await _info('/file.bin');
    final file = _newFile('split.bin');
    final segments = planSegments(info.size!, 1);
    await _download(info, file, segments, LinkCancelToken(), connections: 4).run();
    expect(segments.length, greaterThan(1));
    expect(segmentsCoverFile(segments, info.size!), isTrue);
    expect(await file.readAsBytes(), _data);
  });

  test('pauses, then resumes from the saved ranges without corruption', () async {
    final info = await _info('/file.bin');
    final file = _newFile('resume.bin');
    final segments = planSegments(info.size!, 4);
    final token = LinkCancelToken();
    final run = _download(info, file, segments, token).run();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    token.cancel();
    await expectLater(run, throwsA(predicate<Object>(isSegmentedDownloadCancelled)));

    final done = segments.fold<int>(0, (sum, s) => sum + s.done);
    expect(done, greaterThan(0));
    expect(done, lessThan(info.size!));

    // Same ranges, new run: continues where each connection stopped.
    final resumed = segments.map((s) => RangeSegment.tryFromJson(s.toJson())!).toList();
    await _download(info, file, resumed, LinkCancelToken()).run();
    expect(await file.readAsBytes(), _data);
  });

  test('a server ignoring ranges is reported so a single connection is used', () async {
    final info = await _info('/no-ranges.bin');
    expect(info.acceptsRanges, isFalse);
    final forced = DirectFileInfo(
      sourceUri: info.sourceUri,
      fileUri: info.fileUri,
      fileName: info.fileName,
      mimeType: info.mimeType,
      kind: info.kind,
      size: info.size,
      acceptsRanges: true, // Lies about ranges.
      etag: info.etag,
      lastModified: info.lastModified,
    );
    await expectLater(
      _download(forced, _newFile('no-ranges.bin'), planSegments(info.size!, 4), LinkCancelToken()).run(),
      throwsA(isA<RangeNotSupportedException>()),
    );
  });
}
