import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/chat/chat_database.dart';
import 'package:localsend_app/pages/chat/chat_conversation_page.dart';
import 'package:localsend_app/pages/chat/new_conversation_page.dart';
import 'package:localsend_app/provider/chat/chat_conversations_provider.dart';
import 'package:localsend_app/provider/chat/chat_provider.dart';
import 'package:localsend_app/util/chat/chat_device_resolver.dart';
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

    return ResponsiveListView(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 20),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(t.chat.title, style: Theme.of(context).textTheme.headlineSmall),
            ),
            IconButton(
              tooltip: t.chat.newConversation,
              icon: const Icon(Icons.add_comment_outlined),
              onPressed: () async {
                await context.push(() => const NewConversationPage());
              },
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (conversations.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 60),
            child: Column(
              children: [
                Icon(Icons.chat_bubble_outline_rounded, size: 56, color: Theme.of(context).colorScheme.outline),
                const SizedBox(height: 16),
                Text(
                  t.chat.empty,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          )
        else
          ...conversations.map((conversation) => _ConversationTile(conversation: conversation)),
      ],
    );
  }
}

class _ConversationTile extends StatelessWidget {
  final ChatConversation conversation;

  const _ConversationTile({required this.conversation});

  @override
  Widget build(BuildContext context) {
    final ref = context.ref;
    final online = isDeviceOnline(ref, conversation.peerFingerprint);
    final typing = ref.watch(chatProvider.select((s) => s.typingPeerFingerprints.contains(conversation.peerFingerprint)));
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () async {
            await context.push(() => ChatConversationPage(peerFingerprint: conversation.peerFingerprint));
          },
          onLongPress: () => _showQuickActions(context, ref),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Stack(
                  children: [
                    CircleAvatar(radius: 24, child: const Icon(Icons.person_outline)),
                    if (online)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                            border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 2),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(conversation.peerAlias, style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        typing ? t.chat.typing : (conversation.lastMessagePreview ?? t.chat.noMessagesYet),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: typing ? colorScheme.primary : Theme.of(context).colorScheme.onSurfaceVariant,
                          fontStyle: typing ? FontStyle.italic : FontStyle.normal,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (conversation.lastMessageAt != null)
                      Text(_formatTime(conversation.lastMessageAt!), style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 6),
                    if (conversation.unreadCount > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(color: colorScheme.primary, borderRadius: BorderRadius.circular(999)),
                        child: Text(
                          conversation.unreadCount > 99 ? '99+' : '${conversation.unreadCount}',
                          style: TextStyle(color: colorScheme.onPrimary, fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showQuickActions(BuildContext context, Ref ref) {
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
    );
  }

  void _showExportPreview(BuildContext context, String text) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(t.chat.export),
        content: SingleChildScrollView(child: SelectableText(text)),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(t.general.close)),
        ],
      ),
    );
  }
}

String _formatTime(DateTime utc) {
  final local = utc.toLocal();
  final now = DateTime.now();
  if (local.year == now.year && local.month == now.month && local.day == now.day) {
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
  return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}';
}
