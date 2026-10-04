import 'package:flutter/services.dart';

// Must match the channel registered in Aika's `MainActivity.kt` (and used
// by `app/lib/util/native/channel/android_channel.dart`). With the old
// LocalSend name nobody answers: the call never completes and every
// `content://` upload (chat attachments, files picked on Android) hangs.
const _methodChannel = MethodChannel('com.naniger.aika/localsend');

/// An unanswered platform call would block the upload forever; fail it
/// instead, so the sender reports an error and retries later.
const _fileDescriptorTimeout = Duration(seconds: 15);

/// Opens [uri] for reading and returns an owned Linux file descriptor.
///
/// The descriptor stays open after this call and must be closed by the native
/// consumer it is passed to.
Future<int> getFileDescriptorAndroid({required String uri}) async {
  final fileDescriptor = await _methodChannel
      .invokeMethod<int>('getFileDescriptor', {
        'uri': uri,
      })
      .timeout(_fileDescriptorTimeout);
  if (fileDescriptor == null) {
    throw StateError('Android returned no file descriptor for $uri');
  }
  return fileDescriptor;
}
