import 'dart:math';

import 'package:flutter/material.dart';

/// Colors of the chat screens, derived from the app's color scheme so they
/// follow Aika's brand color, light/dark mode and Material You.
class ChatColors {
  /// Behind the messages.
  final Color background;

  /// The motif drawn over [background].
  final Color pattern;
  final Color outgoingBubble;
  final Color incomingBubble;

  /// Message text, on both bubble colors.
  final Color text;

  /// Time, ticks and other secondary text inside a bubble.
  final Color meta;

  /// The author name / accent inside a bubble.
  final Color accent;

  /// Day separators and system notices.
  final Color chip;
  final Color onChip;

  /// App bar and input bar.
  final Color bar;
  final Color input;

  /// "Read" ticks, the convention users know from other messengers.
  final Color readTick;

  const ChatColors._({
    required this.background,
    required this.pattern,
    required this.outgoingBubble,
    required this.incomingBubble,
    required this.text,
    required this.meta,
    required this.accent,
    required this.chip,
    required this.onChip,
    required this.bar,
    required this.input,
    required this.readTick,
  });

  factory ChatColors.of(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    return ChatColors._(
      background: dark ? Color.alphaBlend(scheme.primary.withValues(alpha: 0.03), scheme.surface) : Color.alphaBlend(scheme.primary.withValues(alpha: 0.06), const Color(0xFFF4F1EC)),
      pattern: scheme.onSurface.withValues(alpha: dark ? 0.035 : 0.05),
      outgoingBubble: dark ? Color.alphaBlend(scheme.primary.withValues(alpha: 0.30), scheme.surfaceContainerLow) : Color.alphaBlend(scheme.primary.withValues(alpha: 0.22), Colors.white),
      incomingBubble: dark ? scheme.surfaceContainerHigh : Colors.white,
      text: scheme.onSurface,
      meta: scheme.onSurfaceVariant,
      accent: scheme.primary,
      chip: dark ? scheme.surfaceContainerHigh : Colors.white.withValues(alpha: 0.92),
      onChip: scheme.onSurfaceVariant,
      bar: dark ? scheme.surfaceContainer : scheme.surface,
      input: dark ? scheme.surfaceContainerHigh : Colors.white,
      readTick: const Color(0xFF53BDEB),
    );
  }
}

/// The conversation background: a solid tint with a sparse, quiet motif of
/// Aika's own shapes (transfer arrows, bubbles, dots), so long
/// conversations do not feel flat. Painted once per size: cheap even on
/// low-end phones.
class ChatBackground extends StatelessWidget {
  final Widget child;

  const ChatBackground({required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    final colors = ChatColors.of(context);
    return ColoredBox(
      color: colors.background,
      child: Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(painter: _MotifPainter(colors.pattern)),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _MotifPainter extends CustomPainter {
  final Color color;

  _MotifPainter(this.color);

  static const _cell = 72.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    // Seeded: the same motif on every build and every device.
    final random = Random(7);
    for (var y = 0.0; y < size.height + _cell; y += _cell) {
      for (var x = 0.0; x < size.width + _cell; x += _cell) {
        final center = Offset(x + random.nextDouble() * 36 + 18, y + random.nextDouble() * 36 + 18);
        _shape(canvas, paint, center, random.nextInt(4), random.nextDouble() * pi);
      }
    }
  }

  void _shape(Canvas canvas, Paint paint, Offset c, int kind, double angle) {
    canvas
      ..save()
      ..translate(c.dx, c.dy)
      ..rotate(angle);
    switch (kind) {
      case 0:
        // Two opposite arrows: a transfer.
        canvas
          ..drawLine(const Offset(-8, -3), const Offset(8, -3), paint)
          ..drawLine(const Offset(8, -3), const Offset(4, -7), paint)
          ..drawLine(const Offset(8, 3), const Offset(-8, 3), paint)
          ..drawLine(const Offset(-8, 3), const Offset(-4, 7), paint);
      case 1:
        // A small speech bubble.
        canvas
          ..drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(-9, -7, 18, 12), const Radius.circular(5)), paint)
          ..drawLine(const Offset(-4, 5), const Offset(-7, 9), paint);
      case 2:
        canvas.drawCircle(Offset.zero, 4, paint);
      default:
        // A file corner.
        canvas.drawPath(
          Path()
            ..moveTo(-6, -8)
            ..lineTo(3, -8)
            ..lineTo(7, -4)
            ..lineTo(7, 8)
            ..lineTo(-6, 8)
            ..close(),
          paint,
        );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MotifPainter oldDelegate) => oldDelegate.color != color;
}

/// A chat peer's picture: its device type on a tinted disc, with a green
/// dot while it is online.
class ChatAvatar extends StatelessWidget {
  final IconData icon;
  final bool online;
  final double radius;

  /// Ring around the online dot, the color behind the avatar.
  final Color ringColor;

  const ChatAvatar({required this.icon, required this.online, required this.ringColor, this.radius = 21, super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final dot = radius * 0.55;
    return SizedBox.square(
      dimension: radius * 2,
      child: Stack(
        children: [
          CircleAvatar(
            radius: radius,
            backgroundColor: colorScheme.primaryContainer,
            foregroundColor: colorScheme.onPrimaryContainer,
            child: Icon(icon, size: radius * 1.05),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: AnimatedScale(
              scale: online ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                width: dot,
                height: dot,
                decoration: BoxDecoration(
                  color: Colors.greenAccent.shade700,
                  shape: BoxShape.circle,
                  border: Border.all(color: ringColor, width: 2),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
