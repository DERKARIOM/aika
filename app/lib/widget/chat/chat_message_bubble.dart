import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/chat/chat_database.dart';
import 'package:localsend_app/model/chat/chat_envelope.dart';
import 'package:localsend_app/provider/chat/chat_attachment_progress.dart';
import 'package:localsend_app/util/chat/chat_time_format.dart';
import 'package:localsend_app/util/file_size_helper.dart';
import 'package:localsend_app/util/native/open_file.dart' as native;
import 'package:localsend_app/widget/chat/chat_style.dart';
import 'package:localsend_isolates/model/file_type.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// Width of the bubble "tail" drawn outside the bubble.
const _tailWidth = 8.0;

/// A single chat bubble, in the style of modern messengers: a tail on the
/// first bubble of a group, the time and delivery ticks tucked into the
/// bottom-right corner of the text, images filling the bubble.
///
/// Kept stateless: everything it shows is resolved on the [ChatMessage]
/// row, so it only rebuilds when its own row changed.
class ChatMessageBubble extends StatelessWidget {
  final ChatMessage message;

  /// Sends an outgoing message again; offered while it is not delivered.
  final VoidCallback? onRetry;

  /// Stops sending the attachment; offered (tap on the progress ring)
  /// while its bytes are being sent.
  final VoidCallback? onCancelTransfer;

  /// Same author just before / just after: the bubbles of a group sit
  /// closer together, and only the first one has a tail.
  final bool groupedWithPrevious;
  final bool groupedWithNext;

  const ChatMessageBubble({
    required this.message,
    this.onRetry,
    this.onCancelTransfer,
    this.groupedWithPrevious = false,
    this.groupedWithNext = false,
    super.key,
  });

  bool get _isOutgoing => message.direction == ChatMessageDirectionColumn.outgoing;

  bool get _hasTail => !groupedWithPrevious;

  bool get _isMedia => message.contentType != ChatContentType.text.name;

  bool get _isImage => message.contentType == ChatContentType.image.name && _canPreview(message.attachmentPath);

  String? get _body => (message.body?.isNotEmpty ?? false) ? message.body : null;

  /// Not sent, and the last attempt reported why.
  bool get _hasSendError =>
      _isOutgoing &&
      (message.status == ChatMessageStatusColumn.failed || (message.status == ChatMessageStatusColumn.pending && message.errorMessage != null));

  bool get _canRetry =>
      onRetry != null && _isOutgoing && (message.status == ChatMessageStatusColumn.pending || message.status == ChatMessageStatusColumn.failed);

