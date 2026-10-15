import 'package:localsend_app/util/link_download/github_source.dart';
import 'package:test/test.dart';

GitHubArtifactRef? _parse(String link) => GitHubArtifactRef.tryParse(Uri.parse(link));

void main() {
  test('recognises the artifact link of a workflow run page', () {
    final ref = _parse('https://github.com/qwiper/qwiper-app-flutter/actions/runs/38601322312/artifacts/11914290733')!;
    expect(ref.owner, 'qwiper');
    expect(ref.repo, 'qwiper-app-flutter');
    expect(ref.artifactId, '11914290733');
    expect(ref.detailsUri.toString(), 'https://api.github.com/repos/qwiper/qwiper-app-flutter/actions/artifacts/11914290733');
    expect(ref.zipUri.toString(), 'https://api.github.com/repos/qwiper/qwiper-app-flutter/actions/artifacts/11914290733/zip');
  });

  test('recognises API links', () {
    expect(_parse('https://api.github.com/repos/a/b/actions/artifacts/42')?.artifactId, '42');
    expect(_parse('https://api.github.com/repos/a/b/actions/artifacts/42/zip')?.artifactId, '42');
  });

  test('ignores other GitHub links and look-alikes', () {
    expect(_parse('https://github.com/a/b/releases/download/v1/app.apk'), isNull);
    expect(_parse('https://github.com/a/b/actions/runs/1'), isNull);
    expect(_parse('https://github.com/a/b/actions/runs/1/artifacts/abc'), isNull);
    expect(_parse('http://github.com/a/b/actions/runs/1/artifacts/2'), isNull);
    expect(_parse('https://github.com.evil.example/a/b/actions/runs/1/artifacts/2'), isNull);
    expect(_parse('https://github.com/a%2F..%2Fx/b/actions/runs/1/artifacts/2'), isNull);
  });

  test('checks the token format before sending it', () {
    expect(looksLikeGitHubToken('github_pat_${'A1b2' * 10}'), isTrue);
    expect(looksLikeGitHubToken('ghp_${'x' * 36}'), isTrue);
    expect(looksLikeGitHubToken('short'), isFalse);
    expect(looksLikeGitHubToken('ghp_abc def ghi jkl mno pqr'), isFalse);
  });
}
