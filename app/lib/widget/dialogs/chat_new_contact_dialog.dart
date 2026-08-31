import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/util/device_type_ext.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:routerino/routerino.dart';

/// Shown exactly once per unknown device, the first time it sends a chat
/// message: explicit user consent before a conversation - and the implicit
/// trust that comes with auto-accepting its future messages - is created.
/// Already-favorited devices and devices with an existing conversation skip
/// this (see `ReceiveController`'s chat branch).
class ChatNewContactDialog extends StatelessWidget {
  final Device sender;

  const ChatNewContactDialog({required this.sender});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      icon: Icon(Icons.chat_bubble_outline_rounded, color: colorScheme.primary, size: 36),
      title: Text(t.chat.newContact.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(child: Icon(sender.deviceType.icon)),
            title: Text(sender.alias, style: Theme.of(context).textTheme.titleMedium),
            subtitle: Text([if (sender.deviceModel != null) sender.deviceModel!, sender.ip ?? '-'].join(' · ')),
          ),
          const SizedBox(height: 8),
          Text(
            t.chat.newContact.description,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => context.pop(false),
          child: Text(t.chat.newContact.block),
        ),
        FilledButton(
          onPressed: () => context.pop(true),
          child: Text(t.chat.newContact.accept),
        ),
      ],
    );
  }
}
