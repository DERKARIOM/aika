import 'dart:convert';

/// What kind of content a link points to, used for the icon and the label.
enum LinkMediaKind { image, video, audio, document, archive, other }

/// Common MIME types and their usual extension. Kept local (not the `mime`
/// package's reverse lookup) so the result is stable across versions.
const _extensionByMime = {
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/gif': 'gif',
  'image/webp': 'webp',
  'image/avif': 'avif',
  'image/heic': 'heic',
  'image/heif': 'heif',
  'image/bmp': 'bmp',
  'image/svg+xml': 'svg',
  'image/tiff': 'tiff',
  'video/mp4': 'mp4',
  'video/webm': 'webm',
  'video/quicktime': 'mov',
  'video/x-matroska': 'mkv',
  'video/x-msvideo': 'avi',
  'video/3gpp': '3gp',
  'audio/mpeg': 'mp3',
  'audio/mp4': 'm4a',
  'audio/aac': 'aac',
  'audio/ogg': 'ogg',
  'audio/wav': 'wav',
  'audio/x-wav': 'wav',
  'audio/flac': 'flac',
  'audio/webm': 'weba',
  'application/pdf': 'pdf',
  'application/epub+zip': 'epub',
  'application/zip': 'zip',
  'application/x-7z-compressed': '7z',
  'application/vnd.rar': 'rar',
  'application/x-rar-compressed': 'rar',
  'application/gzip': 'gz',
  'application/x-tar': 'tar',
  'application/msword': 'doc',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document': 'docx',
  'application/vnd.ms-excel': 'xls',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': 'xlsx',
  'application/vnd.ms-powerpoint': 'ppt',
  'application/vnd.openxmlformats-officedocument.presentationml.presentation': 'pptx',
  'application/vnd.oasis.opendocument.text': 'odt',
  'application/vnd.oasis.opendocument.spreadsheet': 'ods',
  'application/vnd.android.package-archive': 'apk',
  'application/json': 'json',
  'text/plain': 'txt',
  'text/csv': 'csv',
};

const _archiveExtensions = {'zip', '7z', 'rar', 'gz', 'tar', 'tgz', 'bz2', 'xz'};
const _documentExtensions = {'pdf', 'epub', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'odt', 'ods', 'odp', 'txt', 'csv', 'json', 'rtf', 'md'};

/// `image/jpeg; charset=…` → `image/jpeg`; `null` when absent.
String? normalizeMimeType(String? contentType) {
  if (contentType == null) {
    return null;
  }
  final mime = contentType.split(';').first.trim().toLowerCase();
  return mime.isEmpty ? null : mime;
}

/// Usual extension for [mimeType], without the dot.
String? extensionForMime(String? mimeType) => _extensionByMime[normalizeMimeType(mimeType)];

/// Kind of content from its MIME type, falling back to the file extension.
LinkMediaKind mediaKindOf({String? mimeType, required String fileName}) {
  final mime = normalizeMimeType(mimeType) ?? '';
  final ext = _extensionOf(fileName);
  if (mime.startsWith('image/')) {
    return LinkMediaKind.image;
  }
  if (mime.startsWith('video/')) {
    return LinkMediaKind.video;
  }
  if (mime.startsWith('audio/')) {
    return LinkMediaKind.audio;
  }
  final byMime = _extensionByMime[mime];
  for (final candidate in [byMime, ext]) {
    if (candidate == null) {
      continue;
    }
    if (_archiveExtensions.contains(candidate)) {
      return LinkMediaKind.archive;
    }
    if (_documentExtensions.contains(candidate)) {
      return LinkMediaKind.document;
    }
  }
  final byExtension = _extensionByMime.entries.where((e) => e.value == ext).map((e) => e.key).firstOrNull;
  if (byExtension != null && byExtension.contains('/')) {
    final type = byExtension.split('/').first;
    switch (type) {
      case 'image':
        return LinkMediaKind.image;
      case 'video':
        return LinkMediaKind.video;
      case 'audio':
        return LinkMediaKind.audio;
    }
  }
  return LinkMediaKind.other;
}

