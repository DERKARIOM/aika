import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:routerino/routerino.dart';

/// Confirms permanently deleting a conversation (and all its messages)
/// from the local database. There is no undo and nothing is sent to the
/// peer - this only affects the local copy of the conversation.
class ChatDeleteConversationDialog extends StatelessWidget {
  const ChatDeleteConversationDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(t.chat.deleteConversation),
      content: Text(t.chat.deleteConversationConfirm),
      actions: [
        TextButton(
          onPressed: () => context.pop(false),
          child: Text(t.general.cancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
          onPressed: () => context.pop(true),
          child: Text(t.chat.deleteConversation),
        ),
      ],
    );
  }
}
