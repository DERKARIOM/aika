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
import 'package:localsend_app/util/chat/chat_time_format.dart';
import 'package:localsend_app/util/device_type_ext.dart';
import 'package:localsend_app/util/native/cross_file_converters.dart';
import 'package:localsend_app/widget/chat/chat_composer.dart';
import 'package:localsend_app/widget/chat/chat_connection_banner.dart';
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

/// Messages loaded at once; scrolling up loads this many more.
const _pageSize = 200;

/// Consecutive messages of the same author closer than this are grouped.
const _groupGap = Duration(minutes: 2);

class _ChatConversationPageState extends State<ChatConversationPage> with Refena {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  StreamSubscription<List<ChatMessage>>? _messagesSub;
  List<ChatMessage> _messages = [];

  /// How many of the latest messages are watched (grows by [_pageSize]).
  int _limit = _pageSize;

  /// Scrolled up far enough to offer a jump back to the latest message.
  bool _showScrollToLatest = false;

  @override
  void initState() {
    super.initState();
    ensureRef((ref) {
      ref.notifier(chatProvider).currentlyOpenConversationFingerprint = widget.peerFingerprint;
      // Once on open: resets the badge and (re)opens the chat link.
      _markRead(ref);
      _watchMessages(ref);
    });
    _scrollController.addListener(_onScroll);
  }

  /// (Re)subscribes to the latest [_limit] messages.
  void _watchMessages(Ref ref) {
    unawaited(_messagesSub?.cancel());
    _messagesSub = ref.read(chatDatabaseProvider).watchMessages(widget.peerFingerprint, limit: _limit).listen((messages) {
      if (mounted) {
        setState(() => _messages = messages);
      }
      // New messages can arrive while this screen is already open; mark
      // them read as they come in. Other updates (e.g. the status of our
      // own messages) need nothing.
      if (messages.any(_isUnreadIncoming)) {
        _markRead(ref);
      }
    });
  }

  /// The list is reversed: offset 0 is the latest message, the end of the
  /// scroll extent the oldest one loaded.
  void _onScroll() {
    final position = _scrollController.position;
    final showScrollToLatest = position.pixels > 600;
    if (showScrollToLatest != _showScrollToLatest) {
      setState(() => _showScrollToLatest = showScrollToLatest);
    }
    // Near the oldest loaded message, and there may be older ones.
    if (position.pixels >= position.maxScrollExtent - 400 && _messages.length >= _limit) {
      _limit += _pageSize;
      _watchMessages(ref);
    }
  }

  void _scrollToLatest() {
    unawaited(_scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic));
  }

  /// Whether [later] directly continues [earlier] (same author, shortly
  /// after, same day): drawn as one group of bubbles.
  static bool _sameGroup(ChatMessage earlier, ChatMessage later) {
    return earlier.direction == later.direction &&
        later.createdAt.difference(earlier.createdAt) < _groupGap &&
        isSameChatDay(earlier.createdAt, later.createdAt);
  }

  @override
  void dispose() {
    unawaited(_messagesSub?.cancel());
    _scrollController.dispose();
    final chatService = ref.notifier(chatProvider);
    if (chatService.currentlyOpenConversationFingerprint == widget.peerFingerprint) {
      chatService.currentlyOpenConversationFingerprint = null;
    }
    // Best-effort: let the peer know we stopped typing when leaving the screen.
    unawaited(chatService.setTyping(target: _resolveDevice(ref), isTyping: false));
    _textController.dispose();
    super.dispose();
  }

  static bool _isUnreadIncoming(ChatMessage message) {
    return message.direction == ChatMessageDirectionColumn.incoming && message.status != ChatMessageStatusColumn.read;
  }

  void _markRead(Ref ref) {
    unawaited(ref.notifier(chatProvider).markConversationRead(_resolveDevice(ref)));
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
    final online = watchPeerOnline(context, widget.peerFingerprint);
    final typing = context.watch(chatProvider.select((s) => s.typingPeerFingerprints.contains(widget.peerFingerprint)));
    final lastSeenAt = context.watch(chatConversationsProvider.select((s) => s.byFingerprint(widget.peerFingerprint)?.lastSeenAt));
    final String presence;
    if (typing) {
      presence = t.chat.typing;
    } else if (online) {
      presence = t.chat.online;
    } else {
      presence = formatLastSeen(lastSeenAt) ?? t.chat.offline;
    }
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
                    presence,
                    style: TextStyle(
                      fontSize: 12,
                      color: typing ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
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
            ChatConnectionBanner(peerFingerprint: widget.peerFingerprint),
            Expanded(
              child: _messages.isEmpty
                  ? Center(
                      child: Text(t.chat.noMessagesYet, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    )
                  : Stack(
                      children: [
                        _buildMessageList(ref),
                        Positioned(
                          right: 16,
                          bottom: 12,
                          child: AnimatedScale(
                            scale: _showScrollToLatest ? 1 : 0,
                            duration: const Duration(milliseconds: 180),
                            child: FloatingActionButton.small(
                              heroTag: null,
                              tooltip: t.chat.scrollToLatest,
                              onPressed: _scrollToLatest,
                              child: const Icon(Icons.keyboard_arrow_down_rounded),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
            ChatComposer(
              controller: _textController,
              blocked: blocked,
              onChanged: (text) => unawaited(ref.notifier(chatProvider).setTyping(target: device, isTyping: text.isNotEmpty)),
              onSend: (text) {
                unawaited(ref.notifier(chatProvider).sendText(target: device, text: text));
                // Back to the latest message, where the new one appears.
                if (_scrollController.hasClients && _scrollController.offset > 0) {
                  _scrollToLatest();
                }
              },
              onAttach: () async {
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

  Widget _buildMessageList(Ref ref) {
    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final position = _messages.length - 1 - index;
        final message = _messages[position];
        final previous = position > 0 ? _messages[position - 1] : null;
        final next = position < _messages.length - 1 ? _messages[position + 1] : null;
        final bubble = ChatMessageBubble(
          key: ValueKey(message.id),
          message: message,
          groupedWithPrevious: previous != null && _sameGroup(previous, message),
          groupedWithNext: next != null && _sameGroup(message, next),
          onRetry: () => unawaited(ref.notifier(chatProvider).retryMessage(message.id)),
        );
        // The list is reversed: the separator goes above the first message
        // of each day.
        final firstOfDay = previous == null || !isSameChatDay(previous.createdAt, message.createdAt);
        if (!firstOfDay) {
          return bubble;
        }
        return Column(
          key: ValueKey('day-${message.id}'),
          children: [
            _DaySeparator(label: chatDayLabel(message.createdAt)),
            bubble,
          ],
        );
      },
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

class _DaySeparator extends StatelessWidget {
  final String label;

  const _DaySeparator({required this.label});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant)),
        ),
      ),
    );
  }
}
