import 'package:dart_mappable/dart_mappable.dart';
import 'package:flutter/services.dart';
import 'package:localsend_app/util/native/content_uri_helper.dart';
import 'package:logging/logging.dart';

part 'android_channel.mapper.dart';

const _methodChannel = MethodChannel('com.naniger.aika/localsend');
final _logger = Logger('AndroidSaf');

/// From Android 10 and above, we need to use the Storage Access Framework (SAF) to access files due to the scoped storage.
/// SAF itself is available from Android 4.4 (API level 19).
/// We implemented our own algorithm to build encode and decode content URIs.
/// Older versions might also work but the encoded content URI is not guaranteed to work with our algorithm.
const contentUriMinSdk = 27;

Future<PickDirectoryResult?> pickDirectoryAndroid() async {
  final result = await _methodChannel.invokeMethod<Map>('pickDirectory');
  if (result == null) {
    return null;
  }

  return PickDirectoryResultMapper.fromJson({
    'directoryUri': result['directoryUri'],
    'files': (result['files'] as List).map((e) => FileInfoMapper.fromJson((e as Map).cast<String, dynamic>())).toList(),
  });
}

Future<String?> pickDirectoryPathAndroid() async {
  final result = await _methodChannel.invokeMethod<String>('pickDirectoryPath');
  return result;
}

Future<List<FileInfo>?> pickFilesAndroid() async {
  final result = await _methodChannel.invokeMethod<List>('pickFiles');
  if (result == null) {
    return null;
  }

  return result.map((e) => FileInfoMapper.fromJson((e as Map).cast<String, dynamic>())).toList();
}

Future<bool> getSystemAnimationsStatusAndroid() async {
  return await _methodChannel.invokeMethod('isAnimationsEnabled') ?? true;
}

Future<void> createDirectory({
  required String documentUri,
  required String directoryName,
}) async {
  _logger.info('Creating directory "$directoryName" in $documentUri');
  await _methodChannel.invokeMethod('createDirectory', {
    'documentUri': documentUri,
    'directoryName': directoryName,
  });
}

Future<void> createMissingDirectoriesAndroid({
  required String parentUri,
  required String fileName,
  required Set<String> createdDirectories,
}) async {
  final parts = fileName.split('/');
  for (int i = 0; i < parts.length - 1; i++) {
    final subDirPath = parts.sublist(0, i + 1).join('/');
    if (createdDirectories.contains(subDirPath)) {
      continue;
    }

    await createDirectory(
      documentUri: ContentUriHelper.convertTreeUriToDocumentUri(
        treeUri: parentUri,
        suffix: i == 0 ? null : parts.sublist(0, i).join('/'),
      ),
      directoryName: parts[i],
    );
    createdDirectories.add(subDirPath);
  }
}

class CreatedFileAndroid {
  /// The URI of the created document. Android may rename the file on collisions.
  final String uri;

  /// An owned writable Linux file descriptor. It stays open after this call and
  /// must be closed by the native consumer it is passed to.
  final int fileDescriptor;

  CreatedFileAndroid({required this.uri, required this.fileDescriptor});
}

/// Creates a new file inside a SAF directory (a tree or document URI)
/// and opens it for writing.
Future<CreatedFileAndroid> createFileAndroid({
  required String parentUri,
  required String fileName,
  required String mimeType,
}) async {
  final result = await _methodChannel.invokeMethod<Map>('createFile', {
    'parentUri': parentUri,
    'fileName': fileName,
    'mimeType': mimeType,
  });
  if (result == null) {
    throw StateError('Android could not create $fileName in $parentUri');
  }
  return CreatedFileAndroid(
    uri: result['uri'] as String,
    fileDescriptor: result['fd'] as int,
  );
}

Future<void> openContentUri({
  required String uri,
}) async {
  _logger.info('Opening content URI: $uri');
  await _methodChannel.invokeMethod('openContentUri', {
    'uri': uri,
  });
}

Future<void> openGallery() async {
  _logger.info('Opening gallery');
  await _methodChannel.invokeMethod('openGallery');
}

/// Result of a successful [startLocalOnlyHotspotAndroid] call.
class LocalOnlyHotspotInfo {
  /// The generated SSID of the local-only hotspot, if the platform reported one.
  final String? ssid;

  /// The generated WPA2 passphrase of the local-only hotspot, if the platform reported one.
  final String? passphrase;

  const LocalOnlyHotspotInfo({required this.ssid, required this.passphrase});
}

/// Thrown when [startLocalOnlyHotspotAndroid] fails.
/// [code] mirrors the native error code (e.g. "PERMISSION_DENIED", "HOTSPOT_FAILED",
/// "UNSUPPORTED", "UNAVAILABLE") so the caller can decide how to react (e.g. show a
/// permission dialog vs. a generic "open Settings" fallback).
class LocalOnlyHotspotException implements Exception {
  final String code;
  final String? message;

  const LocalOnlyHotspotException({required this.code, this.message});

  @override
  String toString() => 'LocalOnlyHotspotException($code: $message)';
}

/// Starts (or reuses, if already active) a local-only Wi-Fi hotspot via
/// `WifiManager.startLocalOnlyHotspot()`.
///
/// Requires Android 8.0 (API 26) or higher, and the NEARBY_WIFI_DEVICES (Android 13+) or
/// ACCESS_FINE_LOCATION (Android 12 and below) runtime permission to already be granted;
/// the caller is responsible for requesting it beforehand (see [Permission] usage in
/// the hotspot provider). Throws [LocalOnlyHotspotException] on any failure — the caller
/// should fall back to [openHotspotSettingsAndroid] in that case rather than retrying blindly.
Future<LocalOnlyHotspotInfo> startLocalOnlyHotspotAndroid() async {
  try {
    final result = await _methodChannel.invokeMethod<Map>('startLocalOnlyHotspot');
    return LocalOnlyHotspotInfo(
      ssid: result?['ssid'] as String?,
      passphrase: result?['passphrase'] as String?,
    );
  } on PlatformException catch (e) {
    throw LocalOnlyHotspotException(code: e.code, message: e.message);
  }
}

