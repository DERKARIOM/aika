import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:legalize/legalize.dart';
import 'package:localsend_app/provider/github_account_provider.dart';
import 'package:localsend_app/provider/persistence_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/util/link_download/browser_bridge.dart';
import 'package:localsend_app/util/link_download/file_naming.dart';
import 'package:localsend_app/util/link_download/github_source.dart';
import 'package:localsend_app/util/link_download/link_http.dart';
import 'package:localsend_app/util/link_download/link_problem.dart';
import 'package:localsend_app/util/link_download/link_sources.dart';
import 'package:localsend_app/util/link_download/segmented_download.dart';
import 'package:localsend_app/util/link_download/url_policy.dart';
import 'package:localsend_app/util/native/channel/android_channel.dart' as android_channel;
import 'package:localsend_app/util/native/directories.dart';
import 'package:localsend_app/util/native/file_saver.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_app/util/native/storage_info.dart';
import 'package:logging/logging.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart' as path_provider;
import 'package:refena_flutter/refena_flutter.dart';

final _logger = Logger('LinkDownload');

/// Above this size the user confirms before downloading; a file of
/// unknown size is stopped when it reaches it.
const largeDownloadBytes = 2 * 1024 * 1024 * 1024;

/// Hard ceiling, far above any realistic file, so a lying server cannot
/// fill the disk forever.
const _absoluteMaxBytes = 512 * 1024 * 1024 * 1024;

const _maxHistory = 50;
const _retryDelays = [Duration(seconds: 2), Duration(seconds: 5), Duration(seconds: 10)];
const _progressInterval = Duration(milliseconds: 250);
const _clipboardInterval = Duration(seconds: 2);

/// Limits offered in the options.
const maxParallelDownloads = 5;
const maxConnectionsPerDownload = 16;

/// Sub-folder of the destination where downloaded files are saved.
const linkDownloadFolderName = 'Aika';

enum LinkDownloadStatus { queued, running, paused, completed, failed, cancelled }

/// A download started from a link. Unfinished ones are kept across
/// restarts and come back paused.
class LinkDownloadTask {
  final String id;
  final DirectFileInfo info;
  final LinkDownloadStatus status;
  final int received;
  final int? total;

  /// Smoothed speed in bytes per second.
  final double bytesPerSecond;

  /// Connections currently downloading this file (0 when not running).
  final int connections;

  /// Set when [status] is [LinkDownloadStatus.failed].
  final LinkProblem? problem;

  /// Saved file (path or `content://` URI) and its folder once completed.
  final String? savedPath;
  final String? savedFolder;

  /// Retry in progress after a network error (1-based), 0 otherwise.
  final int retry;

  /// The user confirmed a file above [largeDownloadBytes].
  final bool allowLarge;

  /// The link must be analysed again before downloading (restored after a
  /// restart or resumed after a pause: signed links expire, and the file
  /// may have changed meanwhile).
  final bool needsRefresh;

  const LinkDownloadTask({
    required this.id,
    required this.info,
    required this.status,
    required this.received,
    required this.total,
    this.bytesPerSecond = 0,
    this.connections = 0,
    this.problem,
    this.savedPath,
    this.savedFolder,
    this.retry = 0,
    this.allowLarge = false,
    this.needsRefresh = false,
  });

  double? get progress {
    final t = total;
    return t == null || t <= 0 ? null : (received / t).clamp(0.0, 1.0);
  }

  bool get isActive => status == LinkDownloadStatus.running || status == LinkDownloadStatus.queued;
  bool get canResume => status == LinkDownloadStatus.paused || status == LinkDownloadStatus.failed;

  LinkDownloadTask copyWith({
    DirectFileInfo? info,
    LinkDownloadStatus? status,
    int? received,
    int? total,
    double? bytesPerSecond,
    int? connections,
    LinkProblem? problem,
    bool clearProblem = false,
    String? savedPath,
    String? savedFolder,
    int? retry,
    bool? needsRefresh,
  }) {
    return LinkDownloadTask(
      id: id,
      info: info ?? this.info,
      status: status ?? this.status,
      received: received ?? this.received,
      total: total ?? this.total,
      bytesPerSecond: bytesPerSecond ?? this.bytesPerSecond,
      connections: connections ?? this.connections,
      problem: clearProblem ? null : problem ?? this.problem,
      savedPath: savedPath ?? this.savedPath,
      savedFolder: savedFolder ?? this.savedFolder,
      retry: retry ?? this.retry,
      allowLarge: allowLarge,
      needsRefresh: needsRefresh ?? this.needsRefresh,
    );
  }

