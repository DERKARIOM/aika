import 'package:localsend_app/util/link_download/link_sources.dart';
import 'package:test/test.dart';

String? _platform(String link) => knownPlatformOf(Uri.parse(link))?.name;

void main() {
  test('recognises the platforms without an authorized download', () {
    expect(_platform('https://www.youtube.com/watch?v=abc'), 'YouTube');
    expect(_platform('https://youtu.be/abc'), 'YouTube');
    expect(_platform('https://m.youtube.com/shorts/abc'), 'YouTube');
    expect(_platform('https://www.tiktok.com/@a/video/1'), 'TikTok');
    expect(_platform('https://vm.tiktok.com/ZM123/'), 'TikTok');
    expect(_platform('https://www.instagram.com/p/abc/'), 'Instagram');
    expect(_platform('https://www.facebook.com/watch?v=1'), 'Facebook');
    expect(_platform('https://fb.watch/abc/'), 'Facebook');
    expect(_platform('https://x.com/a/status/1'), 'X');
    expect(_platform('https://twitter.com/a/status/1'), 'X');
    expect(_platform('https://www.pinterest.fr/pin/1/'), 'Pinterest');
    expect(_platform('https://pin.it/abc'), 'Pinterest');
    expect(_platform('https://www.reddit.com/r/a/comments/1/'), 'Reddit');
    expect(_platform('https://v.redd.it/abc'), 'Reddit');
  });

  test('lets direct media servers through as plain file links', () {
    expect(_platform('https://i.redd.it/abc.jpg'), isNull);
    expect(_platform('https://i.pinimg.com/originals/a/b/c.jpg'), isNull);
    expect(_platform('https://pbs.twimg.com/media/abc.jpg'), isNull);
  });

  test('does not match look-alike domains', () {
    expect(_platform('https://notyoutube.com/a.mp4'), isNull);
    expect(_platform('https://youtube.com.evil.example/a.mp4'), isNull);
    expect(_platform('https://mytiktok.com/a.mp4'), isNull);
    expect(_platform('https://exemple.org/video.mp4'), isNull);
  });

  test('spots copied links to files, like IDM', () {
    bool file(String link) => looksLikeDirectFileLink(Uri.parse(link));
    expect(file('https://exemple.org/setup-2.4.exe'), isTrue);
    expect(file('https://cdn.exemple.org/a/b/Archive.ZIP?token=1'), isTrue);
    expect(file('https://exemple.org/film.mkv'), isTrue);
    expect(file('https://exemple.org/rapport.pdf#page=2'), isTrue);
    expect(file('https://exemple.org/'), isFalse);
    expect(file('https://exemple.org/article'), isFalse);
    expect(file('https://exemple.org/page.html'), isFalse);
    expect(file('https://www.youtube.com/video.mp4'), isFalse);
  });
}
