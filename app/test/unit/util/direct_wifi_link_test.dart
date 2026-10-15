import 'package:localsend_app/util/native/direct_wifi_link.dart';
import 'package:localsend_isolates/model/session_status.dart';
import 'package:test/test.dart';

void main() {
  test('the receiver Wi-Fi is kept while a session waits or sends', () {
    expect(isFinalSessionStatus(SessionStatus.waiting), isFalse);
    expect(isFinalSessionStatus(SessionStatus.sending), isFalse);
  });

  test('every other status ends the session', () {
    for (final status in SessionStatus.values.where((s) => s != SessionStatus.waiting && s != SessionStatus.sending)) {
      expect(isFinalSessionStatus(status), isTrue, reason: status.name);
    }
  });
}