  /// Saved form of an unfinished download. The final (possibly signed)
  /// link is not stored: the source link is analysed again on resume.
  String toJson() => jsonEncode({
    'id': id,
    'url': info.sourceUri.toString(),
    'fileName': info.fileName,
    'mimeType': info.mimeType,
    'size': info.size,
    'acceptsRanges': info.acceptsRanges,
    'etag': info.etag,
    'lastModified': info.lastModified,
    'received': received,
    'allowLarge': allowLarge,
    'problem': problem?.name,
  });

  static LinkDownloadTask? tryFromJson(String raw) {
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final url = checkLink(Uri.tryParse(json['url'] as String));
      final fileName = sanitizeFileName(json['fileName'] as String?);
      final mimeType = json['mimeType'] as String?;
      final size = json['size'] as int?;
      final problemName = json['problem'] as String?;
      return LinkDownloadTask(
        id: json['id'] as String,
        info: DirectFileInfo(
          sourceUri: url,
          fileUri: url,
          fileName: fileName,
          mimeType: mimeType,
          kind: mediaKindOf(mimeType: mimeType, fileName: fileName),
          size: size,
          acceptsRanges: json['acceptsRanges'] as bool? ?? false,
          etag: json['etag'] as String?,
          lastModified: json['lastModified'] as String?,
        ),
        status: problemName == null ? LinkDownloadStatus.paused : LinkDownloadStatus.failed,
        received: json['received'] as int? ?? 0,
        total: size,
        problem: LinkProblem.values.where((x) => x.name == problemName).firstOrNull,
        allowLarge: json['allowLarge'] as bool? ?? false,
        needsRefresh: true,
      );
    } catch (_) {
      return null; // Skip a corrupted or unsafe entry.
    }
  }
}

/// A finished download, kept in the local history (never sent anywhere).
class LinkDownloadRecord {
  final String id;

  /// The link as the user entered it (the final, possibly signed, URL is
  /// not stored).
  final String url;
  final String fileName;
  final String? mimeType;
  final int size;
  final String savedPath;
  final String savedFolder;
  final DateTime completedAt;

  const LinkDownloadRecord({
    required this.id,
    required this.url,
    required this.fileName,
    required this.mimeType,
    required this.size,
    required this.savedPath,
    required this.savedFolder,
    required this.completedAt,
  });

  LinkMediaKind get kind => mediaKindOf(mimeType: mimeType, fileName: fileName);

  Map<String, Object?> toJson() => {
    'id': id,
    'url': url,
    'fileName': fileName,
    'mimeType': mimeType,
    'size': size,
    'savedPath': savedPath,
    'savedFolder': savedFolder,
    'completedAt': completedAt.millisecondsSinceEpoch,
  };

  static LinkDownloadRecord? tryFromJson(String raw) {
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return LinkDownloadRecord(
        id: json['id'] as String,
        url: json['url'] as String,
        fileName: json['fileName'] as String,
        mimeType: json['mimeType'] as String?,
        size: json['size'] as int,
        savedPath: json['savedPath'] as String,
        savedFolder: json['savedFolder'] as String,
        completedAt: DateTime.fromMillisecondsSinceEpoch(json['completedAt'] as int),
      );
    } catch (_) {
      return null; // Skip a corrupted entry instead of losing the history.
    }
  }
}

/// Options of the download manager.
class LinkDownloadSettings {
  /// Downloads running at the same time; the others wait in the queue.
  final int parallel;

  /// Connections per download (1 = classic single connection).
  final int connections;

  /// Offer to download file links copied to the clipboard (desktop only).
  final bool clipboardWatch;

  /// Receive downloads from the Aika browser extension (desktop only).
  final bool browserBridge;

  /// Pairing code the browser extension must send.
  final String bridgeToken;

  const LinkDownloadSettings({
    required this.parallel,
    required this.connections,
    required this.clipboardWatch,
    required this.browserBridge,
    required this.bridgeToken,
  });

  LinkDownloadSettings copyWith({int? parallel, int? connections, bool? clipboardWatch, bool? browserBridge, String? bridgeToken}) {
    return LinkDownloadSettings(
      parallel: parallel ?? this.parallel,
      connections: connections ?? this.connections,
      clipboardWatch: clipboardWatch ?? this.clipboardWatch,
      browserBridge: browserBridge ?? this.browserBridge,
      bridgeToken: bridgeToken ?? this.bridgeToken,
    );
  }

  /// 8 connections on computers, 4 on phones (battery, mobile data).
  static int get defaultConnections => checkPlatformIsDesktop() ? 8 : 4;
}

class LinkDownloadState {
  /// Downloads of this session and unfinished ones, newest first.
  final List<LinkDownloadTask> tasks;
  final List<LinkDownloadRecord> history;
  final LinkDownloadSettings settings;

  /// The browser bridge listens (false while off or when its port is taken).
  final bool bridgeRunning;

  const LinkDownloadState({required this.tasks, required this.history, required this.settings, this.bridgeRunning = false});

