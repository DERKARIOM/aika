import 'dart:async';

import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/chat/chat_database.dart';
import 'package:localsend_app/pages/chat/chat_conversation_page.dart';
import 'package:localsend_app/pages/chat/chat_search_page.dart';
import 'package:localsend_app/pages/chat/new_conversation_page.dart';
import 'package:localsend_app/provider/chat/chat_conversations_provider.dart';
import 'package:localsend_app/provider/chat/chat_provider.dart';
import 'package:localsend_app/util/chat/chat_device_resolver.dart';
import 'package:localsend_app/util/chat/chat_time_format.dart';
import 'package:localsend_app/util/device_type_ext.dart';
import 'package:localsend_app/widget/chat/chat_style.dart';
import 'package:localsend_app/widget/dialogs/chat_delete_conversation_dialog.dart';
import 'package:localsend_app/widget/responsive_list_view.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

/// Main "Discussions" tab: the entry point of the LAN-only chat feature.
///
/// Mirrors the visual language of [ReceiveTab]/[SendTab] (no classic
/// AppBar, a simple header row, rounded/glassy list tiles) rather than
/// introducing a new visual style.
class ChatTab extends StatelessWidget {
  const ChatTab();

  @override
  Widget build(BuildContext context) {
    final conversations = context.watch(chatConversationsProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return ResponsiveListView(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 4, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(t.chat.title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              ),
              if (conversations.isNotEmpty)
                IconButton(
                  tooltip: t.chat.search,
                  icon: const Icon(Icons.search_rounded),
                  onPressed: () async {
                    await context.push(() => const ChatSearchPage());
                  },
                ),
              IconButton.filledTonal(
                tooltip: t.chat.newConversation,
                icon: const Icon(Icons.edit_square),
                onPressed: () async {
                  await context.push(() => const NewConversationPage());
                },
              ),
            ],
          ),
        ),
        if (conversations.isEmpty)
          // Centré verticalement dans la zone visible : la liste ne contraint
          // pas sa hauteur, d'où une hauteur minimale imposée.
          ConstrainedBox(
            constraints: BoxConstraints(minHeight: MediaQuery.sizeOf(context).height * 0.55),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(color: colorScheme.primaryContainer, shape: BoxShape.circle),
                    child: Icon(Icons.forum_rounded, size: 42, color: colorScheme.onPrimaryContainer),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    t.chat.empty,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    icon: const Icon(Icons.edit_square),
                    label: Text(t.chat.newConversation),
                    onPressed: () async {
                      await context.push(() => const NewConversationPage());
                    },
                  ),
                ],
              ),
            ),
          )
        else
          ...conversations.map((conversation) => _ConversationTile(key: ValueKey(conversation.peerFingerprint), conversation: conversation)),
      ],
    );
  }
}

/// One conversation: avatar, name, last message (or "typing…"), time, and
/// the unread count. Unread conversations stand out (bold, accent time).
class _ConversationTile extends StatelessWidget {
  final ChatConversation conversation;

  const _ConversationTile({required this.conversation, super.key});

  @override
  Widget build(BuildContext context) {
    final ref = context.ref;
    final online = watchPeerOnline(context, conversation.peerFingerprint);
    final typing = ref.watch(chatProvider.select((s) => s.typingPeerFingerprints.contains(conversation.peerFingerprint.toUpperCase())));
    final device = resolveConversationDevice(ref, conversation);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final unread = conversation.unreadCount > 0;
    final lastAt = conversation.lastMessageAt;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () async {
        await context.push(() => ChatConversationPage(peerFingerprint: conversation.peerFingerprint));
      },
      onLongPress: () => _showQuickActions(context, ref),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            ChatAvatar(icon: device.deviceType.icon, online: online, radius: 26, ringColor: theme.scaffoldBackgroundColor),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          conversation.peerAlias,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (lastAt != null)
                        Text(
                          formatConversationTimestamp(lastAt),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: unread ? colorScheme.primary : colorScheme.onSurfaceVariant,
                            fontWeight: unread ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          typing ? t.chat.typing : (conversation.lastMessagePreview ?? t.chat.noMessagesYet),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: typing ? colorScheme.primary : (unread ? colorScheme.onSurface : colorScheme.onSurfaceVariant),
                            fontWeight: unread && !typing ? FontWeight.w500 : FontWeight.normal,
                          ),
                        ),
                      ),
                      if (unread) ...[
                        const SizedBox(width: 8),
                        Container(
                          constraints: const BoxConstraints(minWidth: 22),
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(color: colorScheme.primary, borderRadius: BorderRadius.circular(999)),
                          child: Text(
                            conversation.unreadCount > 99 ? '99+' : '${conversation.unreadCount}',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: colorScheme.onPrimary, fontSize: 12, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showQuickActions(BuildContext context, Ref ref) {
    unawaited(
      showModalBottomSheet(
        context: context,
        builder: (_) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.ios_share_outlined),
                title: Text(t.chat.export),
                onTap: () async {
                  Navigator.of(context).pop();
                  final device = resolveConversationDevice(ref, conversation);
                  final text = await ref.notifier(chatProvider).exportConversation(device);
                  if (!context.mounted) return;
                  _showExportPreview(context, text);
                },
              ),
              ListTile(
                leading: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
                title: Text(t.chat.deleteConversation),
                onTap: () async {
                  Navigator.of(context).pop();
                  final device = resolveConversationDevice(ref, conversation);
                  final confirmed = await showDialog<bool>(context: context, builder: (_) => const ChatDeleteConversationDialog());
                  if (confirmed == true) {
                    await ref.notifier(chatProvider).deleteConversation(device);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showExportPreview(BuildContext context, String text) {
    unawaited(
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(t.chat.export),
          content: SingleChildScrollView(child: SelectableText(text)),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(t.general.close)),
          ],
        ),
      ),
    );
  }
}
