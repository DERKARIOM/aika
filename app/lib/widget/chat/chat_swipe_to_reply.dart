import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Swipe a bubble to the right to reply to it, the gesture of other mobile
/// messengers: a reply icon fades in, a light haptic tick marks the
/// threshold, and releasing past it calls [onReply].
///
/// Without [onReply] (e.g. on desktop, where right click opens the actions)
/// it is just [child].
class ChatSwipeToReply extends StatefulWidget {
  final VoidCallback? onReply;
  final Widget child;

  const ChatSwipeToReply({required this.onReply, required this.child, super.key});

  @override
  State<ChatSwipeToReply> createState() => _ChatSwipeToReplyState();
}

class _ChatSwipeToReplyState extends State<ChatSwipeToReply> {
  /// Distance to drag to reply.
  static const _threshold = 56.0;

  /// The bubble follows the finger up to here.
  static const _max = 80.0;

  double _dx = 0;
  bool _dragging = false;
  bool _armed = false;

  void _onUpdate(DragUpdateDetails details) {
    setState(() {
      _dragging = true;
      _dx = (_dx + details.delta.dx).clamp(0.0, _max);
    });
    final armed = _dx >= _threshold;
    if (armed && !_armed) {
      HapticFeedback.selectionClick().ignore();
    }
    _armed = armed;
  }

  void _onEnd([DragEndDetails? _]) {
    if (_armed) {
      widget.onReply?.call();
    }
    setState(() {
      _dragging = false;
      _dx = 0;
      _armed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.onReply == null) {
      return widget.child;
    }
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragUpdate: _onUpdate,
      onHorizontalDragEnd: _onEnd,
      onHorizontalDragCancel: _onEnd,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          if (_dx > 0)
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Opacity(
                opacity: (_dx / _threshold).clamp(0.0, 1.0),
                child: Icon(Icons.reply_rounded, color: Theme.of(context).colorScheme.primary),
              ),
            ),
          AnimatedContainer(
            // Follows the finger, springs back once released.
            duration: _dragging ? Duration.zero : const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            transform: Matrix4.translationValues(_dx, 0, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}
