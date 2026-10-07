import 'dart:convert';
import 'dart:io';

import 'package:localsend_app/model/cross_file.dart';
import 'package:localsend_app/model/state/send/web/web_send_file.dart';
import 'package:localsend_app/model/state/send/web/web_send_session.dart';
import 'package:localsend_app/model/state/send/web/web_send_state.dart';
import 'package:localsend_app/provider/network/server/server_utils.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/util/native/directories.dart';
import 'package:localsend_app/util/user_agent_analyzer.dart';
import 'package:localsend_isolates/isolate.dart';
import 'package:localsend_isolates/model/dto/file_dto.dart';
import 'package:localsend_isolates/model/file_type.dart';
import 'package:localsend_isolates/util/android_channel.dart' as isolate_android_channel;
import 'package:localsend_isolates/util/rust.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

final _logger = Logger('WebSendController');

/// Handles all server events for web send (sending files to web browsers).
/// The web page and the downloads themselves are served by the Rust server
/// which emits the events handled here.
class SendController {
  final ServerUtils server;

  SendController(this.server);

  /// Builds the [WebSendState] for the given [files].
  /// The auto accept setting and the pin of a previous web send state are kept.
  Future<WebSendState> buildWebSendState({required List<CrossFile> files}) async {
    final currentWebSendState = server.getStateOrNull()?.webSendState;

    return WebSendState(
      sessions: {},
      files: Map.fromEntries(await Future.wait(files.map(_toWebSendFile))),
      autoAccept: currentWebSendState?.autoAccept ?? server.ref.read(settingsProvider).shareViaLinkAutoAccept,
      pin: currentWebSendState?.pin,
    );
  }

  /// Adds [files] to the running web share, without restarting the server:
  /// browsers that already opened the link keep their session and see the
  /// new files on their page's next refresh. Files already shared are skipped.
  Future<void> addFiles(List<CrossFile> files) async {
    final webSendState = server.getStateOrNull()?.webSendState;
    if (webSendState == null || files.isEmpty) {
      return;
    }
    final alreadyShared = webSendState.files.values.map((f) => f.path).whereType<String>().toSet();
    final added = await Future.wait(
      files.where((f) => f.path == null || !alreadyShared.contains(f.path)).map(_toWebSendFile),
    );
    if (added.isEmpty) {
      return;
    }
    _publishFiles({...?server.getStateOrNull()?.webSendState?.files, ...Map.fromEntries(added)});
  }

  /// Stops sharing the file [fileId] through the running web share.
  /// A download already in progress finishes; new requests are refused.
  void removeFile(String fileId) {
    final files = server.getStateOrNull()?.webSendState?.files;
    if (files == null || !files.containsKey(fileId)) {
      return;
    }
    _publishFiles({...files}..remove(fileId));
  }

  /// Stores [files] in the state and hands the list to the Rust server.
  void _publishFiles(Map<String, WebSendFile> files) {
    server.setState(
      (oldState) => oldState?.copyWith(
        webSendState: oldState.webSendState?.copyWith(files: files),
      ),
    );
    server.ref
        .redux(parentIsolateProvider)
        .dispatch(
          IsolateHttpServerSetWebSendFilesAction(
            files: {
              for (final entry in files.entries) entry.key: entry.value.file.toRust(),
            },
          ),
        );
  }

  /// Converts a selected file into an offered file.
  /// Files that only exist in memory (e.g. text messages) are materialized
  /// to the cache directory so the Rust server can stream them.
  Future<MapEntry<String, WebSendFile>> _toWebSendFile(CrossFile file) async {
    final id = _uuid.v4();

    String? path = file.path;
    if (path == null && file.bytes != null) {
      // The Rust server streams file content from disk, so in-memory
      // bytes (text messages, clipboard content) are written to a temp file.
      final tempPath = p.join(await getCacheDirectory(), 'web-send-$id');
      await File(tempPath).writeAsBytes(file.bytes!);
      path = tempPath;
    }

    return MapEntry(
      id,
      WebSendFile(
        file: FileDto(
          id: id,
          fileName: file.name,
          size: file.size,
          fileType: file.fileType,
          hash: null,
          // A simple message is shown by embedding it into the preview.
          preview: file.fileType == FileType.text && file.bytes != null ? utf8.decode(file.bytes!) : null,
          metadata: file.lastModified != null || file.lastAccessed != null
              ? FileMetadata(
                  lastModified: file.lastModified,
                  lastAccessed: file.lastAccessed,
                )
              : null,
        ),
        asset: file.asset,
        path: path,
        bytes: file.bytes,
      ),
    );
  }

