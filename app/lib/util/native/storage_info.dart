import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:localsend_app/util/native/directories.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart' as path;

final _logger = Logger('StorageInfo');

/// Space of the storage volume Aika saves received files to.
///
/// [freeBytes] is the space still available to apps (not the space Aika
/// used); [totalBytes] is `null` when the platform does not report it.
@immutable
class StorageInfo {
  final int? totalBytes;
  final int freeBytes;

  const StorageInfo({required this.totalBytes, required this.freeBytes});

  /// Space in use, when the total is known.
  int? get usedBytes {
    final total = totalBytes;
    if (total == null) {
      return null;
    }
    return (total - freeBytes).clamp(0, total);
  }

  /// Share of the volume in use, from 0 to 1, when the total is known.
  double? get usedFraction {
    final total = totalBytes;
    final used = usedBytes;
    if (total == null || used == null || total <= 0) {
      return null;
    }
    return used / total;
  }
}

const _iosChannel = MethodChannel('ios-delegate-channel');
const _timeout = Duration(seconds: 5);

/// Reads the real storage space of this device, or `null` when it cannot be
/// read reliably here (the page then simply hides the storage card).
///
/// - Android, Linux, macOS: `df` on the app's storage / the folder received
///   files go to (no extra plugin, no permission needed).
/// - iOS: the volume capacity reported by the system (AppDelegate.swift).
/// - Windows: GetDiskFreeSpaceExW on the receive folder's drive.
Future<StorageInfo?> readStorageInfo({String? destination}) async {
  try {
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return await _readIos();
      case TargetPlatform.windows:
        return _readWindows(await _desktopFolder(destination));
      case TargetPlatform.android:
        return await _readDf((await path.getApplicationDocumentsDirectory()).path);
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
        return await _readDf(await _desktopFolder(destination));
      case TargetPlatform.fuchsia:
        return null;
    }
  } catch (e) {
    _logger.info('Storage info unavailable: $e');
    return null;
  }
}

/// The folder received files go to, falling back to the home folder while
/// it does not exist yet.
Future<String> _desktopFolder(String? destination) async {
  final folder = destination ?? await getDefaultDestinationDirectory();
  if (Directory(folder).existsSync()) {
    return folder;
  }
  return Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? Directory.current.path;
}

Future<StorageInfo?> _readIos() async {
  final result = await _iosChannel.invokeMapMethod<String, Object?>('getStorageInfo').timeout(_timeout);
  final free = result?['free'];
  final total = result?['total'];
  if (free is! int || free < 0) {
    return null;
  }
  return StorageInfo(totalBytes: total is int && total > 0 ? total : null, freeBytes: free);
}

/// `df -kP` prints one POSIX line per volume:
/// `Filesystem 1024-blocks Used Available Capacity Mounted-on`.
final _dfLine = RegExp(r'^(.*?)\s+(\d+)\s+(\d+)\s+(\d+)\s+\d+%\s+(.*)$');

Future<StorageInfo?> _readDf(String folder) async {
  // Some Android builds ship a `df` without -P: plain -k prints the same
  // columns.
  for (final flags in const ['-kP', '-k']) {
    final result = await Process.run('df', [flags, folder]).timeout(_timeout);
    if (result.exitCode == 0) {
      final info = parseDfOutput(result.stdout as String);
      if (info != null) {
        return info;
      }
    }
  }
  return null;
}

/// Parses `df -kP` output; `null` when it is not in the expected format.
@visibleForTesting
StorageInfo? parseDfOutput(String output) {
  final lines = output.trim().split('\n');
  for (final line in lines.skip(1).toList().reversed) {
    final match = _dfLine.firstMatch(line.trim());
    if (match == null) {
      continue;
    }
    final totalKb = int.parse(match.group(2)!);
    final freeKb = int.parse(match.group(4)!);
    if (totalKb <= 0) {
      return null;
    }
    return StorageInfo(totalBytes: totalKb * 1024, freeBytes: freeKb * 1024);
  }
  return null;
}

typedef _GetDiskFreeSpaceExNative = Int32 Function(Pointer<Utf16>, Pointer<Uint64>, Pointer<Uint64>, Pointer<Uint64>);
typedef _GetDiskFreeSpaceExDart = int Function(Pointer<Utf16>, Pointer<Uint64>, Pointer<Uint64>, Pointer<Uint64>);

StorageInfo? _readWindows(String folder) {
  final getDiskFreeSpaceEx = DynamicLibrary.open(
    'kernel32.dll',
  ).lookupFunction<_GetDiskFreeSpaceExNative, _GetDiskFreeSpaceExDart>('GetDiskFreeSpaceExW');
  final folderPtr = folder.toNativeUtf16();
  final available = calloc<Uint64>();
  final total = calloc<Uint64>();
  final totalFree = calloc<Uint64>();
  try {
    if (getDiskFreeSpaceEx(folderPtr, available, total, totalFree) == 0 || total.value <= 0) {
      return null;
    }
    return StorageInfo(totalBytes: total.value, freeBytes: available.value);
  } finally {
    calloc.free(folderPtr);
    calloc.free(available);
    calloc.free(total);
    calloc.free(totalFree);
  }
}