  LinkDownloadState copyWith({List<LinkDownloadTask>? tasks, List<LinkDownloadRecord>? history, LinkDownloadSettings? settings, bool? bridgeRunning}) {
    return LinkDownloadState(
      tasks: tasks ?? this.tasks,
      history: history ?? this.history,
      settings: settings ?? this.settings,
      bridgeRunning: bridgeRunning ?? this.bridgeRunning,
    );
  }

  LinkDownloadTask? taskById(String id) => tasks.where((t) => t.id == id).firstOrNull;

  /// Unfinished download of [url] (queued, running, paused or failed).
  LinkDownloadTask? unfinishedFor(Uri url) => tasks
      .where((t) => t.info.sourceUri == url && t.status != LinkDownloadStatus.completed && t.status != LinkDownloadStatus.cancelled)
      .firstOrNull;

  /// Last completed download of [url], if any.
  LinkDownloadRecord? previousDownloadOf(Uri url) {
    final key = url.toString();
    return history.where((r) => r.url == key).firstOrNull;
  }
}

/// Download manager behind "Télécharger depuis un lien", in the spirit of
/// IDM: queue, several downloads at once, several connections per file,
/// pause / resume (also after Aika was closed), clipboard detection on
/// computers. Independent of the local transfer server.
final linkDownloadProvider = NotifierProvider<LinkDownloadService, LinkDownloadState>((ref) {
  return LinkDownloadService(ref.read(persistenceProvider));
});

class LinkDownloadService extends Notifier<LinkDownloadState> {
  final PersistenceService _persistence;
  final LinkHttp _http;
  final _tokens = <String, LinkCancelToken>{};
  final _pausing = <String>{};
  final _lastEmit = <String, DateTime>{};
  final _speedSamples = <String, (DateTime, int)>{};
  final _saveChains = <String, Future<void>>{};
  final _clipboardLinks = StreamController<Uri>.broadcast();
  final _browserDownloads = StreamController<String>.broadcast();
  BrowserBridgeServer? _bridge;
  Timer? _clipboardTimer;
  String? _lastClipboard;
  bool _partsCleaned = false;

  LinkDownloadService(this._persistence, {LinkHttp http = const LinkHttp()}) : _http = http;

  /// File links copied to the clipboard while the option is on (desktop).
  Stream<Uri> get clipboardLinks => _clipboardLinks.stream;

  /// Names of the files the browser extension handed over.
  Stream<String> get browserDownloads => _browserDownloads.stream;

  @override
  LinkDownloadState init() {
    final history = _persistence.getLinkDownloadHistory().map(LinkDownloadRecord.tryFromJson).whereType<LinkDownloadRecord>().toList();
    final restored = _persistence.getLinkDownloadQueue().map(LinkDownloadTask.tryFromJson).whereType<LinkDownloadTask>().toList();
    return LinkDownloadState(
      tasks: restored,
      history: history,
      settings: LinkDownloadSettings(
        parallel: (_persistence.getLinkDownloadParallel() ?? 3).clamp(1, maxParallelDownloads),
        connections: (_persistence.getLinkDownloadConnections() ?? LinkDownloadSettings.defaultConnections).clamp(1, maxConnectionsPerDownload),
        clipboardWatch: _persistence.getLinkDownloadClipboardWatch(),
        browserBridge: _persistence.getBrowserBridgeEnabled(),
        bridgeToken: _bridgeToken(),
      ),
    );
  }

  /// The saved pairing code, created on first use.
  String _bridgeToken() {
    final saved = _persistence.getBrowserBridgeToken();
    if (saved != null && normalizeBridgeToken(saved).length == 16) {
      return saved;
    }
    final token = generateBridgeToken();
    unawaited(_persistence.setBrowserBridgeToken(token));
    return token;
  }

  /// Checks that [url] serves a file (see [LinkHttp.analyze]). GitHub
  /// Actions artifacts go through GitHub's official API with the user's own
  /// token (see [githubAccountProvider]).
  Future<DirectFileInfo> analyze(Uri url) {
    final artifact = GitHubArtifactRef.tryParse(url);
    return artifact == null ? _http.analyze(url) : _analyzeGitHubArtifact(url, artifact);
  }