  /// A web client requests to download the shared files.
  /// The Rust server already checked the PIN and handles repeated visits of
  /// accepted sessions itself.
  void onPrepareDownload(HttpServerWebPrepareDownloadEvent event) {
    final webSendState = server.getStateOrNull()?.webSendState;
    if (webSendState == null) {
      // should not happen: web send events are only emitted when web send was configured
      server.ref.redux(parentIsolateProvider).dispatch(IsolateHttpServerPrepareDownloadDecisionAction(sessionId: event.sessionId, accept: false));
      return;
    }

    server.setState(
      (oldState) => oldState!.copyWith(
        webSendState: oldState.webSendState!.copyWith(
          sessions: {
            ...oldState.webSendState!.sessions,
            event.sessionId: WebSendSession(
              sessionId: event.sessionId,
              pending: true,
              ip: event.ip,
              deviceInfo: parseDeviceInfoFromUserAgent(event.userAgent),
            ),
          },
        ),
      ),
    );

    if (webSendState.autoAccept) {
      acceptRequest(event.sessionId);
    }
  }

  /// A web client downloads an offered file.
  /// The Rust server already validated the session; it streams the content
  /// from the source resolved here.
  Future<void> onFileDownload(HttpServerWebFileDownloadEvent event) async {
    final String? filePath;
    final int? fileDescriptor;
    try {
      final path = server.getStateOrNull()?.webSendState?.files[event.fileId]?.path;
      if (path == null) {
        // should not happen: the Rust server only emits events for offered files
        throw StateError('No path for web send file ${event.fileId}');
      }

      if (path.startsWith('content://')) {
        filePath = null;
        fileDescriptor = await isolate_android_channel.getFileDescriptorAndroid(uri: path);
      } else {
        filePath = path;
        fileDescriptor = null;
      }
    } catch (e, st) {
      _logger.severe('Failed to resolve source for web send file ${event.fileId}', e, st);
      // Unblock the web client's request waiting for the content source.
      server.ref.redux(parentIsolateProvider).dispatch(IsolateHttpServerRejectFileDownloadAction(sessionId: event.sessionId, fileId: event.fileId));
      return;
    }

    server.ref
        .redux(parentIsolateProvider)
        .dispatch(
          IsolateHttpServerFileDownloadTargetAction(
            sessionId: event.sessionId,
            fileId: event.fileId,
            path: filePath,
            fileDescriptor: fileDescriptor,
          ),
        );
  }

  void acceptRequest(String sessionId) {
    final session = server.getStateOrNull()?.webSendState?.sessions[sessionId];
    if (session == null || !session.pending) {
      return;
    }

    server.setState(
      (oldState) => oldState!.copyWith(
        webSendState: oldState.webSendState!.updateSession(
          sessionId: sessionId,
          update: (oldSession) => oldSession.copyWith(pending: false),
        ),
      ),
    );

    server.ref.redux(parentIsolateProvider).dispatch(IsolateHttpServerPrepareDownloadDecisionAction(sessionId: sessionId, accept: true));
  }

  void declineRequest(String sessionId) {
    final session = server.getStateOrNull()?.webSendState?.sessions[sessionId];
    if (session == null || !session.pending) {
      return;
    }

    server.setState(
      (oldState) => oldState!.copyWith(
        webSendState: oldState.webSendState!.copyWith(
          sessions: {
            for (final entry in oldState.webSendState!.sessions.entries)
              if (entry.key != sessionId) entry.key: entry.value, // remove session
          },
        ),
      ),
    );

    server.ref.redux(parentIsolateProvider).dispatch(IsolateHttpServerPrepareDownloadDecisionAction(sessionId: sessionId, accept: false));
  }
}

/// Parses a human-readable device description from a user agent.
String parseDeviceInfoFromUserAgent(String? userAgent) {
  if (userAgent == null) {
    return 'Unknown';
  }

  final userAgentAnalyzer = UserAgentAnalyzer();
  final browser = userAgentAnalyzer.getBrowser(userAgent);
  final os = userAgentAnalyzer.getOS(userAgent);
  if (browser != null && os != null) {
    return '$browser ($os)';
  } else if (browser != null) {
    return browser;
  } else if (os != null) {
    return os;
  } else {
    return 'Unknown';
  }
}

extension on WebSendState {
  WebSendState updateSession({
    required String sessionId,
    required WebSendSession Function(WebSendSession oldSession) update,
  }) {
    return copyWith(
      sessions: {...sessions}
        ..update(
          sessionId,
          (session) => update(session),
        ),
    );
  }
}
