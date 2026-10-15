import 'package:localsend_app/model/collections/collections_database.dart';
import 'package:localsend_app/model/cross_file.dart';
import 'package:localsend_app/provider/collections_provider.dart';
import 'package:localsend_isolates/model/file_type.dart';
import 'package:test/test.dart';

CrossFile _file({String? path, List<int>? bytes}) {
  return CrossFile(
    name: 'a.pdf',
    fileType: FileType.pdf,
    size: 3,
    thumbnail: null,
    asset: null,
    path: path,
    bytes: bytes,
    lastModified: null,
    lastAccessed: null,
  );
}

void main() {
  group('sourceForPickedFile', () {
    test('computers keep a reference to the original file (no copy)', () {
      expect(sourceForPickedFile(_file(path: r'C:\Users\me\a.pdf'), isDesktop: true), CollectionItemSource.path);
      expect(sourceForPickedFile(_file(path: '/home/me/a.pdf'), isDesktop: true), CollectionItemSource.path);
    });

    test('files only lent by the system are copied', () {
      expect(sourceForPickedFile(_file(path: 'content://media/1'), isDesktop: false), CollectionItemSource.copy);
      expect(sourceForPickedFile(_file(path: '/tmp/picked/a.pdf'), isDesktop: false), CollectionItemSource.copy);
      expect(sourceForPickedFile(_file(bytes: [1, 2, 3]), isDesktop: true), CollectionItemSource.copy);
    });
  });
}