  @override
  Widget build(BuildContext context) {
    final colors = ChatColors.of(context);
    final bubbleColor = _isOutgoing ? colors.outgoingBubble : colors.incomingBubble;
    final maxWidth = (MediaQuery.sizeOf(context).width * 0.78).clamp(0.0, 520.0);

    final bubble = Container(
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: _borderRadius,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 1, offset: const Offset(0, 1))],
      ),
      padding: _isImage ? const EdgeInsets.all(3) : const EdgeInsets.fromLTRB(10, 6, 8, 6),
      child: _content(context, colors),
    );

    return GestureDetector(
      onTap: _hasSendError && _canRetry ? onRetry : null,
      onLongPress: () => _showActions(context),
      child: Padding(
        padding: EdgeInsets.only(
          top: groupedWithPrevious ? 2 : 8,
          left: _isOutgoing ? 48 : 0,
          right: _isOutgoing ? 0 : 48,
        ),
        child: Column(
          crossAxisAlignment: _isOutgoing ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Padding(
                // Room for the tail, so grouped bubbles stay aligned.
                padding: EdgeInsets.only(left: _isOutgoing ? 0 : _tailWidth, right: _isOutgoing ? _tailWidth : 0),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    bubble,
                    if (_hasTail)
                      Positioned(
                        top: 0,
                        left: _isOutgoing ? null : -_tailWidth,
                        right: _isOutgoing ? -_tailWidth : null,
                        child: CustomPaint(size: const Size(_tailWidth, 10), painter: _TailPainter(bubbleColor, pointsRight: _isOutgoing)),
                      ),
                  ],
                ),
              ),
            ),
            if (_hasSendError)
              Padding(
                padding: const EdgeInsets.only(top: 2, left: _tailWidth, right: _tailWidth),
                child: Text(
                  t.chat.notSentTapToRetry,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _content(BuildContext context, ChatColors colors) {
    final meta = _Meta(message: message, isOutgoing: _isOutgoing, colors: colors);
    final body = _body;

    if (_isImage) {
      // Image filling the bubble, the time over its bottom-right corner
      // (or under the caption).
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            children: [
              _AttachmentPreview(message: message, colors: colors, onCancel: _isOutgoing ? onCancelTransfer : null),
              if (body == null)
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(10)),
                    child: _Meta(message: message, isOutgoing: _isOutgoing, colors: colors, onImage: true),
                  ),
                ),
            ],
          ),
          if (body != null) Padding(padding: const EdgeInsets.fromLTRB(7, 6, 5, 3), child: _TextWithMeta(text: body, meta: meta, colors: colors)),
        ],
      );
    }

    if (_isMedia) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          _AttachmentPreview(message: message, colors: colors, onCancel: _isOutgoing ? onCancelTransfer : null),
          const SizedBox(height: 4),
          if (body != null) _TextWithMeta(text: body, meta: meta, colors: colors) else meta,
        ],
      );
    }

    return _TextWithMeta(text: body ?? '', meta: meta, colors: colors);
  }

  /// Rounded corners; the corner carrying the tail is square so the tail
  /// joins the bubble seamlessly.
  BorderRadius get _borderRadius {
    const round = Radius.circular(12);
    final tailCorner = _hasTail ? Radius.zero : round;
    return BorderRadius.only(
      topLeft: _isOutgoing ? round : tailCorner,
      topRight: _isOutgoing ? tailCorner : round,
      bottomLeft: round,
      bottomRight: round,
    );
  }

  void _showActions(BuildContext context) {
    final text = message.body;
    final error = _isOutgoing && message.status != ChatMessageStatusColumn.delivered && message.status != ChatMessageStatusColumn.read
        ? message.errorMessage
        : null;
    if ((text == null || text.isEmpty) && !_canRetry && error == null) {
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (error != null)
              ListTile(
                leading: Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
                title: Text(_statusLabelFor(message.status)),
                subtitle: Text(error),
              ),
            if (text != null && text.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: Text(t.chat.copy),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  Clipboard.setData(ClipboardData(text: text)).ignore();
                  ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(t.chat.copied)));
                },
              ),
            if (_canRetry)
              ListTile(
                leading: const Icon(Icons.refresh_rounded),
                title: Text(t.chat.retry),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  onRetry!();
                },
              ),
          ],
        ),
      ),
    ).ignore();
  }
}

/// Text followed by the time and ticks, tucked into its last line when
/// there is room (an invisible spacer reserves it), otherwise on a line of
/// their own: the layout of modern messengers.
class _TextWithMeta extends StatelessWidget {
  final String text;
  final _Meta meta;
  final ChatColors colors;

  const _TextWithMeta({required this.text, required this.meta, required this.colors});

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(color: colors.text, fontSize: 15, height: 1.3);
    return Stack(
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: text),
              // Reserves the room of the time and ticks at the end.
              WidgetSpan(child: SizedBox(width: meta.reservedWidth, height: 14)),
            ],
          ),
          style: style,
        ),
        Positioned(right: 0, bottom: 0, child: meta),
      ],
    );
  }
}

/// Time, and for our own messages the delivery ticks.
class _Meta extends StatelessWidget {
  final ChatMessage message;
  final bool isOutgoing;
  final ChatColors colors;

  /// Drawn over an image: white, for contrast.
  final bool onImage;

  const _Meta({required this.message, required this.isOutgoing, required this.colors, this.onImage = false});

  /// Room to keep free at the end of the text.
  double get reservedWidth => isOutgoing ? 66 : 46;

