/// Everything that can stop a link from being downloaded, each with a clear
/// message for the user (see `link_download_page.dart`).
enum LinkProblem {
  /// Nothing was entered.
  empty,

  /// Not a valid web address.
  malformed,

  /// Only `http` and `https` links are accepted (no `file:`, `javascript:`,
  /// `content:`, ...).
  unsupportedScheme,

  /// The link contains a user name or password (`https://user:pass@host`).
  credentialsInUrl,

  /// The link points to this device, the local network or a reserved
  /// address (SSRF protection).
  localAddress,

  /// A known platform that offers no authorized download for third-party
  /// apps (YouTube, TikTok, Instagram, ...).
  unsupportedPlatform,

  /// The link opens a web page, not a file.
  webPageWithoutMedia,

  /// The server asks to sign in (401 / 403).
  requiresAuth,

  /// The content no longer exists or is private (404 / 410).
  notFound,

  /// Too many redirections (loop or tracking chain).
  tooManyRedirects,

  /// An `https` link redirected to plain `http`.
  insecureRedirect,

  /// The server answered with an error (5xx, unexpected status).
  serverError,

  /// No connection, DNS failure, connection lost.
  network,

  /// The server stopped answering.
  timeout,

  /// Bigger than allowed (unknown size above the limit).
  tooLarge,

  /// Not enough free space on the device.
  notEnoughSpace,

  /// The file could not be written to its destination.
  storage,

  /// A GitHub Actions artifact: GitHub only serves it to a signed-in
  /// account, and no GitHub token is set in Aika.
  githubSignInRequired,

  /// The saved GitHub token was refused (revoked or expired).
  githubTokenInvalid,

  /// The GitHub token cannot read this repository's artifacts.
  githubNoAccess,

  /// The content expired (for example a GitHub artifact past its
  /// retention period).
  expired,
}

/// A [LinkProblem] raised while analysing or downloading a link.
class LinkDownloadException implements Exception {
  final LinkProblem problem;

  /// Name of the platform for [LinkProblem.unsupportedPlatform].
  final String? platform;

  /// HTTP status when the problem comes from the server.
  final int? statusCode;

  const LinkDownloadException(this.problem, {this.platform, this.statusCode});

  /// Whether retrying the same request may succeed.
  bool get isTransient => problem == LinkProblem.network || problem == LinkProblem.timeout || problem == LinkProblem.serverError;

  @override
  String toString() => 'LinkDownloadException(${problem.name}${platform != null ? ', $platform' : ''}${statusCode != null ? ', $statusCode' : ''})';
}
