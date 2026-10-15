import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:localsend_app/util/link_download/file_naming.dart';
import 'package:localsend_app/util/link_download/link_problem.dart';
import 'package:localsend_app/util/link_download/link_sources.dart';
import 'package:localsend_app/util/link_download/url_policy.dart';
import 'package:mime/mime.dart';

/// Most redirections followed (short links, CDNs and signed URLs need a
/// few; loops and tracking chains are cut).
const maxRedirects = 5;

const _userAgent = 'Mozilla/5.0 (compatible; Aika-LinkDownload/1.0)';

/// Credentials for one host only, sent exclusively over `https` to
/// [host] and never to the hosts it redirects to (for GitHub: sent to
/// `api.github.com`, not to the storage server holding the file).
class LinkAuth {
  final String host;
  final String authorization;

  const LinkAuth({required this.host, required this.authorization});

  @override
  String toString() => 'LinkAuth($host)'; // Never prints the secret.
}

/// A link verified to serve a file.
class DirectFileInfo {
  /// Link as entered (shown to the user and kept in the history).
  final Uri sourceUri;

  /// Link after redirections, used for the download itself (may contain
  /// short-lived signed tokens, so it is never stored).
  final Uri fileUri;

  final String fileName;
  final String? mimeType;
  final LinkMediaKind kind;

  /// Size in bytes, `null` when the server does not announce it.
  final int? size;

  /// The server accepts `Range` requests: an interrupted download resumes.
  final bool acceptsRanges;

  /// Validators used with `If-Range` so a resumed download never mixes two
  /// versions of the file.
  final String? etag;
  final String? lastModified;

  /// Credentials needed for [fileUri] (kept in memory only: never saved
  /// with the queue or the history).
  final LinkAuth? auth;

  const DirectFileInfo({
    required this.sourceUri,
    required this.fileUri,
    required this.fileName,
    required this.mimeType,
    required this.kind,
    required this.size,
    required this.acceptsRanges,
    required this.etag,
    required this.lastModified,
    this.auth,
  });
}

/// Lets a running download be stopped from the UI.
class LinkCancelToken {
  bool _cancelled = false;
  final _listeners = <void Function()>[];

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) {
      return;
    }
    _cancelled = true;
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }

  /// Registers [listener]; returns a function that removes it (long
  /// downloads retry many times and must not accumulate listeners).
  void Function() onCancel(void Function() listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }
}

/// The server ignored a `Range` request (or the file changed): the
/// multi-connection download falls back to a single connection.
class RangeNotSupportedException implements Exception {
  const RangeNotSupportedException();
}

/// One byte range of a multi-connection download: bytes [start]..[end]
/// (inclusive), of which [done] are already written. [end] may be lowered
/// while downloading when the range is split to give work to an idle
/// connection.
class RangeSegment {
  final int start;
  int end;
  int done;

  RangeSegment({required this.start, required this.end, this.done = 0});

  int get position => start + done;
  int get remaining => end - position + 1;

  List<int> toJson() => [start, end, done];

  static RangeSegment? tryFromJson(Object? json) {
    if (json is! List || json.length != 3 || json.any((v) => v is! int)) {
      return null;
    }
    final [start, end, done] = json.cast<int>();
    if (start < 0 || end < start - 1 || done < 0 || start + done > end + 1) {
      return null;
    }
    return RangeSegment(start: start, end: end, done: done);
  }
}

/// HTTP access for "Télécharger depuis un lien", separate from Aika's local
/// transfer protocol.
///
/// Security:
/// - every connection goes to an address checked by [resolvePublicAddress]
///   and the socket is opened to that exact address (no second DNS lookup,
///   no DNS rebinding); TLS still verifies the certificate for the host name;
/// - redirections are followed one by one and each target is checked again
///   (scheme, local address, known platform); `https` → `http` is refused;
/// - no proxy, no cookies, no credentials are ever sent;
/// - nothing is decompressed on the fly, so sizes and progress are exact.
class LinkHttp {
  /// Hosts allowed despite a non-public address. Tests only (they serve
  /// files from `127.0.0.1`); always empty in the app.
  final Set<String> trustedHosts;
  final Duration connectTimeout;
  final Duration idleTimeout;

