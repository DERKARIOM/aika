import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/chat/chat_database.dart';
import 'package:localsend_app/provider/chat/blocked_devices_provider.dart';
import 'package:localsend_app/provider/chat/chat_conversations_provider.dart';
import 'package:localsend_app/provider/chat/chat_database_provider.dart';
import 'package:localsend_app/provider/chat/chat_provider.dart';
import 'package:localsend_app/util/chat/chat_device_resolver.dart';
import 'package:localsend_app/util/device_type_ext.dart';
import 'package:localsend_app/util/native/cross_file_converters.dart';
import 'package:localsend_app/widget/chat/chat_message_bubble.dart';
import 'package:localsend_app/widget/dialogs/chat_delete_conversation_dialog.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// A single 1:1 conversation screen: message list + composer, WhatsApp/
/// Telegram-inspired. Manages its own live subscription to
/// `ChatDatabase.watchMessages` (like `QrPairingDisplayPage` manages its own
/// countdown `Timer`) rather than routing the (potentially large, and only
/// ever needed while this exact screen is visible) message list through a
/// global provider - see the architecture notes in `chat_provider.dart`.
class ChatConversationPage extends StatefulWidget {
  final String peerFingerprint;

  const ChatConversationPage({required this.peerFingerprint});

  @override
  State<ChatConversationPage> createState() => _ChatConversationPageState();
}

class _ChatConversationPageState extends State<ChatConversationPage> with Refena {
  final _textController = TextEditingController();
  StreamSubscription<List<ChatMessage>>? _messagesSub;
  List<ChatMessage> _messages = [];

  @override
  void initState() {
    super.initState();
    ensureRef((ref) {
      ref.notifier(chatProvider).currentlyOpenConversationFingerprint = widget.peerFingerprint;
      _messagesSub = ref.read(chatDatabaseProvider).watchMessages(widget.peerFingerprint).listen((messages) {
        if (mounted) {
          setState(() => _messages = messages);
        }
        // New messages can arrive while this screen is already open; keep
        // marking them read as they come in, not just once on open.
        _markRead(ref);
      });
    });
  }

  @override
  void dispose() {
    _messagesSub?.cancel();
    final chatService = ref.notifier(chatProvider);
    if (chatService.currentlyOpenConversationFingerprint == widget.peerFingerprint) {
      chatService.currentlyOpenConversationFingerprint = null;
    }
    // Best-effort: let the peer know we stopped typing when leaving the screen.
    chatService.setTyping(target: _resolveDevice(ref), isTyping: false);
    _textController.dispose();
    super.dispose();
  }

  void _markRead(Ref ref) {
    ref.notifier(chatProvider).markConversationRead(_resolveDevice(ref));
  }

  Device _resolveDevice(Ref ref) {
    final conversation = ref.read(chatConversationsProvider).byFingerprint(widget.peerFingerprint);
    return resolveDeviceByFingerprint(
      ref,
      widget.peerFingerprint,
      fallbackAlias: conversation?.peerAlias,
      fallbackDeviceModel: conversation?.peerDeviceModel,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ref = context.ref;
    final device = _resolveDevice(ref);
    final online = isDeviceOnline(ref, widget.peerFingerprint);
    final typing = context.watch(chatProvider.select((s) => s.typingPeerFingerprints.contains(widget.peerFingerprint)));
    final blocked = context.watch(blockedDevicesProvider).isFingerprintBlocked(widget.peerFingerprint);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(radius: 18, child: Icon(device.deviceType.icon, size: 18)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(device.alias, style: const TextStyle(fontSize: 16)),
                  Text(
                    typing ? t.chat.typing : (online ? t.chat.online : t.chat.offline),
                    style: TextStyle(fontSize: 12, color: typing ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) async {
              switch (value) {
                case 'export':
                  final text = await ref.notifier(chatProvider).exportConversation(device);
                  if (context.mounted) _showExportPreview(context, text);
                  break;
                case 'delete':
                  final confirmed = await showDialog<bool>(context: context, builder: (_) => const ChatDeleteConversationDialog());
                  if (confirmed == true) {
                    await ref.notifier(chatProvider).deleteConversation(device);
                    if (context.mounted) Navigator.of(context).pop();
                  }
                  break;
                case 'block':
                  await ref.notifier(chatProvider).blockDevice(device);
                  break;
                case 'unblock':
                  await ref.notifier(chatProvider).unblockDevice(widget.peerFingerprint);
                  break;
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'export', child: Text(t.chat.export)),
              PopupMenuItem(value: 'delete', child: Text(t.chat.deleteConversation)),
              PopupMenuItem(value: blocked ? 'unblock' : 'block', child: Text(blocked ? t.chat.unblock : t.chat.block)),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _messages.isEmpty
                  ? Center(
                      child: Text(t.chat.noMessagesYet, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    )
                  : ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final message = _messages[_messages.length - 1 - index];
                        return ChatMessageBubble(message: message);
                      },
                    ),
            ),
            _Composer(
              controller: _textController,
              blocked: blocked,
              onChanged: (text) => ref.notifier(chatProvider).setTyping(target: device, isTyping: text.isNotEmpty),
              onSendText: () {
                final text = _textController.text;
                _textController.clear();
                ref.notifier(chatProvider).sendText(target: device, text: text);
              },
              onSendFile: () async {
                final file = await openFile();
                if (file == null) {
                  return;
                }
                final crossFile = await CrossFileConverters.convertXFile(file);
                await ref.notifier(chatProvider).sendMedia(target: device, file: crossFile);
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

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final bool blocked;
  final ValueChanged<String> onChanged;
  final VoidCallback onSendText;
  final VoidCallback onSendFile;

  const _Composer({
    required this.controller,
    required this.blocked,
    required this.onChanged,
    required this.onSendText,
    required this.onSendFile,
  });

  @override
  Widget build(BuildContext context) {
    if (blocked) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(t.chat.blockedNotice, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant), textAlign: TextAlign.center),
      );
    }

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
        child: Row(
          children: [
            IconButton(
              tooltip: t.chat.attachment,
              icon: const Icon(Icons.attach_file_rounded),
              onPressed: onSendFile,
            ),
            Expanded(
              child: TextField(
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
                onSubmitted: (_) => onSendText(),
              ),
            ),
            const SizedBox(width: 4),
            IconButton.filled(
              icon: const Icon(Icons.send_rounded),
              onPressed: () {
                if (controller.text.trim().isNotEmpty) {
                  onSendText();
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
