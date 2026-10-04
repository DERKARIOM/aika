import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/widget/chat/chat_style.dart';

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

    final colors = ChatColors.of(context);
    final field = TextField(
      controller: controller,
      onChanged: onChanged,
      minLines: 1,
      maxLines: 6,
      textCapitalization: TextCapitalization.sentences,
      style: TextStyle(color: colors.text, fontSize: 16),
      decoration: InputDecoration(
        hintText: t.chat.messageHint,
        isDense: true,
        filled: false,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
      ),
    );

    return ColoredBox(
      color: Colors.transparent,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(minHeight: 48),
                  padding: const EdgeInsets.only(left: 18, right: 4),
                  decoration: BoxDecoration(
                    color: colors.input,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 2, offset: const Offset(0, 1))],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: _isDesktop ? Focus(canRequestFocus: false, skipTraversal: true, onKeyEvent: _onKey, child: field) : field,
                      ),
                      IconButton(
                        tooltip: t.chat.attachment,
                        color: colors.meta,
                        icon: const Icon(Icons.attach_file_rounded),
                        onPressed: onAttach,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Always visible, dimmed while there is nothing to send.
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, value, _) {
                  final canSend = value.text.trim().isNotEmpty;
                  return AnimatedOpacity(
                    opacity: canSend ? 1 : 0.55,
                    duration: const Duration(milliseconds: 150),
                    child: SizedBox.square(
                      dimension: 48,
                      child: IconButton.filled(
                        tooltip: t.sendTab.title,
                        icon: const Icon(Icons.send_rounded, size: 22),
                        onPressed: _send,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