  const LinkHttp({
    this.trustedHosts = const {},
    this.connectTimeout = const Duration(seconds: 15),
    this.idleTimeout = const Duration(seconds: 30),
  });

  HttpClient _newClient() {
    final client = HttpClient()
      ..findProxy = ((_) => 'DIRECT')
      ..autoUncompress = false
      ..userAgent = _userAgent
      ..connectionTimeout = connectTimeout
      ..idleTimeout = const Duration(seconds: 5);
    client.connectionFactory = (Uri uri, String? proxyHost, int? proxyPort) async {
      final address = await resolvePublicAddress(uri.host, trustedHosts: trustedHosts);
      final tcp = await Socket.startConnect(address, uri.port);
      final socket = tcp.socket.timeout(
        connectTimeout,
        onTimeout: () {
          tcp.cancel();
          throw const LinkDownloadException(LinkProblem.timeout);
        },
      );
      if (uri.scheme != 'https') {
        return ConnectionTask.fromSocket(socket, tcp.cancel);
      }
      // Certificate checked against the host name, not the IP address.
      return ConnectionTask.fromSocket(
        socket.then((s) => SecureSocket.secure(s, host: uri.host)),
        tcp.cancel,
      );
    };
    return client;
  }

  /// Checks that [uri] serves a file and reads what the server announces
  /// about it, without downloading it.
  Future<DirectFileInfo> analyze(Uri uri, {LinkAuth? auth}) async {
    final client = _newClient();
    try {
      final (response, finalUri) = await _open(client, uri, const {}, auth: auth).timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw const LinkDownloadException(LinkProblem.timeout),
      );
      try {
        _throwOnErrorStatus(response.statusCode);

        final contentType = normalizeMimeType(response.headers.value(HttpHeaders.contentTypeHeader));
        final disposition = response.headers.value('content-disposition');
        final isAttachment = disposition != null && disposition.toLowerCase().trimLeft().startsWith('attachment');

        var mimeType = contentType;
        if (mimeType == null || mimeType == 'application/octet-stream') {
          // Unknown type: look at the first bytes (magic numbers).
          final head = await _firstBytes(response, 512);
          mimeType = lookupMimeType(fileNameFromUri(finalUri) ?? '', headerBytes: head) ?? mimeType;
          if (mimeType == null && _looksLikeHtml(head)) {
            mimeType = 'text/html';
          }
        }

        if (!isAttachment && (mimeType == 'text/html' || mimeType == 'application/xhtml+xml')) {
          throw const LinkDownloadException(LinkProblem.webPageWithoutMedia);
        }

        final fileName = sanitizeFileName(
          fileNameFromContentDisposition(disposition) ?? fileNameFromUri(finalUri) ?? fileNameFromUri(uri),
          mimeType: mimeType,
        );
        final length = response.contentLength;
        return DirectFileInfo(
          sourceUri: uri,
          fileUri: finalUri,
          fileName: fileName,
          mimeType: mimeType,
          kind: mediaKindOf(mimeType: mimeType, fileName: fileName),
          size: length >= 0 ? length : null,
          acceptsRanges: (response.headers.value(HttpHeaders.acceptRangesHeader) ?? '').toLowerCase().contains('bytes'),
          etag: _strongEtag(response.headers.value(HttpHeaders.etagHeader)),
          lastModified: response.headers.value(HttpHeaders.lastModifiedHeader),
          auth: auth,
        );
      } finally {
        await _discard(response);
      }
    } on LinkDownloadException {
      rethrow;
    } on HandshakeException {
      throw const LinkDownloadException(LinkProblem.network);
    } on SocketException {
      throw const LinkDownloadException(LinkProblem.network);
    } on HttpException {
      throw const LinkDownloadException(LinkProblem.network);
    } on TimeoutException {
      throw const LinkDownloadException(LinkProblem.timeout);
    } finally {
      client.close(force: true);
    }
  }

  /// Downloads [info] into [partFile], appending from its current size when
  /// the server allows it (otherwise starting over), and returns the final
  /// size. Streams to disk chunk by chunk: memory use stays constant,
  /// whatever the file size.
  ///
  /// [onProgress] receives the bytes written so far and the total when
  /// known. [maxBytes] stops downloads whose real size exceeds it.
  Future<int> download({
    required DirectFileInfo info,
    required File partFile,
    required LinkCancelToken cancelToken,
    required void Function(int received, int? total) onProgress,
    required int maxBytes,
  }) async {
    final client = _newClient();
    final unregister = cancelToken.onCancel(() => client.close(force: true));
    RandomAccessFile? raf;
    try {
      var start = partFile.existsSync() ? partFile.lengthSync() : 0;
      final validator = info.etag ?? info.lastModified;
      final canResume = start > 0 && info.acceptsRanges && validator != null;
      final headers = <String, String>{
        if (canResume) HttpHeaders.rangeHeader: 'bytes=$start-',
        if (canResume) HttpHeaders.ifRangeHeader: validator,
      };

      final (response, _) = await _open(client, info.fileUri, headers, auth: info.auth).timeout(
        connectTimeout * 2,
        onTimeout: () => throw const LinkDownloadException(LinkProblem.timeout),
      );

      int? total;
      if (response.statusCode == HttpStatus.partialContent && canResume) {
        total = _totalFromContentRange(response.headers.value(HttpHeaders.contentRangeHeader)) ?? info.size;
      } else if (response.statusCode == HttpStatus.requestedRangeNotSatisfiable && canResume && info.size == start) {
        // Already complete.
        await _discard(response);
        onProgress(start, start);
        return start;
      } else if (response.statusCode == HttpStatus.requestedRangeNotSatisfiable && canResume) {
        // The partial file no longer matches: start over on the next try.
        await _discard(response);
        await partFile.delete();
        throw const LinkDownloadException(LinkProblem.network);
      } else {
        _throwOnErrorStatus(response.statusCode);
        start = 0; // Range ignored or file changed: start over.
        total = response.contentLength >= 0 ? response.contentLength : info.size;
      }

      if (total != null && total > maxBytes) {
        await _discard(response);
        throw const LinkDownloadException(LinkProblem.tooLarge);
      }

      raf = await partFile.open(mode: start == 0 ? FileMode.write : FileMode.append);
      var received = start;
      onProgress(received, total);
      await for (final chunk in response.timeout(idleTimeout)) {
        if (cancelToken.isCancelled) {
          break;
        }
        await raf.writeFrom(chunk);
        received += chunk.length;
        if (received > maxBytes) {
          throw const LinkDownloadException(LinkProblem.tooLarge);
        }
        onProgress(received, total);
      }
      await raf.flush();

      if (cancelToken.isCancelled) {
        throw const _Cancelled();
      }
      if (total != null && received < total) {
        // Connection ended early: resumable.
        throw const LinkDownloadException(LinkProblem.network);
      }
      return received;
    } on LinkDownloadException {
      rethrow;
    } on _Cancelled {
      rethrow;
    } on FileSystemException catch (e) {
      if (cancelToken.isCancelled) {
        throw const _Cancelled();
      }
      throw LinkDownloadException(_isNoSpace(e) ? LinkProblem.notEnoughSpace : LinkProblem.storage);
    } catch (e) {
      if (cancelToken.isCancelled) {
        throw const _Cancelled();
      }
      if (e is TimeoutException) {
        throw const LinkDownloadException(LinkProblem.timeout);
      }
      throw const LinkDownloadException(LinkProblem.network);
    } finally {
      unregister();
      await raf?.close();
      client.close(force: true);
    }
  }

  /// Downloads the rest of [segment] into [raf] at the matching offset
  /// (one connection of a multi-connection download). Writes never go past
  /// [RangeSegment.end], even when it is lowered meanwhile.
  ///
  /// Throws [RangeNotSupportedException] when the server answers without a
  /// matching partial response (range ignored, or the file changed since
  /// the analysis: `If-Range` no longer matches).
  Future<void> downloadSegment({
    required DirectFileInfo info,
    required RandomAccessFile raf,
    required RangeSegment segment,
    required LinkCancelToken cancelToken,
    required void Function(int bytes) onBytes,
  }) async {
    if (segment.remaining <= 0) {
      return;
    }
    final client = _newClient();
    final unregister = cancelToken.onCancel(() => client.close(force: true));
    try {
      final from = segment.position;
      final validator = info.etag ?? info.lastModified;
      final headers = <String, String>{
        HttpHeaders.rangeHeader: 'bytes=$from-${segment.end}',
        HttpHeaders.ifRangeHeader: ?validator,
      };
      final (response, _) = await _open(client, info.fileUri, headers, auth: info.auth).timeout(
        connectTimeout * 2,
        onTimeout: () => throw const LinkDownloadException(LinkProblem.timeout),
      );
      if (response.statusCode != HttpStatus.partialContent) {
        await _discard(response);
        if (response.statusCode >= 400 && response.statusCode != HttpStatus.requestedRangeNotSatisfiable) {
          _throwOnErrorStatus(response.statusCode);
        }
        throw const RangeNotSupportedException();
      }
      final contentRange = response.headers.value(HttpHeaders.contentRangeHeader) ?? '';
      final rangeStart = int.tryParse(RegExp(r'bytes\s+(\d+)-').firstMatch(contentRange)?.group(1) ?? '');
      final total = _totalFromContentRange(contentRange);
      if (rangeStart != from || (total != null && info.size != null && total != info.size)) {
        await _discard(response);
        throw const RangeNotSupportedException();
      }

      await raf.setPosition(from);
      await for (final chunk in response.timeout(idleTimeout)) {
        if (cancelToken.isCancelled) {
          break;
        }
        final room = segment.remaining;
        if (room <= 0) {
          break; // The segment was split: the rest belongs to another connection.
        }
        final part = chunk.length > room ? chunk.sublist(0, room) : chunk;
        await raf.writeFrom(part);
        segment.done += part.length;
        onBytes(part.length);
        if (part.length < chunk.length) {
          break;
        }
      }

      if (cancelToken.isCancelled) {
        throw const _Cancelled();
      }
      if (segment.remaining > 0) {
        throw const LinkDownloadException(LinkProblem.network); // Ended early.
      }
    } on LinkDownloadException {
      rethrow;
    } on RangeNotSupportedException {
      rethrow;
    } on _Cancelled {
      rethrow;
    } on FileSystemException catch (e) {
      if (cancelToken.isCancelled) {
        throw const _Cancelled();
      }
      throw LinkDownloadException(_isNoSpace(e) ? LinkProblem.notEnoughSpace : LinkProblem.storage);
    } catch (e) {
      if (cancelToken.isCancelled) {
        throw const _Cancelled();
      }
      if (e is TimeoutException) {
        throw const LinkDownloadException(LinkProblem.timeout);
      }
      throw const LinkDownloadException(LinkProblem.network);
    } finally {
      unregister();
      client.close(force: true);
    }
  }

  /// Reads a small JSON answer from an official API (at most 1 MB), for
  /// example GitHub's artifact details.
  Future<Map<String, dynamic>> getJson(Uri uri, {LinkAuth? auth, Map<String, String> headers = const {}}) async {
    final client = _newClient();
    try {
      final (response, _) = await _open(client, uri, headers, auth: auth).timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw const LinkDownloadException(LinkProblem.timeout),
      );
      try {
        _throwOnErrorStatus(response.statusCode);
        final bytes = <int>[];
        await for (final chunk in response.timeout(idleTimeout)) {
          bytes.addAll(chunk);
          if (bytes.length > 1024 * 1024) {
            throw const LinkDownloadException(LinkProblem.serverError);
          }
        }
        final json = jsonDecode(utf8.decode(bytes));
        if (json is! Map<String, dynamic>) {
          throw const LinkDownloadException(LinkProblem.serverError);
        }
        return json;
      } finally {
        await _discard(response);
      }
    } on LinkDownloadException {
      rethrow;
    } on FormatException {
      throw const LinkDownloadException(LinkProblem.serverError);
    } on TimeoutException {
      throw const LinkDownloadException(LinkProblem.timeout);
    } catch (_) {
      throw const LinkDownloadException(LinkProblem.network);
    } finally {
      client.close(force: true);
    }
  }

  /// Sends a GET to [uri], following redirections manually so that each
  /// step is checked. Returns the response of the last step and its URL.
  Future<(HttpClientResponse, Uri)> _open(HttpClient client, Uri uri, Map<String, String> headers, {LinkAuth? auth}) async {
    var current = checkLink(uri, trustedHosts: trustedHosts);
    for (var hop = 0; hop <= maxRedirects; hop++) {
      final platform = knownPlatformOf(current);
      if (platform != null) {
        throw LinkDownloadException(LinkProblem.unsupportedPlatform, platform: platform.name);
      }

      final request = await client.getUrl(current);
      request.followRedirects = false;
      request.persistentConnection = false;
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      request.headers.set(HttpHeaders.acceptHeader, '*/*');
      headers.forEach(request.headers.set);
      if (auth != null && current.scheme == 'https' && current.host.toLowerCase() == auth.host) {
        request.headers.set(HttpHeaders.authorizationHeader, auth.authorization);
      }
      final response = await request.close();

      if (!response.isRedirect) {
        return (response, current);
      }
      final location = response.headers.value(HttpHeaders.locationHeader);
      await _discard(response);
      if (location == null) {
        throw LinkDownloadException(LinkProblem.serverError, statusCode: response.statusCode);
      }
      final next = checkLink(current.resolve(location), trustedHosts: trustedHosts);
      if (current.scheme == 'https' && next.scheme != 'https') {
        throw const LinkDownloadException(LinkProblem.insecureRedirect);
      }
      current = next;
    }
    throw const LinkDownloadException(LinkProblem.tooManyRedirects);
  }
}