/// Stops the local-only hotspot started by [startLocalOnlyHotspotAndroid], if any.
/// Safe to call even if no hotspot is currently active.
Future<void> stopLocalOnlyHotspotAndroid() async {
  await _methodChannel.invokeMethod('stopLocalOnlyHotspot');
}

/// Opens the system "Hotspot & tethering" settings screen (falling back to the general
/// wireless settings screen if that specific one is not resolvable on this OEM/ROM).
/// Used when [startLocalOnlyHotspotAndroid] is unsupported/fails/is denied, so the user
/// can enable a hotspot manually.
Future<void> openHotspotSettingsAndroid() async {
  await _methodChannel.invokeMethod('openHotspotSettings');
}

/// Thrown when [joinWifiNetworkAndroid] fails.
/// [code] mirrors the native error code (e.g. "UNSUPPORTED", "INVALID_ARGUMENT",
/// "UNAVAILABLE", "JOIN_FAILED").
class WifiJoinException implements Exception {
  final String code;
  final String? message;

  const WifiJoinException({required this.code, this.message});

  @override
  String toString() => 'WifiJoinException($code: $message)';
}

/// Requests a connection to the Wi-Fi network [ssid]/[passphrase] via
/// `WifiNetworkSpecifier` (Android 10+/API 29+) and, once connected, binds this
/// process's network traffic to it via `ConnectivityManager.bindProcessToNetwork()`.
///
/// Used on the *scanning* device of the Smart QR Code pairing feature to automatically
/// join the emitter's freshly created local-only hotspot, so the pairing HTTP call can
/// reach it without the user having to join the network by hand first.
///
/// The binding affects the whole app process, not just one request: callers MUST call
/// [unbindWifiNetworkAndroid] as soon as they no longer need it (right after the pairing
/// HTTP call completes, success or failure), so the app doesn't stay cut off from its
/// normal network route. Throws [WifiJoinException] on any failure — the caller should
/// treat this as "could not auto-join" and fall back to whatever it would have done if no
/// Wi-Fi credentials had been provided at all (e.g. the user already joined manually).
Future<bool> joinWifiNetworkAndroid({required String ssid, required String? passphrase}) async {
  try {
    final result = await _methodChannel.invokeMethod<bool>('joinWifiNetwork', {
      'ssid': ssid,
      'passphrase': passphrase,
    });
    return result ?? false;
  } on PlatformException catch (e) {
    throw WifiJoinException(code: e.code, message: e.message);
  }
}

/// Undoes the effect of [joinWifiNetworkAndroid]: unbinds this process from the joined
/// network and releases the underlying network request. Safe to call even if no join was
/// ever attempted or it already failed.
Future<void> unbindWifiNetworkAndroid() async {
  await _methodChannel.invokeMethod('unbindWifiNetwork');
}

@MappableClass()
/// Result of a successful [shareOwnApkAndroid] call — everything is resolved dynamically
/// from the currently installed app on the native side (see MainActivity.shareOwnApk),
/// never hardcoded, so it automatically reflects whichever Aika version is running.
class OwnApkShareResult {
  final String appName;
  final String versionName;
  final int versionCode;
  final int sizeBytes;
  final String fileName;

  const OwnApkShareResult({
    required this.appName,
    required this.versionName,
    required this.versionCode,
    required this.sizeBytes,
    required this.fileName,
  });
}

/// "Partager Aika": triggers Android's native Sharesheet (`ACTION_SEND`) with Aika's own
/// currently installed APK, so the user can send it to a nearby device — via Bluetooth,
/// Nearby Share/Quick Share, or any other app Android offers — including a device that
/// does not have Aika installed yet.
///
/// Aika deliberately does not manage Bluetooth (or any other transport) itself here: the
/// recipient device does not have Aika, so there would be no Aika process on that side to
/// speak a custom protocol to. Handing the file to Android's own Sharesheet lets the
/// system's own built-in receivers (which exist independently of whether Aika is
/// installed) take over, and it naturally surfaces whichever nearby-sharing option is
/// actually available on this device — Aika never claims a specific transport works when
/// Android doesn't actually offer it.
///
/// Throws on failure (e.g. [PlatformException] with code "APK_NOT_FOUND" if the running
/// app's own APK file could not be located, or "SHARE_FAILED" for any other native error).
Future<OwnApkShareResult> shareOwnApkAndroid() async {
  final result = await _methodChannel.invokeMethod<Map>('shareOwnApk');
  if (result == null) {
    throw StateError("Could not resolve or share Aika's own APK");
  }
  return OwnApkShareResult(
    appName: result['appName'] as String,
    versionName: result['versionName'] as String,
    versionCode: result['versionCode'] as int,
    sizeBytes: result['sizeBytes'] as int,
    fileName: result['fileName'] as String,
  );
}

class PickDirectoryResult with PickDirectoryResultMappable {
  final String directoryUri;
  final List<FileInfo> files;

  PickDirectoryResult({
    required this.directoryUri,
    required this.files,
  });
}

@MappableClass()
class FileInfo with FileInfoMappable {
  final String name;
  final int size;
  final String uri;
  final int lastModified;

  FileInfo({
    required this.name,
    required this.size,
    required this.uri,
    required this.lastModified,
  });
}
