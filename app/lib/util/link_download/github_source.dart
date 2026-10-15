/// GitHub's official REST API host: the only host a GitHub token is ever
/// sent to.
const githubApiHost = 'api.github.com';

/// Headers recommended by GitHub for its REST API.
const githubApiHeaders = {
  'accept': 'application/vnd.github+json',
  'x-github-api-version': '2022-11-28',
};

final _name = RegExp(r'^[A-Za-z0-9_.-]{1,100}$');
final _number = RegExp(r'^\d{1,20}$');

/// A GitHub Actions artifact, recognised from the link shown on the
/// workflow run page or from its API link:
/// - `https://github.com/<owner>/<repo>/actions/runs/<run>/artifacts/<id>`
/// - `https://api.github.com/repos/<owner>/<repo>/actions/artifacts/<id>[/zip]`
///
/// GitHub only serves artifacts to a signed-in account, through its API.
class GitHubArtifactRef {
  final String owner;
  final String repo;
  final String artifactId;

  const GitHubArtifactRef({required this.owner, required this.repo, required this.artifactId});

  static GitHubArtifactRef? tryParse(Uri uri) {
    if (uri.scheme != 'https') {
      return null;
    }
    final host = uri.host.toLowerCase();
    final s = uri.pathSegments.where((x) => x.isNotEmpty).toList();
    GitHubArtifactRef? ref;
    if ((host == 'github.com' || host == 'www.github.com') &&
        s.length == 7 &&
        s[2] == 'actions' &&
        s[3] == 'runs' &&
        _number.hasMatch(s[4]) &&
        s[5] == 'artifacts') {
      ref = GitHubArtifactRef(owner: s[0], repo: s[1], artifactId: s[6]);
    } else if (host == githubApiHost &&
        (s.length == 6 || (s.length == 7 && s[6] == 'zip')) &&
        s[0] == 'repos' &&
        s[3] == 'actions' &&
        s[4] == 'artifacts') {
      ref = GitHubArtifactRef(owner: s[1], repo: s[2], artifactId: s[5]);
    }
    if (ref == null || !_name.hasMatch(ref.owner) || !_name.hasMatch(ref.repo) || !_number.hasMatch(ref.artifactId)) {
      return null;
    }
    return ref;
  }

  /// Details: name, size, expiry (`GET /repos/{o}/{r}/actions/artifacts/{id}`).
  Uri get detailsUri => Uri.https(githubApiHost, '/repos/$owner/$repo/actions/artifacts/$artifactId');

  /// The archive: answers with a redirection to a short-lived storage link,
  /// so every download request goes through it again.
  Uri get zipUri => Uri.https(githubApiHost, '/repos/$owner/$repo/actions/artifacts/$artifactId/zip');
}

/// Rough check of a GitHub personal access token before sending it to
/// GitHub (classic `ghp_…` or fine-grained `github_pat_…`).
bool looksLikeGitHubToken(String token) => RegExp(r'^[A-Za-z0-9_]{20,255}$').hasMatch(token);
