import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:logging/logging.dart';
import 'package:pasteboard/pasteboard.dart';

final _logger = Logger('FileClipboard');

/// Image extensions iOS can put on its pasteboard as an image.
const _imageExtensions = {'.png', '.jpg', '.jpeg', '.heic', '.heif', '.gif', '.webp', '.bmp'};

/// Received files that can be copied to the clipboard, so they can be pasted
/// straight into another app (file manager, mail, chat…).
///
/// - Windows, macOS, Linux: the files themselves (like Ctrl+C in a file
///   manager), any number of them.
/// - iOS: a single image (the system pasteboard holds images, not files).
/// - Android: not available (the clipboard plugin cannot write files there).
///
/// Only files that still exist are kept; empty when nothing can be copied.
List<String> copyableReceivedFiles(Iterable<String?> paths) {
  final existing = paths.whereType<String>().where((path) => path.isNotEmpty && File(path).existsSync()).toList();
  if (checkPlatformIsDesktop()) {
    return existing;
  }
  if (defaultTargetPlatform == TargetPlatform.iOS && existing.length == 1 && _isImage(existing.single)) {
    return existing;
  }
  return const [];
}

bool _isImage(String path) {
  final dot = path.lastIndexOf('.');
  return dot >= 0 && _imageExtensions.contains(path.substring(dot).toLowerCase());
}

/// Copies [paths] (from [copyableReceivedFiles]) to the clipboard.
/// Returns whether it worked.
Future<bool> copyReceivedFilesToClipboard(List<String> paths) async {
  if (paths.isEmpty) {
    return false;
  }
  try {
    if (checkPlatformIsDesktop()) {
      return await Pasteboard.writeFiles(paths);
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await Pasteboard.writeImage(await File(paths.single).readAsBytes());
      return true;
    }
  } catch (e) {
    _logger.warning('Could not copy files to the clipboard', e);
  }
  return false;
}