  Future<DirectFileInfo> _analyzeGitHubArtifact(Uri url, GitHubArtifactRef artifact) async {
    final token = await ref.notifier(githubAccountProvider).readToken();
    if (token == null) {
      throw const LinkDownloadException(LinkProblem.githubSignInRequired);
    }
    final auth = LinkAuth(host: githubApiHost, authorization: 'Bearer $token');

    final Map<String, dynamic> details;
    try {
      details = await _http.getJson(artifact.detailsUri, auth: auth, headers: githubApiHeaders);
    } on LinkDownloadException catch (e) {
      throw switch (e.statusCode) {
        401 => const LinkDownloadException(LinkProblem.githubTokenInvalid),
        403 || 404 => const LinkDownloadException(LinkProblem.githubNoAccess),
        410 => const LinkDownloadException(LinkProblem.expired),
        _ => e,
      };
    }
    if (details['expired'] == true) {
      throw const LinkDownloadException(LinkProblem.expired);
    }

    // The archive link redirects to a short-lived storage link: it is kept
    // as the download link so every request (each connection, each resume)
    // gets a fresh one. The token never reaches the storage server.
    final probed = await _http.analyze(artifact.zipUri, auth: auth);
    final name = details['name'];
    final size = details['size_in_bytes'];
    final fileName = sanitizeFileName('${name is String && name.isNotEmpty ? name : 'artifact-${artifact.artifactId}'}.zip');
    return DirectFileInfo(
      sourceUri: url,
      fileUri: artifact.zipUri,
      fileName: fileName,
      mimeType: 'application/zip',
      kind: LinkMediaKind.archive,
      size: probed.size ?? (size is int && size > 0 ? size : null),
      acceptsRanges: probed.acceptsRanges,
      etag: probed.etag,
      lastModified: probed.lastModified,
      auth: auth,
    );
  }

  /// Free space problem for [info], or `null` when it fits.
  Future<LinkProblem?> checkSpace(DirectFileInfo info) async {
    final size = info.size;
    if (size == null) {
      return null;
    }
    final destination = await _destination();
    final storage = await readStorageInfo(destination: destination == kAndroidDefaultDownloadsMarker ? null : destination);
    if (storage == null) {
      return null; // Unknown: the write itself reports a full disk.
    }
    // On Android 10+ the file is copied from the app's storage into
    // Downloads, so it briefly exists twice.
    final needed = (destination == kAndroidDefaultDownloadsMarker ? 2 * size : size) + 50 * 1024 * 1024;
    return storage.freeBytes < needed ? LinkProblem.notEnoughSpace : null;
  }

  /// Adds [info] to the queue and returns the task id. When the same link
  /// is already in the list (not finished), returns that task instead of
  /// downloading it twice. [allowLarge] is set once the user confirmed a
  /// file above [largeDownloadBytes].
  String start(DirectFileInfo info, {bool allowLarge = false}) {
    final existing = state.unfinishedFor(info.sourceUri);
    if (existing != null) {
      if (existing.canResume) {
        resume(existing.id);
      }
      return existing.id;
    }
    final id = '${DateTime.now().microsecondsSinceEpoch}';
    final task = LinkDownloadTask(
      id: id,
      info: info,
      status: LinkDownloadStatus.queued,
      received: 0,
      total: info.size,
      allowLarge: allowLarge,
    );
    state = state.copyWith(tasks: [task, ...state.tasks]);
    _pump();
    return id;
  }

  /// Pauses a running or queued download, keeping what is already
  /// downloaded.
  void pause(String id) {
    final task = state.taskById(id);
    if (task == null) {
      return;
    }
    if (task.status == LinkDownloadStatus.running) {
      _pausing.add(id);
      _tokens[id]?.cancel();
    } else if (task.status == LinkDownloadStatus.queued) {
      _update(id, (t) => t.copyWith(status: LinkDownloadStatus.paused));
      unawaited(_persistQueue());
    }
  }

  void pauseAll() {
    for (final task in [...state.tasks]) {
      pause(task.id);
    }
  }

  /// Puts a paused or failed download back in the queue.
  void resume(String id) {
    final task = state.taskById(id);
    if (task == null || !task.canResume) {
      return;
    }
    _update(id, (t) => t.copyWith(status: LinkDownloadStatus.queued, needsRefresh: true, clearProblem: true, retry: 0));
    _pump();
  }

  void resumeAll() {
    for (final task in [...state.tasks]) {
      if (task.status == LinkDownloadStatus.paused) {
        resume(task.id);
      }
    }
  }

  /// Stops a download for good and deletes its partial file.
  void cancel(String id) {
    final task = state.taskById(id);
    if (task == null) {
      return;
    }
    if (task.status == LinkDownloadStatus.running) {
      _tokens[id]?.cancel();
      return; // _run marks it cancelled and cleans up.
    }
    if (task.status != LinkDownloadStatus.completed) {
      _update(id, (t) => t.copyWith(status: LinkDownloadStatus.cancelled));
      unawaited(_deleteParts(id));
      unawaited(_persistQueue());
    }
  }

  /// Removes a finished, cancelled or failed download from the list (the
  /// history is kept).
  void dismiss(String id) {
    final task = state.taskById(id);
    if (task == null || task.isActive) {
      return;
    }
    if (task.status != LinkDownloadStatus.completed) {
      unawaited(_deleteParts(id));
    }
    state = state.copyWith(tasks: state.tasks.where((t) => t.id != id).toList());
    unawaited(_persistQueue());
  }

