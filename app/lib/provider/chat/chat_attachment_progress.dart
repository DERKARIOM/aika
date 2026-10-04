import 'package:flutter/foundation.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// Progress of the attachment bytes of chat messages being sent or
/// received, per message id.
final chatAttachmentProgressProvider = Provider((ref) => ChatAttachmentProgress());

/// Each message has its own listenable, so a transfer only repaints the
/// bubble of that message, never the whole conversation.
class ChatAttachmentProgress {
  /// Repaint on each 1 % step...
  static const minStep = 0.01;

  /// ...or at least this often while bytes flow, so speed and remaining
  /// time stay fresh even when 1 % is a whole gigabyte.
  static const minInterval = Duration(milliseconds: 500);

  final DateTime Function() _clock;
  final _progress = <String, ValueNotifier<double?>>{};
  final _startedAt = <String, DateTime>{};
  final _notifiedAt = <String, DateTime>{};

  ChatAttachmentProgress({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  /// Progress of [messageId] in `[0, 1]`, or `null` while no transfer runs.
  ValueListenable<double?> of(String messageId) => _notifier(messageId);

  /// Time since the bytes of [messageId] started flowing, `null` while no
  /// transfer runs.
  Duration? elapsed(String messageId) {
    final startedAt = _startedAt[messageId];
    return startedAt == null ? null : _clock().difference(startedAt);
  }

  void set(String messageId, double progress) {
    final now = _clock();
    final notifier = _notifier(messageId);
    final current = notifier.value;
    final next = progress.clamp(0.0, 1.0);
    _startedAt.putIfAbsent(messageId, () => now);
    final notifiedAt = _notifiedAt[messageId];
    final stepReached = current == null || next >= 1 || (next - current).abs() >= minStep;
    final intervalReached = next != current && (notifiedAt == null || now.difference(notifiedAt) >= minInterval);
    if (stepReached || intervalReached) {
      _notifiedAt[messageId] = now;
      notifier.value = next;
    }
  }

  /// The transfer of [messageId] ended (finished, failed or cancelled).
  void done(String messageId) {
    _startedAt.remove(messageId);
    _notifiedAt.remove(messageId);
    _progress[messageId]?.value = null;
  }

  ValueNotifier<double?> _notifier(String messageId) => _progress.putIfAbsent(messageId, () => ValueNotifier(null));
}
