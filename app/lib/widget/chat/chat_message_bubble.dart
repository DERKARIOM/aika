import 'dart:io';

import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/chat/chat_database.dart';
import 'package:localsend_app/model/chat/chat_envelope.dart';

/// A single WhatsApp/Telegram/Material-3-style chat bubble.
///
/// Kept intentionally small and stateless: all the state (status, content,
/// timing) is already fully resolved on the [ChatMessage] row itself, so
/// this widget is a pure function of its data - easy to reuse, easy to
/// test, easy to keep smooth on low-end Android since it never rebuilds
/// unless its own message row actually changed.
class ChatMessageBubble extends StatelessWidget {
  final ChatMessage message;

  const ChatMessageBubble({required this.message});

  bool get _isOutgoing => message.direction == ChatMessageDirectionColumn.outgoing;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bubbleColor = _isOutgoing ? colorScheme.primary : colorScheme.surfaceContainerHighest;
    final textColor = _isOutgoing ? colorScheme.onPrimary : colorScheme.onSurface;

    return Align(
      alignment: _isOutgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.75),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(_isOutgoing ? 18 : 4),
              bottomRight: Radius.circular(_isOutgoing ? 4 : 18),
            ),
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
                    _formatTime(message.createdAt),
                    style: TextStyle(color: textColor.withValues(alpha: 0.7), fontSize: 11),
                  ),
                  if (_isOutgoing) ...[
                    const SizedBox(width: 4),
                    Icon(_statusIcon(message.status), size: 15, color: textColor.withValues(alpha: 0.85)),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
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

class _AttachmentPreview extends StatelessWidget {
  final ChatMessage message;
  final Color textColor;

  const _AttachmentPreview({required this.message, required this.textColor});

  @override
  Widget build(BuildContext context) {
    final path = message.attachmentPath;
    final isImage = message.contentType == ChatContentType.image.name;

    if (isImage && path != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.file(File(path), width: 220, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _placeholder(context)),
      );
    }

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
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              message.attachmentFileName ?? t.chat.attachment,
              style: TextStyle(color: textColor),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (path == null) ...[
            const SizedBox(width: 8),
            SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: textColor)),
          ],
        ],
      ),
    );
  }

  Widget _placeholder(BuildContext context) {
    return Container(
      width: 220,
      height: 140,
      color: Colors.black12,
      child: Icon(Icons.broken_image_outlined, color: textColor),
    );
  }

  IconData _iconFor(String contentType) {
    if (contentType == ChatContentType.video.name) return Icons.videocam_outlined;
    if (contentType == ChatContentType.audio.name) return Icons.mic_none_outlined;
    return Icons.insert_drive_file_outlined;
  }
}

String _formatTime(DateTime utc) {
  final local = utc.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}