  /// Removes every finished or cancelled entry from the list.
  void clearFinished() {
    state = state.copyWith(
      tasks: state.tasks.where((t) => t.status != LinkDownloadStatus.completed && t.status != LinkDownloadStatus.cancelled).toList(),
    );
  }

  Future<void> removeFromHistory(String id) async {
    await _setHistory(state.history.where((r) => r.id != id).toList());
  }

  Future<void> clearHistory() => _setHistory(const []);

  Future<void> setParallel(int value) async {
    final parallel = value.clamp(1, maxParallelDownloads);
    state = state.copyWith(settings: state.settings.copyWith(parallel: parallel));
    await _persistence.setLinkDownloadParallel(parallel);
    _pump();
  }

  /// Applies to downloads started or resumed afterwards.
  Future<void> setConnections(int value) async {
    final connections = value.clamp(1, maxConnectionsPerDownload);
    state = state.copyWith(settings: state.settings.copyWith(connections: connections));
    await _persistence.setLinkDownloadConnections(connections);
  }

  Future<void> setClipboardWatch(bool enabled) async {
    state = state.copyWith(settings: state.settings.copyWith(clipboardWatch: enabled));
    await _persistence.setLinkDownloadClipboardWatch(enabled);
    if (enabled) {
      await startClipboardWatch();
    } else {
      _clipboardTimer?.cancel();
      _clipboardTimer = null;
    }
  }

  /// Watches the clipboard on computers when the option is on: a copied
  /// link to a file (`.zip`, `.exe`, `.mp4`, `.pdf`, ...) is announced on
  /// [clipboardLinks]. Only checked while Aika is in the foreground; the
  /// clipboard never leaves the device.
  Future<void> startClipboardWatch() async {
    if (!checkPlatformIsDesktop() || !state.settings.clipboardWatch || _clipboardTimer != null) {
      return;
    }
    // What is already copied is not "new": only later copies are offered.
    _lastClipboard = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    _clipboardTimer = Timer.periodic(_clipboardInterval, (_) => unawaited(_checkClipboard()));
  }

  /// Turns the browser extension integration on or off (computers only).
  Future<void> setBrowserBridge(bool enabled) async {
    state = state.copyWith(settings: state.settings.copyWith(browserBridge: enabled));
    await _persistence.setBrowserBridgeEnabled(enabled);
    if (enabled) {
      await startBrowserBridge();
    } else {
      await _bridge?.stop();
      _bridge = null;
      state = state.copyWith(bridgeRunning: false);
    }
  }

  /// New pairing code: the extension must be paired again.
  Future<void> regenerateBridgeToken() async {
    final token = generateBridgeToken();
    state = state.copyWith(settings: state.settings.copyWith(bridgeToken: token));
    await _persistence.setBrowserBridgeToken(token);
  }

  /// Starts the local receiver when the option is on. Safe to call again.
  Future<void> startBrowserBridge() async {
    if (!checkPlatformIsDesktop() || !state.settings.browserBridge || _bridge != null) {
      return;
    }
    final bridge = BrowserBridgeServer(token: () => state.settings.bridgeToken, onDownload: _onBrowserDownload);
    try {
      await bridge.start();
      _bridge = bridge;
      state = state.copyWith(bridgeRunning: true);
    } catch (e) {
      _logger.warning('Browser bridge could not start (port $browserBridgePort busy?)', e);
      state = state.copyWith(bridgeRunning: false);
    }
  }

  /// A download clicked in the browser: accepted (202) only once Aika
  /// verified the link serves a file it can download; otherwise the
  /// extension lets the browser download it as usual.
  Future<BridgeAnswer> _onBrowserDownload(BridgeDownloadRequest request) async {
    final Uri url;
    try {
      url = checkLink(request.url);
    } on LinkDownloadException catch (e) {
      return BridgeAnswer(400, {'error': e.problem.name});
    }
    if (knownPlatformOf(url) != null) {
      return const BridgeAnswer(422, {'error': 'unsupportedPlatform'});
    }
    DirectFileInfo info;
    try {
      info = await analyze(url).timeout(const Duration(seconds: 25));
    } on LinkDownloadException catch (e) {
      return BridgeAnswer(422, {'error': e.problem.name});
    } on TimeoutException {
      return const BridgeAnswer(504, {'error': 'timeout'});
    }
    final space = await checkSpace(info);
    if (space != null) {
      return BridgeAnswer(507, {'error': space.name});
    }
    final browserName = request.fileName;
    if (browserName != null) {
      // The browser may know a better name (from the page or the server).
      final name = sanitizeFileName(browserName, mimeType: info.mimeType);
      info = DirectFileInfo(
        sourceUri: info.sourceUri,
        fileUri: info.fileUri,
        fileName: name,
        mimeType: info.mimeType,
        kind: mediaKindOf(mimeType: info.mimeType, fileName: name),
        size: info.size,
        acceptsRanges: info.acceptsRanges,
        etag: info.etag,
        lastModified: info.lastModified,
        auth: info.auth,
      );
    }
    start(info, allowLarge: true);
    _browserDownloads.add(info.fileName);
    return BridgeAnswer(202, {'accepted': true, 'fileName': info.fileName});
  }

