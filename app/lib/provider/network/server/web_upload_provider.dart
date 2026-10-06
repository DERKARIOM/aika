import 'package:localsend_isolates/model/dto/file_dto.dart';
import 'package:localsend_isolates/model/file_type.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// Prefix of the sender fingerprint of upload sessions created from the web
/// share page, followed by the web send session ID.
///
/// Set by the Rust server only (`WEB_UPLOAD_FINGERPRINT_PREFIX` in
/// `packages/core/src/http/server/v2.rs`), which refuses it on the public
/// `prepare-upload` endpoint, so it cannot be spoofed by a regular sender.
const kWebUploadFingerprintPrefix = 'aika-web-upload:';

/// Returns the web send session ID if [fingerprint] belongs to a web upload.
String? webUploadSessionIdOf(String fingerprint) {
  if (!fingerprint.startsWith(kWebUploadFingerprintPrefix)) {
    return null;
  }
  return fingerprint.substring(kWebUploadFingerprintPrefix.length);
}

enum WebUploadStatus {
  /// Announced by the browser, not started yet.
  pending,

  /// Bytes are being received.
  receiving,

  /// Saved on this device.
  finished,

  /// The transfer or the save failed.
  failed,

  /// Abandoned by the browser (cancelled, page closed...).
  cancelled,
}

/// A file uploaded to this device from the web share page.
class WebUploadEntry {
  /// The file ID (unique within [sessionId]).
  final String fileId;

  /// The upload session ID, used to look up the progress in `progressProvider`.
  final String sessionId;

  final String fileName;
  final int size;
  final FileType fileType;

  /// Human readable description of the sender (browser and OS).
  final String deviceInfo;

  final WebUploadStatus status;

  /// Where the file was saved (path or content URI), when finished.
  final String? path;

  /// True if the file was saved to the gallery (then [path] may be null).
  final bool savedToGallery;

  final String? errorMessage;

  final DateTime timestamp;

  const WebUploadEntry({
    required this.fileId,
    required this.sessionId,
    required this.fileName,
    required this.size,
    required this.fileType,
    required this.deviceInfo,
    required this.status,
    required this.path,
    required this.savedToGallery,
    required this.errorMessage,
    required this.timestamp,
  });

  bool get isActive => status == WebUploadStatus.pending || status == WebUploadStatus.receiving;

  WebUploadEntry _copyWith({
    WebUploadStatus? status,
    String? path,
    bool? savedToGallery,
    String? errorMessage,
  }) {
    return WebUploadEntry(
      fileId: fileId,
      sessionId: sessionId,
      fileName: fileName,
      size: size,
      fileType: fileType,
      deviceInfo: deviceInfo,
      status: status ?? this.status,
      path: path ?? this.path,
      savedToGallery: savedToGallery ?? this.savedToGallery,
      errorMessage: errorMessage ?? this.errorMessage,
      timestamp: timestamp,
    );
  }
}

class WebUploadState {
  /// Whether browsers that opened the share link may upload files.
  final bool allowUploads;

  /// Most recent first.
  final List<WebUploadEntry> entries;

  const WebUploadState({
    required this.allowUploads,
    required this.entries,
  });

  bool get hasActiveUploads => entries.any((e) => e.isActive);

  WebUploadState _copyWith({bool? allowUploads, List<WebUploadEntry>? entries}) {
    return WebUploadState(
      allowUploads: allowUploads ?? this.allowUploads,
      entries: entries ?? this.entries,
    );
  }
}

/// Maximum number of entries kept in memory for the current share.
const _maxEntries = 500;

/// State of the files received through the web share link (bidirectional
/// web share). Fed by `ReceiveController`, displayed by `WebSendPage`.
///
/// The per-file byte progress is intentionally not stored here but in
/// `progressProvider` (keyed by session and file ID), so frequent progress
/// events only rebuild the progress bars, not the whole page.
final webUploadProvider = NotifierProvider<WebUploadService, WebUploadState>((ref) {
  return WebUploadService();
});

class WebUploadService extends Notifier<WebUploadState> {
  @override
  WebUploadState init() => const WebUploadState(allowUploads: true, entries: []);

  void setAllowUploads(bool allow) {
    state = state._copyWith(allowUploads: allow);
  }

  /// Starts a new share: forgets the files of the previous one.
  /// The [WebUploadState.allowUploads] choice is kept.
  void reset() {
    state = state._copyWith(entries: const []);
  }

  /// Removes finished, failed and cancelled entries.
  void clearCompleted() {
    state = state._copyWith(entries: state.entries.where((e) => e.isActive).toList());
  }

  /// A browser announced [files] for the upload session [sessionId].
  void addSession({
    required String sessionId,
    required Iterable<FileDto> files,
    required String deviceInfo,
  }) {
    final now = DateTime.now();
    final added = [
      for (final file in files)
        WebUploadEntry(
          fileId: file.id,
          sessionId: sessionId,
          fileName: file.fileName,
          size: file.size,
          fileType: file.fileType,
          deviceInfo: deviceInfo,
          status: WebUploadStatus.pending,
          path: null,
          savedToGallery: false,
          errorMessage: null,
          timestamp: now,
        ),
    ];
    state = state._copyWith(entries: [...added, ...state.entries].take(_maxEntries).toList());
  }

  void markReceiving({required String sessionId, required String fileId}) {
    _update(sessionId, fileId, (e) => e._copyWith(status: WebUploadStatus.receiving));
  }

  void markFinished({required String sessionId, required String fileId, required String? path, required bool savedToGallery}) {
    _update(sessionId, fileId, (e) => e._copyWith(status: WebUploadStatus.finished, path: path, savedToGallery: savedToGallery));
  }

  void markFailed({required String sessionId, required String fileId, required String errorMessage}) {
    _update(sessionId, fileId, (e) => e._copyWith(status: WebUploadStatus.failed, errorMessage: errorMessage));
  }

  /// The session is over: files never received are marked as cancelled.
  void endSession(String sessionId) {
    if (!state.entries.any((e) => e.sessionId == sessionId && e.isActive)) {
      return;
    }
    state = state._copyWith(
      entries: [
        for (final e in state.entries)
          if (e.sessionId == sessionId && e.isActive) e._copyWith(status: WebUploadStatus.cancelled) else e,
      ],
    );
  }

  void _update(String sessionId, String fileId, WebUploadEntry Function(WebUploadEntry) update) {
    final index = state.entries.indexWhere((e) => e.sessionId == sessionId && e.fileId == fileId);
    if (index == -1) {
      return;
    }
    final entries = [...state.entries];
    entries[index] = update(entries[index]);
    state = state._copyWith(entries: entries);
  }
}
