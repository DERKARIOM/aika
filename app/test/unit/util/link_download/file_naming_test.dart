import 'package:localsend_app/util/link_download/file_naming.dart';
import 'package:test/test.dart';

void main() {
  group('sanitizeFileName', () {
    test('keeps a normal name', () {
      expect(sanitizeFileName('photo été 2026.jpg'), 'photo été 2026.jpg');
    });

    test('removes folders and path traversal', () {
      expect(sanitizeFileName('../../etc/passwd'), 'passwd');
      expect(sanitizeFileName(r'C:\Windows\system32\evil.exe'), 'evil.exe');
    });

    test('replaces forbidden and control characters', () {
      expect(sanitizeFileName('a<b>c:d"e|f?g*h.txt'), 'a_b_c_d_e_f_g_h.txt');
      expect(sanitizeFileName('bad\u0000name\n.pdf'), 'bad_name_.pdf');
    });

    test('never produces a hidden or empty name', () {
      expect(sanitizeFileName('.htaccess'), 'htaccess');
      expect(sanitizeFileName('...'), 'telechargement');
      expect(sanitizeFileName(null, mimeType: 'image/png'), 'telechargement.png');
      expect(sanitizeFileName('name. '), 'name');
    });

    test('avoids Windows reserved names', () {
      expect(sanitizeFileName('CON.txt'), '_CON.txt');
      expect(sanitizeFileName('nul'), '_nul');
    });

    test('adds the extension from the MIME type when missing', () {
      expect(sanitizeFileName('video', mimeType: 'video/mp4; codecs=avc1'), 'video.mp4');
      expect(sanitizeFileName('doc.pdf', mimeType: 'application/pdf'), 'doc.pdf');
    });

    test('shortens long names but keeps the extension', () {
      final name = sanitizeFileName('${'x' * 300}.mp4');
      expect(name.length, maxFileNameLength);
      expect(name.endsWith('.mp4'), isTrue);
    });
  });

  group('fileNameFromContentDisposition', () {
    test('prefers the UTF-8 extended form', () {
      expect(
        fileNameFromContentDisposition('attachment; filename="rapport.pdf"; filename*=UTF-8\'\'rapport%20%C3%A9t%C3%A9.pdf'),
        'rapport été.pdf',
      );
    });

    test('reads ISO-8859-1 extended names', () {
      expect(fileNameFromContentDisposition("attachment; filename*=iso-8859-1'fr'caf%E9.txt"), 'café.txt');
    });

    test('reads quoted and plain names', () {
      expect(fileNameFromContentDisposition('attachment; filename="mon \\"fichier\\".zip"'), 'mon "fichier".zip');
      expect(fileNameFromContentDisposition('inline; filename=image.png'), 'image.png');
    });

    test('returns null without a file name', () {
      expect(fileNameFromContentDisposition('attachment'), isNull);
      expect(fileNameFromContentDisposition(null), isNull);
    });
  });

  test('fileNameFromUri decodes the last path segment', () {
    expect(fileNameFromUri(Uri.parse('https://exemple.org/media/photo%20%C3%A9t%C3%A9.jpg?x=1')), 'photo été.jpg');
    expect(fileNameFromUri(Uri.parse('https://exemple.org/')), isNull);
  });

  test('mediaKindOf uses the MIME type, then the extension', () {
    expect(mediaKindOf(mimeType: 'image/webp', fileName: 'x'), LinkMediaKind.image);
    expect(mediaKindOf(mimeType: 'video/mp4', fileName: 'x'), LinkMediaKind.video);
    expect(mediaKindOf(mimeType: 'audio/mpeg', fileName: 'x'), LinkMediaKind.audio);
    expect(mediaKindOf(mimeType: 'application/pdf', fileName: 'x'), LinkMediaKind.document);
    expect(mediaKindOf(mimeType: 'application/zip', fileName: 'x'), LinkMediaKind.archive);
    expect(mediaKindOf(mimeType: 'application/octet-stream', fileName: 'clip.mov'), LinkMediaKind.video);
    expect(mediaKindOf(mimeType: null, fileName: 'notes.docx'), LinkMediaKind.document);
    expect(mediaKindOf(mimeType: null, fileName: 'data.bin'), LinkMediaKind.other);
  });
}