  Future<void> _checkClipboard() async {
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    final String? text;
    try {
      text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    } catch (_) {
      return;
    }
    if (text == null || text == _lastClipboard) {
      return;
    }
    _lastClipboard = text;
    final trimmed = text.trim();
    if (trimmed.isEmpty || trimmed.length > maxLinkLength || trimmed.contains(RegExp(r'\s'))) {
      return;
    }
    try {
      final uri = parseUserLink(trimmed);
      if (looksLikeDirectFileLink(uri) && state.unfinishedFor(uri) == null) {
        _clipboardLinks.add(uri);
      }
    } on LinkDownloadException {
      // Not a downloadable link.
    }
  }

  /// Starts queued downloads while fewer than the allowed number run.
  void _pump() {
    var running = state.tasks.where((t) => t.status == LinkDownloadStatus.running).length;
    for (final task in state.tasks.reversed) {
      // Oldest first.
      if (running >= state.settings.parallel) {
        break;
      }
      if (task.status == LinkDownloadStatus.queued && !_tokens.containsKey(task.id)) {
        running++;
        _update(task.id, (t) => t.copyWith(status: LinkDownloadStatus.running, bytesPerSecond: 0, connections: 0));
        unawaited(_run(task.id));
      }
    }
    unawaited(_persistQueue());
  }

  Future<void> _run(String id) async {
    final token = LinkCancelToken();
    _tokens[id] = token;
    final initial = state.taskById(id)!;
    var info = initial.info;
    try {
      final part = await _partFile(id);
      final stateFile = File('${part.path}.state.json');

      if (initial.needsRefresh) {
        final fresh = await analyze(info.sourceUri);
        if (!_sameFile(info, fresh, hasData: part.existsSync())) {
          _logger.info('Download $id: the file changed on the server, starting over');
          await _deleteParts(id);
        }
        info = DirectFileInfo(
          sourceUri: info.sourceUri,
          fileUri: fresh.fileUri,
          fileName: info.fileName,
          mimeType: fresh.mimeType ?? info.mimeType,
          kind: info.kind,
          size: fresh.size,
          acceptsRanges: fresh.acceptsRanges,
          etag: fresh.etag,
          lastModified: fresh.lastModified,
          auth: fresh.auth,
        );
        _update(id, (t) => t.copyWith(info: info, total: info.size, needsRefresh: false));
        if (token.isCancelled) {
          throw const _Stopped();
        }
      }

      final maxBytes = info.size == null && !initial.allowLarge ? largeDownloadBytes : _absoluteMaxBytes;
      final connections = state.settings.connections;
      final size = info.size;
      final segmented = connections > 1 && size != null && size >= minSegmentedSize && info.acceptsRanges && (info.etag ?? info.lastModified) != null;

      var done = false;
      if (segmented) {
        try {
          await _runSegmented(id, info, part, stateFile, connections, token);
          done = true;
        } on RangeNotSupportedException {
          _logger.info('Download $id: ranges refused, using a single connection');
          await _deleteParts(id);
        }
      }
      if (!done) {
        await _runSingle(id, info, part, token, maxBytes);
      }

      final (savedPath, savedFolder) = await _save(part, info);
      await _deleteQuietly(stateFile);
      final finalSize = state.taskById(id)?.received ?? info.size ?? 0;
      _update(id, (t) => t.copyWith(status: LinkDownloadStatus.completed, savedPath: savedPath, savedFolder: savedFolder, connections: 0, bytesPerSecond: 0));
      await _addToHistory(
        LinkDownloadRecord(
          id: id,
          url: info.sourceUri.toString(),
          fileName: p.basename(savedPath.startsWith('content://') ? info.fileName : savedPath),
          mimeType: info.mimeType,
          size: finalSize,
          savedPath: savedPath,
          savedFolder: savedFolder,
          completedAt: DateTime.now(),
        ),
      );
    } catch (e) {
      final cancelled = token.isCancelled || e is _Stopped || isSegmentedDownloadCancelled(e);
      if (cancelled && _pausing.contains(id)) {
        _update(id, (t) => t.copyWith(status: LinkDownloadStatus.paused, connections: 0, bytesPerSecond: 0));
      } else if (cancelled) {
        _update(id, (t) => t.copyWith(status: LinkDownloadStatus.cancelled, connections: 0, bytesPerSecond: 0));
        await _deleteParts(id);
      } else {
        final problem = e is LinkDownloadException ? e.problem : LinkProblem.storage;
        _logger.warning('Download $id failed', e);
        // Partial data is kept: "Réessayer" resumes when the server allows it.
        _update(id, (t) => t.copyWith(status: LinkDownloadStatus.failed, problem: problem, connections: 0, bytesPerSecond: 0));
      }
    } finally {
      _tokens.remove(id);
      _pausing.remove(id);
      _lastEmit.remove(id);
      _speedSamples.remove(id);
      _saveChains.remove(id)?.ignore();
      _pump();
    }
  }

