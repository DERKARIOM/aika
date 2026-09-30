import 'package:localsend_app/gen/strings.g.dart';

/// Time formatting shared by the chat screens. Every function takes UTC
/// timestamps (as stored) and an optional [now] (local) for testability.

String _two(int value) => value.toString().padLeft(2, '0');

bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

bool _isYesterday(DateTime local, DateTime now) => _sameDay(local, DateTime(now.year, now.month, now.day - 1));

String _date(DateTime local, DateTime now) {
  final day = '${_two(local.day)}/${_two(local.month)}';
  return local.year == now.year ? day : '$day/${local.year}';
}

/// `14:05`
String formatChatClock(DateTime utc) {
  final local = utc.toLocal();
  return '${_two(local.hour)}:${_two(local.minute)}';
}

/// Whether two stored timestamps fall on the same local day.
bool isSameChatDay(DateTime a, DateTime b) => _sameDay(a.toLocal(), b.toLocal());

/// Separator label in a conversation: "Today", "Yesterday", `28/09`,
/// `28/09/2025`.
String chatDayLabel(DateTime utc, {DateTime? now}) {
  final local = utc.toLocal();
  final today = now ?? DateTime.now();
  if (_sameDay(local, today)) {
    return t.chat.today;
  }
  if (_isYesterday(local, today)) {
    return t.chat.yesterday;
  }
  return _date(local, today);
}

/// Timestamp of the last message in the conversation list: `14:05` today,
/// "Yesterday", otherwise the date.
String formatConversationTimestamp(DateTime utc, {DateTime? now}) {
  final local = utc.toLocal();
  final today = now ?? DateTime.now();
  if (_sameDay(local, today)) {
    return formatChatClock(utc);
  }
  if (_isYesterday(local, today)) {
    return t.chat.yesterday;
  }
  return _date(local, today);
}

/// "last seen today at 14:05", "last seen yesterday at 09:12",
/// "last seen on 28/09"; `null` if never seen.
String? formatLastSeen(DateTime? utc, {DateTime? now}) {
  if (utc == null) {
    return null;
  }
  final local = utc.toLocal();
  final today = now ?? DateTime.now();
  if (_sameDay(local, today)) {
    return t.chat.lastSeenToday(time: formatChatClock(utc));
  }
  if (_isYesterday(local, today)) {
    return t.chat.lastSeenYesterday(time: formatChatClock(utc));
  }
  return t.chat.lastSeenOn(date: _date(local, today));
}