  @override
  Widget build(BuildContext context) {
    final color = onImage ? Colors.white : colors.meta;
    final status = message.status;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(formatChatClock(message.createdAt), style: TextStyle(color: color, fontSize: 11)),
        if (isOutgoing) ...[
          const SizedBox(width: 3),
          Icon(
            _statusIconFor(status),
            size: 16,
            semanticLabel: _statusLabelFor(status),
            color: status == ChatMessageStatusColumn.read ? colors.readTick : color,
          ),
        ],
      ],
    );
  }
}

String _statusLabelFor(ChatMessageStatusColumn status) {
  return switch (status) {
    ChatMessageStatusColumn.pending => t.chat.status.pending,
    ChatMessageStatusColumn.sent => t.chat.status.sent,
    ChatMessageStatusColumn.delivered => t.chat.status.delivered,
    ChatMessageStatusColumn.read => t.chat.status.read,
    ChatMessageStatusColumn.failed => t.chat.status.failed,
  };
}

IconData _statusIconFor(ChatMessageStatusColumn status) {
  return switch (status) {
    ChatMessageStatusColumn.pending => Icons.schedule_rounded,
    ChatMessageStatusColumn.sent => Icons.done_rounded,
    ChatMessageStatusColumn.delivered || ChatMessageStatusColumn.read => Icons.done_all_rounded,
    ChatMessageStatusColumn.failed => Icons.error_outline_rounded,
  };
}

/// The little triangle joining the first bubble of a group to its side.
class _TailPainter extends CustomPainter {
  final Color color;
  final bool pointsRight;

  _TailPainter(this.color, {required this.pointsRight});

  @override
  void paint(Canvas canvas, Size size) {
    final path = pointsRight
        ? (Path()
            ..moveTo(0, 0)
            ..lineTo(size.width, 0)
            ..quadraticBezierTo(size.width * 0.35, size.height * 0.35, 0, size.height)
            ..close())
        : (Path()
            ..moveTo(size.width, 0)
            ..lineTo(0, 0)
            ..quadraticBezierTo(size.width * 0.65, size.height * 0.35, size.width, size.height)
            ..close());
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_TailPainter oldDelegate) => oldDelegate.color != color || oldDelegate.pointsRight != pointsRight;
}

/// The file of a media message: the image itself, or an icon with the file
/// name and size. Tapping it opens the file with the system's default app,
/// once it is on this device (always for one we sent, after the download
/// for one we received; a spinner shows until then).
class _AttachmentPreview extends StatelessWidget {
  final ChatMessage message;
  final ChatColors colors;
  final VoidCallback? onCancel;

  const _AttachmentPreview({required this.message, required this.colors, this.onCancel});

  FileType get _fileType => switch (message.contentType) {
    'image' => FileType.image,
    'video' => FileType.video,
    _ => FileType.other,
  };

  @override
  Widget build(BuildContext context) {
    // Only this preview listens: a running transfer repaints one bubble,
    // never the conversation.
    final transfers = context.ref.read(chatAttachmentProgressProvider);
    return ValueListenableBuilder<double?>(
      valueListenable: transfers.of(message.id),
      builder: (context, progress, _) => _content(context, progress, transfers.elapsed(message.id)),
    );
  }

