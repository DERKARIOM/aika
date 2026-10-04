import 'dart:async';

import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/chat/chat_database.dart';
import 'package:localsend_app/pages/chat/chat_conversation_page.dart';
import 'package:localsend_app/provider/chat/chat_conversations_provider.dart';
import 'package:localsend_app/provider/chat/chat_database_provider.dart';
import 'package:localsend_app/util/chat/chat_device_resolver.dart';
import 'package:localsend_app/util/chat/chat_time_format.dart';
import 'package:localsend_app/util/device_type_ext.dart';
import 'package:localsend_app/widget/chat/chat_style.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

/// Searches the text and file names of every conversation. Results are the
/// newest first; tapping one opens its conversation on that message.
class ChatSearchPage extends StatefulWidget {
  const ChatSearchPage();

  @override
  State<ChatSearchPage> createState() => _ChatSearchPageState();
}

class _ChatSearchPageState extends State<ChatSearchPage> with Refena {
  /// Typing fast does not query the database on every keystroke.
  static const _debounce = Duration(milliseconds: 250);

  final _controller = TextEditingController();
  Timer? _timer;
  String _query = '';
  List<ChatMessage> _results = const [];

  /// Guards against an older, slower query overwriting a newer result.
  int _generation = 0;

  void _onChanged(String value) {
    _timer?.cancel();
    _timer = Timer(_debounce, () => unawaited(_search(value)));
    // Shows or hides the clear button right away.
    setState(() {});
  }

  Future<void> _search(String value) async {
    final generation = ++_generation;
    final query = value.trim();
    final results = query.isEmpty ? const <ChatMessage>[] : await ref.read(chatDatabaseProvider).searchMessages(query);
    if (mounted && generation == _generation) {
      setState(() {
        _query = query;
        _results = results;
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _controller,
          autofocus: true,
          onChanged: _onChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(hintText: t.chat.searchHint, border: InputBorder.none),
        ),
        actions: [
          if (_controller.text.isNotEmpty)
            IconButton(
              tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
              icon: const Icon(Icons.close_rounded),
              onPressed: () {
                _controller.clear();
                _onChanged('');
              },
            ),
        ],
      ),
      body: _query.isNotEmpty && _results.isEmpty
          ? Center(
              child: Text(t.chat.noResults, style: TextStyle(color: colorScheme.onSurfaceVariant)),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _results.length,
              itemBuilder: (context, index) => _SearchResultTile(
                key: ValueKey(_results[index].id),
                message: _results[index],
                query: _query,
              ),
            ),
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  final ChatMessage message;
  final String query;

  const _SearchResultTile({required this.message, required this.query, super.key});

  @override
  Widget build(BuildContext context) {
    final ref = context.ref;
    final theme = Theme.of(context);
    final conversation = context.watch(chatConversationsProvider).byFingerprint(message.conversationId);
    final device = conversation == null ? null : resolveConversationDevice(ref, conversation);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: ChatAvatar(
        icon: device?.deviceType.icon ?? Icons.person_rounded,
        online: false,
        ringColor: theme.scaffoldBackgroundColor,
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              conversation?.peerAlias ?? message.conversationId,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Text(
            formatConversationTimestamp(message.createdAt),
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
      subtitle: Text.rich(
        highlightChatMatch(_matchedText(message, query), query, theme.textTheme.bodyMedium!, theme.colorScheme.primary),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () async {
        await context.push(
          () => ChatConversationPage(peerFingerprint: message.conversationId, highlightMessageId: message.id),
        );
      },
    );
  }
}

/// The part of [message] that matched: its text, else its file name.
String _matchedText(ChatMessage message, String query) {
  final body = message.body ?? '';
  final fileName = message.attachmentFileName;
  if (fileName == null || body.toLowerCase().contains(query.toLowerCase())) {
    return body;
  }
  return fileName;
}

/// [text] on one line with the first occurrence of [query] in bold accent
/// color, starting a little before it so the match stays visible.
@visibleForTesting
TextSpan highlightChatMatch(String text, String query, TextStyle style, Color accent) {
  const lead = 30;
  final single = text.replaceAll('\n', ' ');
  final index = query.isEmpty ? -1 : single.toLowerCase().indexOf(query.toLowerCase());
  // Lower-casing can change the length of a few rare characters: then the
  // index does not map back, and the text is shown without highlight.
  if (index < 0 || index + query.length > single.length) {
    return TextSpan(text: single, style: style);
  }
  final start = index > lead ? index - lead : 0;
  final end = index + query.length;
  return TextSpan(
    style: style,
    children: [
      TextSpan(text: '${start > 0 ? '…' : ''}${single.substring(start, index)}'),
      TextSpan(
        text: single.substring(index, end),
        style: TextStyle(color: accent, fontWeight: FontWeight.w700),
      ),
      TextSpan(text: single.substring(end)),
    ],
  );
}