class _Cancelled implements Exception {
  const _Cancelled();
}

/// Whether [error] is the cancellation raised by [LinkHttp.download].
bool isLinkDownloadCancelled(Object error) => error is _Cancelled;

void _throwOnErrorStatus(int status) {
  if (status >= 200 && status < 300) {
    return;
  }
  if (status == HttpStatus.unauthorized || status == HttpStatus.forbidden || status == 407) {
    throw LinkDownloadException(LinkProblem.requiresAuth, statusCode: status);
  }
  if (status == HttpStatus.notFound || status == HttpStatus.gone) {
    throw LinkDownloadException(LinkProblem.notFound, statusCode: status);
  }
  throw LinkDownloadException(LinkProblem.serverError, statusCode: status);
}

/// Only strong ETags can validate a byte range (RFC 9110 §13.1.5).
String? _strongEtag(String? etag) => etag == null || etag.startsWith('W/') ? null : etag;

/// `bytes 100-199/1234` → 1234; `null` when the total is unknown (`*`).
int? _totalFromContentRange(String? header) {
  final match = RegExp(r'/(\d+)\s*$').firstMatch(header ?? '');
  return match == null ? null : int.tryParse(match.group(1)!);
}

Future<List<int>> _firstBytes(HttpClientResponse response, int count) async {
  final bytes = <int>[];
  try {
    await for (final chunk in response.timeout(const Duration(seconds: 10))) {
      bytes.addAll(chunk);
      if (bytes.length >= count) {
        break; // Cancels the subscription: the body is not downloaded.
      }
    }
  } on TimeoutException {
    // Use what arrived.
  }
  return bytes.length > count ? bytes.sublist(0, count) : bytes;
}

bool _looksLikeHtml(List<int> head) {
  final text = String.fromCharCodes(head.take(256)).trimLeft().toLowerCase();
  return text.startsWith('<!doctype html') || text.startsWith('<html') || text.startsWith('<head') || text.startsWith('<?xml') && text.contains('<html');
}

/// Stops reading a response body without downloading it.
Future<void> _discard(HttpClientResponse response) async {
  try {
    await response.listen(null).cancel();
  } catch (_) {
    // The body may already be consumed.
  }
}

bool _isNoSpace(FileSystemException e) {
  final code = e.osError?.errorCode;
  // ENOSPC (Linux, Android, macOS, iOS) / ERROR_DISK_FULL, ERROR_HANDLE_DISK_FULL (Windows)
  return code == 28 || code == 112 || code == 39;
}