  Widget _content(BuildContext context, double? progress, Duration? elapsed) {
    final path = message.attachmentPath;
    final isImage = message.contentType == ChatContentType.image.name;
    final content = isImage && _canPreview(path) ? _image(context, path!, progress) : _fileRow(path, progress, elapsed);
    if (path == null) {
      return content;
    }
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => native.openFile(context, _fileType, path),
        child: content,
      ),
    );
  }

  Widget _image(BuildContext context, String path, double? progress) {
    const width = 260.0;
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 340),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Image.file(
              File(path),
              width: width,
              // Decoded at display size: a 12 MP photo would otherwise take ~48 MB.
              cacheWidth: (width * pixelRatio).round(),
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _fileRow(path, progress, null),
            ),
            if (progress != null) _ImageProgress(progress: progress, onCancel: onCancel),
          ],
        ),
      ),
    );
  }

  Widget _fileRow(String? path, double? progress, Duration? elapsed) {
    final size = message.attachmentSize;
    final sizeLabel = size == null
        ? null
        : progress == null
        ? size.asReadableFileSize
        : chatTransferLabel(size: size, progress: progress, elapsed: elapsed);
    return Container(
      width: 240,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.text.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: colors.accent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
            child: progress != null || path == null
                ? _CancelableRing(
                    progress: progress,
                    color: colors.accent,
                    // Only a running transfer can be stopped.
                    onCancel: progress == null ? null : onCancel,
                  )
                : Icon(_iconFor(message.contentType), color: colors.accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  message.attachmentFileName ?? t.chat.attachment,
                  style: TextStyle(color: colors.text, fontWeight: FontWeight.w500),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (sizeLabel != null) Text(sizeLabel, style: TextStyle(color: colors.meta, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconFor(String contentType) {
    if (contentType == ChatContentType.video.name) return Icons.play_circle_outline_rounded;
    if (contentType == ChatContentType.audio.name) return Icons.audiotrack_rounded;
    if (contentType == ChatContentType.image.name) return Icons.image_outlined;
    return Icons.insert_drive_file_outlined;
  }
}

/// Ring over an image whose bytes are still being transferred.
class _ImageProgress extends StatelessWidget {
  final double progress;
  final VoidCallback? onCancel;

  const _ImageProgress({required this.progress, this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
      child: _CancelableRing(progress: progress, color: Colors.white, onCancel: onCancel),
    );
  }
}

/// Progress ring of a transfer: determinate while bytes flow, indeterminate
/// while waiting. With [onCancel], a cross in its center stops the
/// transfer, the gesture users know from other messengers.
class _CancelableRing extends StatelessWidget {
  final double? progress;
  final Color color;
  final VoidCallback? onCancel;

  const _CancelableRing({required this.progress, required this.color, this.onCancel});

  @override
  Widget build(BuildContext context) {
    final ring = Padding(
      padding: const EdgeInsets.all(8),
      child: CircularProgressIndicator(
        value: progress,
        strokeWidth: 2.5,
        color: color,
        backgroundColor: progress == null ? null : color.withValues(alpha: 0.25),
      ),
    );
    if (onCancel == null) {
      return ring;
    }
    return Tooltip(
      message: t.general.cancel,
      child: Material(
        type: MaterialType.transparency,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onCancel,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(child: ring),
              Icon(Icons.close_rounded, size: 18, color: color, semanticLabel: t.general.cancel),
            ],
          ),
        ),
      ),
    );
  }
}

/// A local file that `Image.file` can decode. An Android `content://` URI
/// (an attachment picked with the system picker) is shown as a file card
/// and opened with the system viewer instead.
bool _canPreview(String? path) => path != null && !path.startsWith('content://');

/// "12.0 MB / 40.0 MB · 2.4 MB/s · 12 s" while a transfer runs: what was
/// sent, the speed and the time left. During the first second the speed is
/// not meaningful yet, so the percentage is shown instead.
@visibleForTesting
String chatTransferLabel({required int size, required double progress, required Duration? elapsed}) {
  final transferred = (size * progress).round();
  final head = '${transferred.asReadableFileSize} / ${size.asReadableFileSize}';
  final seconds = (elapsed?.inMilliseconds ?? 0) / 1000;
  if (seconds < 1 || transferred <= 0) {
    return '$head · ${(progress * 100).floor()} %';
  }
  final bytesPerSecond = transferred / seconds;
  final remaining = Duration(seconds: ((size - transferred) / bytesPerSecond).ceil());
  return '$head · ${bytesPerSecond.round().asReadableFileSize}/s · ${_shortDuration(remaining)}';
}

/// "45 s", "12 min", "1 h 05": compact, the same in every language.
String _shortDuration(Duration d) {
  if (d.inSeconds < 60) {
    return '${d.inSeconds} s';
  }
  if (d.inMinutes < 60) {
    return '${d.inMinutes} min';
  }
  return '${d.inHours} h ${(d.inMinutes % 60).toString().padLeft(2, '0')}';
}
