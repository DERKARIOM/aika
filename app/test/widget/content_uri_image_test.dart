import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/widget/chat/content_uri_image.dart';

void main() {
  test('Should share the image cache entry of the same URI', () {
    const a = ContentUriImage('content://media/1');
    const b = ContentUriImage('content://media/1');
    const c = ContentUriImage('content://media/2');

    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(c));
  });
}
