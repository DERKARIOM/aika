import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:uri_content/uri_content.dart';

/// Image behind an Android `content://` URI, e.g. a photo picked with the
/// system picker: the app has no file path for it, only the URI.
///
/// Keyed by the URI, so Flutter's image cache keeps the decoded picture
/// like any other: it is read once, not on every scroll. Wrap it in a
/// [ResizeImage] to decode at display size.
@immutable
class ContentUriImage extends ImageProvider<ContentUriImage> {
  final String uri;

  const ContentUriImage(this.uri);

  static final _content = UriContent();

  @override
  Future<ContentUriImage> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(ContentUriImage key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(codec: _load(key, decode), scale: 1, debugLabel: uri);
  }

  Future<ui.Codec> _load(ContentUriImage key, ImageDecoderCallback decode) async {
    final bytes = await _content.fromOrNull(Uri.parse(uri));
    if (bytes == null || bytes.isEmpty) {
      // Not cached as a failure: the permission may come back later.
      scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(key));
      throw StateError('Cannot read $uri');
    }
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  @override
  bool operator ==(Object other) => other is ContentUriImage && other.uri == uri;

  @override
  int get hashCode => uri.hashCode;
}
