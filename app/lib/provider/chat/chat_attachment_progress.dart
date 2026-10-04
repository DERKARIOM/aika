import 'package:flutter/foundation.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// Progress of the attachment bytes of chat messages being sent or
/// received, per message id.
final chatAttachmentProgressProvider = Provider((ref) => ChatAttachmentProgress());

/// Each message has its own listenable, so a transfer only repaints the
/// bubble of that message, never the whole conversation.
class ChatAttachmentProgress {
  final _progress = <String, ValueNotifier<double?>>{};

  /// Progress of [messageId] in `[0, 1]`, or `null` while no transfer runs.
  ValueListenable<double?> of(String messageId) => _notifier(messageId);

  void set(String messageId, double progress) {
    final notifier = _notifier(messageId);
    final current = notifier.value;
    final next = progress.clamp(0.0, 1.0);
    // Steps of 1 %: smooth to the eye, few repaints even for 100 GB.
    if (current == null || next >= 1 || (next - current).abs() >= 0.01) {
      notifier.value = next;
    }
  }

  /// The transfer of [messageId] ended (finished or failed).
  void done(String messageId) {
    _progress[messageId]?.value = null;
  }

  ValueNotifier<double?> _notifier(String messageId) => _progress.putIfAbsent(messageId, () => ValueNotifier(null));
}