/// File name announced by the server in `Content-Disposition`, preferring
/// the UTF-8 `filename*` form (RFC 6266 / 5987). `null` when absent.
String? fileNameFromContentDisposition(String? header) {
  if (header == null || header.isEmpty) {
    return null;
  }
  final extended = RegExp(r"""filename\*\s*=\s*([^']*)'[^']*'([^;]+)""", caseSensitive: false).firstMatch(header);
  if (extended != null) {
    final charset = extended.group(1)!.trim().toLowerCase();
    final value = extended.group(2)!.trim().replaceAll('"', '');
    final bytes = _percentDecode(value);
    if (bytes != null) {
      return charset == 'iso-8859-1' ? latin1.decode(bytes, allowInvalid: true) : utf8.decode(bytes, allowMalformed: true);
    }
  }
  final quoted = RegExp(r'filename\s*=\s*"((?:[^"\\]|\\.)*)"', caseSensitive: false).firstMatch(header);
  if (quoted != null) {
    return quoted.group(1)!.replaceAllMapped(RegExp(r'\\(.)'), (m) => m.group(1)!);
  }
  final token = RegExp(r'filename\s*=\s*([^;\s]+)', caseSensitive: false).firstMatch(header);
  return token?.group(1);
}

/// Last segment of the link's path (`/media/photo%20été.jpg` →
/// `photo été.jpg`), `null` when the path ends with `/`.
String? fileNameFromUri(Uri uri) {
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  return segments.isEmpty ? null : segments.last;
}

/// Characters refused by at least one supported system, plus control
/// characters.
final _forbidden = RegExp(r'[<>:"/\\|?*\x00-\x1F\x7F]');
final _reservedWindowsName = RegExp(r'^(con|prn|aux|nul|com[0-9]|lpt[0-9])(\..*)?$', caseSensitive: false);

/// Longest file name kept, in characters (well below the 255-byte limit
/// of the usual file systems, accents included).
const maxFileNameLength = 120;

/// Builds a safe file name from what the server and the link announce:
/// - removes any folder part (`../../x`, `C:\x`) and forbidden characters;
/// - never starts with a dot (hidden file) nor ends with a dot or space;
/// - avoids Windows reserved names (`CON`, `NUL`, ...);
/// - adds the extension matching [mimeType] when missing;
/// - keeps the extension when shortening a long name.
String sanitizeFileName(String? candidate, {String? mimeType, String fallback = 'telechargement'}) {
  var name = (candidate ?? '').replaceAll('\\', '/').split('/').last;
  name = name.replaceAll(_forbidden, '_').replaceAll(RegExp(r'\s+'), ' ').trim();
  name = name.replaceFirst(RegExp(r'^[.\s]+'), '').replaceFirst(RegExp(r'[.\s]+$'), '');
  if (name.isEmpty || RegExp(r'^_+$').hasMatch(name)) {
    name = fallback;
  }
  if (_reservedWindowsName.hasMatch(name)) {
    name = '_$name';
  }

  final mimeExtension = extensionForMime(mimeType);
  if (mimeExtension != null && _extensionOf(name) == null) {
    name = '$name.$mimeExtension';
  }

  if (name.length > maxFileNameLength) {
    final ext = _extensionOf(name);
    final suffix = ext == null || ext.length > 10 ? '' : '.$ext';
    final base = name.substring(0, name.length - suffix.length);
    name = '${base.substring(0, maxFileNameLength - suffix.length).trimRight()}$suffix';
  }
  return name;
}

/// Lower-case extension of [name] without the dot, `null` when none.
String? _extensionOf(String name) {
  final dot = name.lastIndexOf('.');
  if (dot <= 0 || dot == name.length - 1) {
    return null;
  }
  final ext = name.substring(dot + 1).toLowerCase();
  return RegExp(r'^[a-z0-9]{1,10}$').hasMatch(ext) ? ext : null;
}

/// Decodes `%XX` escapes to raw bytes (the charset is applied by the
/// caller); `null` on an invalid escape.
List<int>? _percentDecode(String value) {
  final bytes = <int>[];
  for (var i = 0; i < value.length; i++) {
    final c = value.codeUnitAt(i);
    if (c == 0x25) {
      if (i + 2 >= value.length) {
        return null;
      }
      final hex = int.tryParse(value.substring(i + 1, i + 3), radix: 16);
      if (hex == null) {
        return null;
      }
      bytes.add(hex);
      i += 2;
    } else {
      bytes.addAll(utf8.encode(value[i]));
    }
  }
  return bytes;
}