  /// Several connections at once, resumable from the saved ranges.
  Future<void> _runSegmented(String id, DirectFileInfo info, File part, File stateFile, int connections, LinkCancelToken token) async {
    final size = info.size!;
    final validator = info.etag ?? info.lastModified;
    var segments = await _loadSegments(stateFile, size, validator);
    if (segments == null || !part.existsSync()) {
      await _deleteQuietly(part);
      segments = planSegments(size, connections);
    }
    await SegmentedDownload(
      http: _http,
      info: info,
      file: part,
      segments: segments,
      connections: connections,
      cancelToken: token,
      onProgress: (received, active) => _onProgress(id, received, size, active),
      onCheckpoint: (current) => _saveSegments(id, stateFile, size, validator, current),
    ).run();
    _onProgress(id, size, size, 0, force: true);
  }

  /// Classic single connection, resuming from the partial file when the
  /// server allows it, with automatic retries after network errors.
  Future<void> _runSingle(String id, DirectFileInfo info, File part, LinkCancelToken token, int maxBytes) async {
    for (var attempt = 0; ; attempt++) {
      try {
        final size = await _http.download(
          info: info,
          partFile: part,
          cancelToken: token,
          maxBytes: maxBytes,
          onProgress: (received, total) => _onProgress(id, received, total, 1),
        );
        _onProgress(id, size, size, 0, force: true);
        _update(id, (t) => t.copyWith(retry: 0));
        return;
      } on LinkDownloadException catch (e) {
        if (!e.isTransient || attempt >= _retryDelays.length || token.isCancelled) {
          rethrow;
        }
        _logger.info('Download $id interrupted (${e.problem.name}), retry ${attempt + 1}');
        _update(id, (t) => t.copyWith(retry: attempt + 1));
        await Future<void>.delayed(_retryDelays[attempt]);
        if (token.isCancelled) {
          rethrow;
        }
      }
    }
  }

  /// Whether the partial data of [saved] can be kept for [fresh]: same
  /// size and same validator (ETag or Last-Modified).
  bool _sameFile(DirectFileInfo saved, DirectFileInfo fresh, {required bool hasData}) {
    if (!hasData) {
      return true;
    }
    if (saved.size != fresh.size) {
      return false;
    }
    if (saved.etag != null) {
      return saved.etag == fresh.etag;
    }
    if (saved.lastModified != null) {
      return saved.lastModified == fresh.lastModified;
    }
    return false; // Nothing proves it is the same file.
  }

  void _onProgress(String id, int received, int? total, int connections, {bool force = false}) {
    final now = DateTime.now();
    final last = _lastEmit[id];
    if (!force && last != null && now.difference(last) < _progressInterval) {
      return; // Limit rebuilds to a few per second.
    }
    _lastEmit[id] = now;

    // Speed over the last second or so, smoothed.
    final sample = _speedSamples[id];
    var speed = state.taskById(id)?.bytesPerSecond ?? 0;
    if (sample == null || received < sample.$2) {
      _speedSamples[id] = (now, received);
    } else {
      final seconds = now.difference(sample.$1).inMilliseconds / 1000;
      if (seconds >= 1) {
        final instant = (received - sample.$2) / seconds;
        speed = speed == 0 ? instant : speed * 0.6 + instant * 0.4;
        _speedSamples[id] = (now, received);
      }
    }
    _update(id, (t) => t.copyWith(received: received, total: total, bytesPerSecond: speed, connections: connections, retry: 0));
  }

  void _update(String id, LinkDownloadTask Function(LinkDownloadTask) change) {
    state = state.copyWith(tasks: [for (final t in state.tasks) t.id == id ? change(t) : t]);
  }

  /// Saves unfinished downloads so they come back (paused) after a restart.
  Future<void> _persistQueue() async {
    final unfinished = state.tasks.where(
      (t) => t.status != LinkDownloadStatus.completed && t.status != LinkDownloadStatus.cancelled,
    );
    await _persistence.setLinkDownloadQueue(unfinished.map((t) => t.toJson()).toList());
  }

