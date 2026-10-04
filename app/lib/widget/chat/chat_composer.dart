import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:localsend_app/gen/strings.g.dart';

/// The message input of a conversation: attachment button, text field and
/// send button, or a notice when the peer is blocked.
///
/// On desktop, Enter sends and Shift+Enter starts a new line, as in other
/// messengers; on mobile, Enter inserts a new line (the send button sends).
class ChatComposer extends StatelessWidget {
  final TextEditingController controller;
  final bool blocked;
  final ValueChanged<String> onChanged;

  /// Called with a non-blank text; the field is cleared right before.
  final ValueChanged<String> onSend;
  final VoidCallback onAttach;

  const ChatComposer({
    required this.controller,
    required this.blocked,
    required this.onChanged,
    required this.onSend,
    required this.onAttach,
    super.key,
  });

  static bool get _isDesktop => const {TargetPlatform.windows, TargetPlatform.macOS, TargetPlatform.linux}.contains(defaultTargetPlatform);

  void _send() {
    final text = controller.text;
    if (text.trim().isEmpty) {
      return;
    }
    controller.clear();
    onChanged('');
    onSend(text);
  }

  /// Enter without Shift sends, unless an input method is composing a
  /// character (e.g. Chinese or Japanese input), which Enter confirms.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final isEnter = event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (event is! KeyDownEvent || !isEnter || HardwareKeyboard.instance.isShiftPressed || controller.value.composing.isValid) {
      return KeyEventResult.ignored;
    }
    _send();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    if (blocked) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          t.chat.blockedNotice,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
      );
    }

    final field = TextField(
      controller: controller,
      onChanged: onChanged,
      minLines: 1,
      maxLines: 5,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(
        hintText: t.chat.messageHint,
        filled: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
      ),
    );

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
        child: Row(
          children: [
            IconButton(
              tooltip: t.chat.attachment,
              icon: const Icon(Icons.attach_file_rounded),
              onPressed: onAttach,
            ),
            Expanded(
              child: _isDesktop ? Focus(canRequestFocus: false, skipTraversal: true, onKeyEvent: _onKey, child: field) : field,
            ),
            const SizedBox(width: 4),
            IconButton.filled(
              icon: const Icon(Icons.send_rounded),
              onPressed: _send,
            ),
          ],
        ),
      ),
    );
  }
}
