import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/util/chat/chat_time_format.dart';
import 'package:test/test.dart';

void main() {
  // Local "now"; stored timestamps are UTC, so build them from local times.
  final now = DateTime(2026, 9, 30, 15, 0);
  DateTime at(int year, int month, int day, int hour, int minute) => DateTime(year, month, day, hour, minute).toUtc();

  setUpAll(() {
    LocaleSettings.setLocaleSync(AppLocale.en);
  });

  test('Should format the clock time', () {
    expect(formatChatClock(at(2026, 9, 30, 9, 5)), '09:05');
  });

  test('Should label days', () {
    expect(chatDayLabel(at(2026, 9, 30, 0, 1), now: now), 'Today');
    expect(chatDayLabel(at(2026, 9, 29, 23, 59), now: now), 'Yesterday');
    expect(chatDayLabel(at(2026, 9, 3, 12, 0), now: now), '03/09');
    expect(chatDayLabel(at(2025, 12, 31, 12, 0), now: now), '31/12/2025');
  });

  test('Should handle yesterday across a month boundary', () {
    expect(chatDayLabel(at(2026, 9, 30, 12, 0), now: DateTime(2026, 10, 1, 8, 0)), 'Yesterday');
  });

  test('Should format conversation timestamps', () {
    expect(formatConversationTimestamp(at(2026, 9, 30, 14, 5), now: now), '14:05');
    expect(formatConversationTimestamp(at(2026, 9, 29, 14, 5), now: now), 'Yesterday');
    expect(formatConversationTimestamp(at(2026, 8, 1, 14, 5), now: now), '01/08');
  });

  test('Should format last seen', () {
    expect(formatLastSeen(null, now: now), isNull);
    expect(formatLastSeen(at(2026, 9, 30, 14, 5), now: now), 'last seen today at 14:05');
    expect(formatLastSeen(at(2026, 9, 29, 9, 12), now: now), 'last seen yesterday at 09:12');
    expect(formatLastSeen(at(2026, 9, 28, 9, 12), now: now), 'last seen on 28/09');
  });

  test('Should compare days in local time', () {
    expect(isSameChatDay(at(2026, 9, 30, 0, 1), at(2026, 9, 30, 23, 59)), true);
    expect(isSameChatDay(at(2026, 9, 29, 23, 59), at(2026, 9, 30, 0, 1)), false);
  });

  test('Should translate to French', () async {
    await LocaleSettings.setLocale(AppLocale.fr);
    addTearDown(() => LocaleSettings.setLocaleSync(AppLocale.en));

    expect(formatLastSeen(at(2026, 9, 29, 9, 12), now: now), 'vu hier à 09:12');
    expect(chatDayLabel(at(2026, 9, 30, 9, 12), now: now), "Aujourd'hui");
  });
}