  Future<List<RangeSegment>?> _loadSegments(File stateFile, int size, String? validator) async {
    try {
      if (!stateFile.existsSync()) {
        return null;
      }
      final json = jsonDecode(await stateFile.readAsString()) as Map<String, dynamic>;
      if (json['size'] != size || json['validator'] != validator) {
        return null;
      }
      final segments = (json['segments'] as List).map(RangeSegment.tryFromJson).toList();
      if (segments.any((s) => s == null)) {
        return null;
      }
      final list = segments.cast<RangeSegment>();
      return segmentsCoverFile(list, size) ? list : null;
    } catch (_) {
      return null;
    }
  }

  /// Written to a temporary file then renamed, so a crash never leaves a
  /// half-written state. Saves of one download run one after the other.
  Future<void> _saveSegments(String id, File stateFile, int size, String? validator, List<RangeSegment> segments) {
    // Serialized now: the ranges keep changing while the write waits.
    final content = jsonEncode({'size': size, 'validator': validator, 'segments': segments.map((s) => s.toJson()).toList()});
    Future<void> write() async {
      try {
        final tmp = File('${stateFile.path}.tmp');
        await tmp.writeAsString(content, flush: true);
        await tmp.rename(stateFile.path);
      } catch (e) {
        _logger.fine('Could not save download state', e);
      }
    }

    final next = (_saveChains[id] ?? Future<void>.value()).then((_) => write());
    _saveChains[id] = next;
    return next;
  }

  /// Partial file in the app's own storage (never in the cache, which the
  /// system may clear during a long download). Files that belong to no
  /// known download are removed once.
  Future<File> _partFile(String id) async {
    final dir = await _partsDirectory();
    if (!_partsCleaned) {
      _partsCleaned = true;
      final known = state.tasks.map((t) => t.id).toSet();
      if (dir.existsSync()) {
        for (final entity in dir.listSync()) {
          final name = p.basename(entity.path);
          if (entity is File && !known.any((k) => name.startsWith('$k.part'))) {
            await _deleteQuietly(entity);
          }
        }
      }
    }
    return File(p.join(dir.path, '$id.part'));
  }

  Future<Directory> _partsDirectory() async {
    final dir = Directory(p.join((await path_provider.getApplicationSupportDirectory()).path, 'link_downloads'));
    await dir.create(recursive: true);
    return dir;
  }

  Future<void> _deleteParts(String id) async {
    final dir = await _partsDirectory();
    for (final suffix in ['.part', '.part.state.json', '.part.state.json.tmp']) {
      await _deleteQuietly(File(p.join(dir.path, '$id$suffix')));
    }
  }

  /// Where downloaded files go: the receive folder chosen in the settings
  /// (when it is a plain folder) or the system's Downloads, in an "Aika"
  /// sub-folder.
  Future<String> _destination() async {
    final custom = ref.read(settingsProvider).destination;
    if (custom != null && !custom.startsWith('content://')) {
      return custom;
    }
    return getDefaultDestinationDirectory();
  }

  /// Moves the completed [part] to its destination; returns the saved path
  /// (or `content://` URI) and its folder.
  Future<(String, String)> _save(File part, DirectFileInfo info) async {
    final destination = await _destination();
    final mimeType = info.mimeType ?? lookupMimeType(info.fileName) ?? 'application/octet-stream';
    if (destination == kAndroidDefaultDownloadsMarker) {
      // Android 10+: MediaStore Downloads, no storage permission needed.
      final uri = await android_channel.copyFileToDownloadsAndroid(
        sourcePath: part.path,
        fileName: legalizeFilename(info.fileName, os: Platform.operatingSystem),
        relativePath: 'Download/$linkDownloadFolderName/',
        mimeType: mimeType,
      );
      await _deleteQuietly(part);
      return (uri, kAndroidDefaultDownloadsMarker);
    }

    // Same name already there → "nom (2).ext" (never overwritten).
    final (target, _, _) = await digestFilePathAndPrepareDirectory(
      parentDirectory: destination,
      fileName: '$linkDownloadFolderName/${info.fileName}',
      createdDirectories: <String>{},
    );
    try {
      await part.rename(target);
    } on FileSystemException {
      // Different volume: copy, then remove the partial file.
      await part.copy(target);
      await _deleteQuietly(part);
    }
    return (target, p.dirname(target));
  }

  Future<void> _addToHistory(LinkDownloadRecord record) async {
    final others = state.history.where((r) => r.url != record.url);
    await _setHistory([record, ...others].take(_maxHistory).toList());
    await _persistQueue();
  }

  Future<void> _setHistory(List<LinkDownloadRecord> history) async {
    state = state.copyWith(history: history);
    await _persistence.setLinkDownloadHistory(history.map((r) => jsonEncode(r.toJson())).toList());
  }
}

/// Stop requested while the link was being analysed again.
class _Stopped implements Exception {
  const _Stopped();
}

Future<void> _deleteQuietly(File? file) async {
  try {
    if (file != null && file.existsSync()) {
      await file.delete();
    }
  } catch (_) {}
}
