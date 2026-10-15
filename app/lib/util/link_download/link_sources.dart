/// Why a known platform cannot be downloaded from directly.
enum PlatformLimit {
  /// The platform's terms forbid downloads outside its own features.
  termsForbid,

  /// No public API gives third-party apps the media file.
  noPublicApi,

  /// Only reachable after signing in with an approved developer app.
  requiresApprovedApp,
}

/// A site Aika recognises but cannot download from directly (yet).
///
/// This is the extension point: a future adapter for a platform that
/// offers an authorized download mechanism replaces its entry here with a
/// resolver returning the real file URL. Nothing is listed as supported
/// before it has been verified.
class KnownPlatform {
  final String name;
  final PlatformLimit limit;
  final bool Function(String host) matches;

  /// Whether the platform's own app can save the content (when the
  /// creator allows it), so Aika can suggest that route.
  final bool hasOwnSaveFeature;

  const KnownPlatform({required this.name, required this.limit, required this.matches, this.hasOwnSaveFeature = false});
}

bool _isOrSub(String host, String domain) => host == domain || host.endsWith('.$domain');

final _pinterestDomain = RegExp(r'(^|\.)pinterest\.(com|[a-z]{2}|co\.[a-z]{2}|com\.[a-z]{2})$');

/// Platforms checked before any request (and again after each redirection,
/// so a short link landing on one of them gets the same clear message).
///
/// Media servers of these platforms that serve plain public files (for
/// example `i.redd.it`, `i.pinimg.com`, `pbs.twimg.com`) are deliberately
/// NOT listed: a pasted direct file link goes through the generic, verified
/// direct download like any other file.
final knownPlatforms = <KnownPlatform>[
  KnownPlatform(
    name: 'YouTube',
    limit: PlatformLimit.termsForbid,
    matches: (h) => _isOrSub(h, 'youtube.com') || _isOrSub(h, 'youtu.be') || _isOrSub(h, 'youtube-nocookie.com'),
  ),
  KnownPlatform(
    name: 'TikTok',
    limit: PlatformLimit.noPublicApi,
    matches: (h) => _isOrSub(h, 'tiktok.com'),
    hasOwnSaveFeature: true,
  ),
  KnownPlatform(
    name: 'Instagram',
    limit: PlatformLimit.requiresApprovedApp,
    matches: (h) => _isOrSub(h, 'instagram.com') || _isOrSub(h, 'instagr.am'),
  ),
  KnownPlatform(
    name: 'Facebook',
    limit: PlatformLimit.requiresApprovedApp,
    matches: (h) => _isOrSub(h, 'facebook.com') || _isOrSub(h, 'fb.watch') || h == 'fb.com' || h == 'www.fb.com',
  ),
  KnownPlatform(
    name: 'Threads',
    limit: PlatformLimit.requiresApprovedApp,
    matches: (h) => _isOrSub(h, 'threads.net') || _isOrSub(h, 'threads.com'),
  ),
  KnownPlatform(
    name: 'X',
    limit: PlatformLimit.requiresApprovedApp,
    matches: (h) => h == 'x.com' || h == 'www.x.com' || h == 'mobile.x.com' || _isOrSub(h, 'twitter.com'),
  ),
  KnownPlatform(
    name: 'Pinterest',
    limit: PlatformLimit.requiresApprovedApp,
    matches: (h) => _pinterestDomain.hasMatch(h) || h == 'pin.it',
  ),
  KnownPlatform(
    name: 'Reddit',
    limit: PlatformLimit.requiresApprovedApp,
    matches: (h) => _isOrSub(h, 'reddit.com') || h == 'redd.it' || h == 'v.redd.it',
  ),
  KnownPlatform(
    name: 'Snapchat',
    limit: PlatformLimit.noPublicApi,
    matches: (h) => _isOrSub(h, 'snapchat.com'),
  ),
  KnownPlatform(
    name: 'LinkedIn',
    limit: PlatformLimit.requiresApprovedApp,
    matches: (h) => _isOrSub(h, 'linkedin.com') || h == 'lnkd.in',
  ),
  KnownPlatform(
    name: 'Vimeo',
    limit: PlatformLimit.termsForbid,
    matches: (h) => _isOrSub(h, 'vimeo.com'),
  ),
  KnownPlatform(
    name: 'Dailymotion',
    limit: PlatformLimit.termsForbid,
    matches: (h) => _isOrSub(h, 'dailymotion.com') || h == 'dai.ly',
  ),
];

/// The known platform [uri] belongs to, `null` for any other site.
KnownPlatform? knownPlatformOf(Uri uri) {
  final host = uri.host.toLowerCase();
  for (final platform in knownPlatforms) {
    if (platform.matches(host)) {
      return platform;
    }
  }
  return null;
}

/// Extensions of files people usually download from a link (used to spot
/// a copied file link, like IDM does).
const _downloadableExtensions = {
  'zip', 'rar', '7z', 'tar', 'gz', 'tgz', 'xz', 'bz2', 'zst', //
  'exe', 'msi', 'msix', 'appx', 'dmg', 'pkg', 'deb', 'rpm', 'appimage', 'apk', 'aab', 'iso', 'img', //
  'pdf', 'epub', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'odt', 'ods', 'odp', 'csv', //
  'mp4', 'mkv', 'avi', 'mov', 'webm', 'm4v', 'wmv', 'flv', '3gp', //
  'mp3', 'flac', 'wav', 'm4a', 'aac', 'ogg', 'opus', 'wma', //
  'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'avif', 'tif', 'tiff', 'bmp', 'svg', 'psd', 'raw', //
  'torrent', 'bin', 'jar',
};

/// Whether [uri] looks like a link to a file (its path ends with a known
/// file extension) on a site that is not a known platform.
bool looksLikeDirectFileLink(Uri uri) {
  if (knownPlatformOf(uri) != null) {
    return false;
  }
  final segments = uri.pathSegments.where((s) => s.isNotEmpty);
  if (segments.isEmpty) {
    return false;
  }
  final last = segments.last.toLowerCase();
  final dot = last.lastIndexOf('.');
  return dot > 0 && _downloadableExtensions.contains(last.substring(dot + 1));
}
