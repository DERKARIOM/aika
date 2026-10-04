import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/chat/chat_database.dart';
import 'package:localsend_app/model/chat/chat_envelope.dart';
import 'package:localsend_app/util/chat/chat_time_format.dart';
import 'package:localsend_app/util/file_size_helper.dart';
import 'package:localsend_app/util/native/open_file.dart' as native;
import 'package:localsend_isolates/model/file_type.dart';

/// "Read" ticks, the convention users know from other messengers.
const _readTickColor = Color(0xFF53BDEB);

/// A single WhatsApp/Telegram/Material-3-style chat bubble.
///
/// Kept intentionally small and stateless: all the state (status, content,
/// timing) is already fully resolved on the [ChatMessage] row itself, so
/// this widget is a pure function of its data - easy to reuse, easy to
/// test, easy to keep smooth on low-end Android since it never rebuilds
/// unless its own message row actually changed.
class ChatMessageBubble extends StatelessWidget {
  final ChatMessage message;

  /// Sends an outgoing message again; offered while it is not delivered.
  final VoidCallback? onRetry;

  /// Same author just before / just after: the bubbles of a group sit
  /// closer together, and only the last one has the "tail" corner.
  final bool groupedWithPrevious;
  final bool groupedWithNext;

  const ChatMessageBubble({
    required this.message,
    this.onRetry,
    this.groupedWithPrevious = false,
    this.groupedWithNext = false,
    super.key,
  });

  bool get _isOutgoing => message.direction == ChatMessageDirectionColumn.outgoing;

  /// Not sent, and the last attempt reported why.
  bool get _hasSendError =>
      _isOutgoing &&
      (message.status == ChatMessageStatusColumn.failed || (message.status == ChatMessageStatusColumn.pending && message.errorMessage != null));

  bool get _canRetry =>
      onRetry != null && _isOutgoing && (message.status == ChatMessageStatusColumn.pending || message.status == ChatMessageStatusColumn.failed);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bubbleColor = _isOutgoing ? colorScheme.primary : colorScheme.surfaceContainerHighest;
    final textColor = _isOutgoing ? colorScheme.onPrimary : colorScheme.onSurface;

    final bubble = Align(
      alignment: _isOutgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.75),
        child: Container(
          margin: EdgeInsets.only(top: groupedWithPrevious ? 1 : 6, bottom: groupedWithNext ? 1 : 2),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: _borderRadius,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (message.contentType != ChatContentType.text.name) _AttachmentPreview(message: message, textColor: textColor),
              if (message.body != null && message.body!.isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(top: message.contentType != ChatContentType.text.name ? 6 : 0),
                  child: Text(message.body!, style: TextStyle(color: textColor)),
                ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    formatChatClock(message.createdAt),
                    style: TextStyle(color: textColor.withValues(alpha: 0.7), fontSize: 11),
                  ),
                  if (_isOutgoing) ...[
                    const SizedBox(width: 4),
                    Icon(
                      _statusIcon(message.status),
                      size: 15,
                      semanticLabel: _statusLabel(message.status),
                      color: message.status == ChatMessageStatusColumn.read ? _readTickColor : textColor.withValues(alpha: 0.85),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );

    return GestureDetector(
      onTap: _hasSendError && _canRetry ? onRetry : null,
      onLongPress: () => _showActions(context),
      child: Column(
        crossAxisAlignment: _isOutgoing ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          bubble,
          if (_hasSendError)
            Padding(
              padding: const EdgeInsets.only(bottom: 4, right: 4),
              child: Text(
                t.chat.notSentTapToRetry,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colorScheme.error),
              ),
            ),
        ],
      ),
    );
  }

  /// Round corners, except on the author's side where the bubble touches
  /// the previous or next one of its group, and the "tail" at the bottom of
  /// the last one.
  BorderRadius get _borderRadius {
    const round = Radius.circular(18);
    const joined = Radius.circular(6);
    const tail = Radius.circular(4);
    final authorTop = groupedWithPrevious ? joined : round;
    final authorBottom = groupedWithNext ? joined : tail;
    return BorderRadius.only(
      topLeft: _isOutgoing ? round : authorTop,
      topRight: _isOutgoing ? authorTop : round,
      bottomLeft: _isOutgoing ? round : authorBottom,
      bottomRight: _isOutgoing ? authorBottom : round,
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
                title: Text(_statusLabel(message.status)),
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

  String _statusLabel(ChatMessageStatusColumn status) {
    return switch (status) {
      ChatMessageStatusColumn.pending => t.chat.status.pending,
      ChatMessageStatusColumn.sent => t.chat.status.sent,
      ChatMessageStatusColumn.delivered => t.chat.status.delivered,
      ChatMessageStatusColumn.read => t.chat.status.read,
      ChatMessageStatusColumn.failed => t.chat.status.failed,
    };
  }

  IconData _statusIcon(ChatMessageStatusColumn status) {
    return switch (status) {
      ChatMessageStatusColumn.pending => Icons.schedule,
      ChatMessageStatusColumn.sent => Icons.done,
      ChatMessageStatusColumn.delivered => Icons.done_all,
      ChatMessageStatusColumn.read => Icons.done_all,
      ChatMessageStatusColumn.failed => Icons.error_outline,
    };
  }
}

/// The file of a media message: a thumbnail for an image, otherwise an
/// icon, the file name and its size. Tapping it opens the file with the
/// system's default app, once it is on this device (always for one we sent,
/// after the download for one we received; a spinner shows until then).
class _AttachmentPreview extends StatelessWidget {
  final ChatMessage message;
  final Color textColor;

  const _AttachmentPreview({required this.message, required this.textColor});

  bool get _isImage => message.contentType == ChatContentType.image.name;

  FileType get _fileType => switch (message.contentType) {
    'image' => FileType.image,
    'video' => FileType.video,
    _ => FileType.other,
  };

  @override
  Widget build(BuildContext context) {
    final path = message.attachmentPath;
    final content = _isImage && path != null ? _image(context, path) : _fileRow(path);
    if (path == null) {
      return content;
    }
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => native.openFile(context, _fileType, path),
        child: content,
      ),
    );
  }

  Widget _image(BuildContext context, String path) {
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.file(
        File(path),
        width: 220,
        // Decoded at display size: a 12 MP photo would otherwise take ~48 MB.
        cacheWidth: (220 * pixelRatio).round(),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _fileRow(path),
      ),
    );
  }

  Widget _fileRow(String? path) {
    final size = message.attachmentSize;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_iconFor(message.contentType), color: textColor),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  message.attachmentFileName ?? t.chat.attachment,
                  style: TextStyle(color: textColor, fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
                if (size != null)
                  Text(
                    size.asReadableFileSize,
                    style: TextStyle(color: textColor.withValues(alpha: 0.7), fontSize: 12),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (path == null)
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: textColor))
          else
            Icon(Icons.open_in_new_rounded, size: 18, color: textColor.withValues(alpha: 0.8)),
        ],
      ),
    );
  }

  IconData _iconFor(String contentType) {
    if (contentType == ChatContentType.video.name) return Icons.videocam_outlined;
    if (contentType == ChatContentType.audio.name) return Icons.audiotrack_outlined;
    if (contentType == ChatContentType.image.name) return Icons.image_outlined;
    return Icons.insert_drive_file_outlined;
  }
}
