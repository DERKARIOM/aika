import 'dart:io' show Directory, Platform;

import 'package:flutter/foundation.dart';
import 'package:localsend_app/provider/device_info_provider.dart';
import 'package:localsend_app/util/native/channel/android_channel.dart' as android_channel;
import 'package:path_provider/path_provider.dart' as path;
import 'package:refena_flutter/refena_flutter.dart';

/// Sentinel returned by [getDefaultDestinationDirectory] on Android 10+ (API 29+)
/// instead of a real filesystem path. Under Scoped Storage, a raw path to the public
/// Download folder is no longer reliably writable, so this marker tells the save
/// pipeline (see file_saver.dart) to create incoming files through MediaStore's
/// "Downloads" collection instead. It is never persisted to settings (a `null`
/// destination already means "use the default" -- see persistence_provider.dart) and
/// never shown to the user as-is (see receive_options_page.dart / open_folder.dart,
/// which special-case it).
const kAndroidDefaultDownloadsMarker = 'aika-downloads://default';

Future<String> getDefaultDestinationDirectory() async {
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      final androidSdkInt = RefenaScope.defaultRef.read(deviceRawInfoProvider).androidSdkInt;
      if (androidSdkInt != null && androidSdkInt >= android_channel.mediaStoreDownloadsMinSdk) {
        // Android 10+: Scoped Storage applies, so route through MediaStore (see marker
        // doc comment above) instead of a plain path.
        return kAndroidDefaultDownloadsMarker;
      }
      // Android 9 and below: Scoped Storage does not apply, so a plain path still works.
      // path_provider resolves this dynamically via
      // Environment.getExternalStoragePublicDirectory(DIRECTORY_DOWNLOADS) -- never
      // hardcoded here.
      final dir = await path.getDownloadsDirectory();
      if (dir != null) {
        return dir.path;
      }
      // Extremely unlikely (e.g. no external storage mounted on this device/OEM): fall
      // back to the app's own sandboxed directory rather than guessing a system path
      // that may not exist here.
      return (await path.getApplicationDocumentsDirectory()).path;
    case TargetPlatform.iOS:
      return (await path.getApplicationDocumentsDirectory()).path;
    case TargetPlatform.linux:
    case TargetPlatform.macOS:
    case TargetPlatform.windows:
    case TargetPlatform.fuchsia:
      var downloadDir = await path.getDownloadsDirectory();
      if (downloadDir == null) {
        if (defaultTargetPlatform == TargetPlatform.windows) {
          downloadDir = Directory('${Platform.environment['HOMEPATH']}/Downloads');
          if (!downloadDir.existsSync()) {
            downloadDir = Directory(Platform.environment['HOMEPATH']!);
          }
        } else {
          downloadDir = Directory('${Platform.environment['HOME']}/Downloads');
          if (!downloadDir.existsSync()) {
            downloadDir = Directory(Platform.environment['HOME']!);
          }
        }
      }
      return downloadDir.path.replaceAll('\\', '/');
  }
}

Future<String> getCacheDirectory() async {
  return (await path.getTemporaryDirectory()).path;
}

/// Persistent (i.e. never auto-cleared, unlike [getCacheDirectory]) folder
/// used to store chat media attachments (images/videos/documents received
/// in a conversation), separate from the user's chosen download
/// destination so chat history stays self-contained and browsable from the
/// conversation itself.
Future<String> getChatMediaDirectory() async {
  final base = await path.getApplicationSupportDirectory();
  final dir = Directory('${base.path}/chat_media');
  if (!dir.existsSync()) {
    await dir.create(recursive: true);
  }
  return dir.path;
}
