import 'package:localsend_app/pages/tabs/receive_tab.dart';
import 'package:localsend_app/util/native/storage_info.dart';
import 'package:test/test.dart';

void main() {
  group('parseDfOutput', () {
    test('Should read total and free space from POSIX output', () {
      const output = '''
Filesystem     1024-blocks      Used Available Capacity Mounted on
/dev/block/dm-48 115638528 41943040  73695488      37% /data
''';
      final info = parseDfOutput(output)!;
      expect(info.totalBytes, 115638528 * 1024);
      expect(info.freeBytes, 73695488 * 1024);
      expect(info.usedBytes, (115638528 - 73695488) * 1024);
    });

    test('Should accept a mount point with spaces (macOS volumes)', () {
      const output = '''
Filesystem   1024-blocks      Used Available Capacity  Mounted on
/dev/disk3s5   971350180 412349600 520124020    45%    /Volumes/Mon Disque
''';
      final info = parseDfOutput(output)!;
      expect(info.freeBytes, 520124020 * 1024);
    });

    test('Should return null for unexpected output', () {
      expect(parseDfOutput(''), isNull);
      expect(parseDfOutput('df: /nope: No such file or directory'), isNull);
    });
  });

  group('StorageInfo', () {
    test('Should not report used space without a total', () {
      const info = StorageInfo(totalBytes: null, freeBytes: 1000);
      expect(info.usedBytes, isNull);
      expect(info.usedFraction, isNull);
    });

    test('Should compute the used fraction', () {
      const info = StorageInfo(totalBytes: 128, freeBytes: 96);
      expect(info.usedBytes, 32);
      expect(info.usedFraction, 0.25);
    });
  });

  group('formatStorageSize', () {
    test('Should use decimal units like phones do', () {
      expect(formatStorageSize(86 * 1000 * 1000 * 1000), '86 GB');
      expect(formatStorageSize(4200 * 1000 * 1000), '4.2 GB');
      expect(formatStorageSize(128 * 1000 * 1000 * 1000), '128 GB');
      expect(formatStorageSize(512 * 1000 * 1000), '512 MB');
      expect(formatStorageSize(2 * 1000 * 1000 * 1000), '2 GB');
    });
  });
}
