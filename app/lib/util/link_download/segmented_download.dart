import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:localsend_app/util/link_download/link_http.dart';
import 'package:localsend_app/util/link_download/link_problem.dart';

/// Files smaller than this use a single connection (the extra requests
/// would cost more than they save).
const minSegmentedSize = 4 * 1024 * 1024;

/// A running range is only split when at least this much is left, so a
/// connection never starts for a tiny piece and two writers never get
/// close to each other in the file.
const _minSplitRemaining = 4 * 1024 * 1024;

const _segmentRetryDelays = [
  Duration(seconds: 1),
  Duration(seconds: 2),
  Duration(seconds: 4),
  Duration(seconds: 8),
  Duration(seconds: 15),
];

/// Splits a file of [size] bytes into up to [connections] equal ranges
/// (at least 1 MB each) covering the whole file.
List<RangeSegment> planSegments(int size, int connections) {
  final count = max(1, min(connections, size ~/ (1024 * 1024)));
  final base = size ~/ count;
  return [
    for (var i = 0; i < count; i++) RangeSegment(start: i * base, end: i == count - 1 ? size - 1 : (i + 1) * base - 1),
  ];
}

/// Whether [segments] exactly cover `0..size-1` without overlap (checked
/// before resuming from a saved state).
bool segmentsCoverFile(List<RangeSegment> segments, int size) {
  final sorted = [...segments]..sort((a, b) => a.start.compareTo(b.start));
  var next = 0;
  for (final s in sorted) {
    if (s.start != next || s.end < s.start - 1) {
      return false;
    }
    next = s.end + 1;
  }
  return next == size;
}

/// Downloads one file over several connections at once, each writing its
/// own byte range of the same file (like IDM):
/// - when a connection finishes, it takes over half of the largest range
///   still running, so all connections stay busy until the end;
/// - a failing connection retries on its own (network loss, timeout)
///   without stopping the others;
/// - [onCheckpoint] receives the ranges about once a second so the
///   download resumes after Aika is closed;
/// - memory stays constant: every connection streams to disk.
///
/// Throws [RangeNotSupportedException] when the server does not honour
/// ranges (the caller then uses a single connection).
class SegmentedDownload {
  final LinkHttp http;
  final DirectFileInfo info;
  final File file;
  final List<RangeSegment> segments;
  final int connections;
  final LinkCancelToken cancelToken;
  final void Function(int received, int activeConnections) onProgress;
  final Future<void> Function(List<RangeSegment> segments) onCheckpoint;

  final _active = <RangeSegment>{};
  late final LinkCancelToken _abort;
  Object? _error;
  int _received = 0;

  SegmentedDownload({
    required this.http,
    required this.info,
    required this.file,
    required this.segments,
    required this.connections,
    required this.cancelToken,
    required this.onProgress,
    required this.onCheckpoint,
  });

  Future<void> run() async {
    final size = info.size!;
    // Pre-size the file once; ranges are then written in place.
    final init = await file.open(mode: FileMode.append);
    try {
      if (await init.length() != size) {
        await init.truncate(size);
      }
    } finally {
      await init.close();
    }

    _abort = LinkCancelToken();
    final removeForward = cancelToken.onCancel(_abort.cancel);
    if (cancelToken.isCancelled) {
      _abort.cancel();
    }

    _received = segments.fold(0, (sum, s) => sum + s.done);
    onProgress(_received, 0);
    final checkpoint = Timer.periodic(const Duration(seconds: 1), (_) => unawaited(onCheckpoint(segments)));
    try {
      await Future.wait([for (var i = 0; i < max(1, connections); i++) _worker()]);
    } finally {
      checkpoint.cancel();
      removeForward();
      await onCheckpoint(segments);
    }

    final error = _error;
    if (error != null) {
      throw error;
    }
    if (cancelToken.isCancelled) {
      throw const _SegmentedCancelled();
    }
    if (segments.any((s) => s.remaining > 0)) {
      throw const LinkDownloadException(LinkProblem.network);
    }
  }

  /// One connection: takes free ranges (or splits a running one) until
  /// nothing is left. Never throws; the first fatal error is kept in
  /// [_error] and stops the other connections.
  Future<void> _worker() async {
    RandomAccessFile? raf;
    try {
      raf = await file.open(mode: FileMode.append);
      while (!_abort.isCancelled) {
        final segment = _nextSegment();
        if (segment == null) {
          return;
        }
        _active.add(segment);
        try {
          await _runSegment(raf, segment);
        } finally {
          _active.remove(segment);
        }
      }
    } catch (e) {
      if (!_abort.isCancelled && !isLinkDownloadCancelled(e)) {
        _error ??= e;
        _abort.cancel();
      }
    } finally {
      await raf?.close();
    }
  }

  RangeSegment? _nextSegment() {
    for (final s in segments) {
      if (s.remaining > 0 && !_active.contains(s)) {
        return s;
      }
    }
    // Nothing free: split the running range with the most bytes left.
    RangeSegment? largest;
    for (final s in _active) {
      if (s.remaining >= _minSplitRemaining && (largest == null || s.remaining > largest.remaining)) {
        largest = s;
      }
    }
    if (largest == null) {
      return null;
    }
    final newStart = largest.position + largest.remaining ~/ 2;
    final split = RangeSegment(start: newStart, end: largest.end);
    largest.end = newStart - 1;
    segments.add(split);
    return split;
  }

  Future<void> _runSegment(RandomAccessFile raf, RangeSegment segment) async {
    for (var attempt = 0; ; attempt++) {
      try {
        await http.downloadSegment(
          info: info,
          raf: raf,
          segment: segment,
          cancelToken: _abort,
          onBytes: (bytes) {
            _received += bytes;
            onProgress(_received, _active.length);
          },
        );
        return;
      } on LinkDownloadException catch (e) {
        if (!e.isTransient || attempt >= _segmentRetryDelays.length || _abort.isCancelled) {
          rethrow;
        }
        await Future<void>.delayed(_segmentRetryDelays[attempt]);
        if (_abort.isCancelled) {
          rethrow;
        }
      }
    }
  }
}

/// Raised by [SegmentedDownload.run] when the user cancels or pauses.
class _SegmentedCancelled implements Exception {
  const _SegmentedCancelled();
}

/// Whether [error] comes from a cancelled multi-connection download.
bool isSegmentedDownloadCancelled(Object error) => error is _SegmentedCancelled || isLinkDownloadCancelled(error);
