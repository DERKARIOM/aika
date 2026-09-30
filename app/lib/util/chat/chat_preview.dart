import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/chat/chat_envelope.dart';

/// Short, human-readable summary of a message, for the conversation list
/// and notifications: the text itself, or e.g. "Photo · caption".
String chatPreviewText(ChatContentType contentType, {String? text, String? attachmentFileName}) {
  if (contentType == ChatContentType.text) {
    return text ?? '';
  }
  final label = switch (contentType) {
    ChatContentType.image => t.chat.preview.photo,
    ChatContentType.video => t.chat.preview.video,
    ChatContentType.audio => t.chat.preview.audio,
    ChatContentType.document => attachmentFileName ?? t.chat.preview.document,
    ChatContentType.text => text ?? '',
  };
  return (text != null && text.isNotEmpty) ? '$label · $text' : label;
}
