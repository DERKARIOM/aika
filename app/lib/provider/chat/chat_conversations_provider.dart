import 'package:localsend_app/model/chat/chat_database.dart';
import 'package:localsend_app/provider/chat/chat_database_provider.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// Live list of chat conversations (peer alias, last-seen, unread count).
///
/// Conversations themselves are cheap and few (one row per contact), unlike
/// messages, which can be numerous per conversation. That is why this list
/// is kept resident as an always-on provider (started once from
/// `postInit()`, exactly like `nearbyDevicesProvider`'s multicast listener),
/// while the *messages* of a given conversation are only loaded on demand
/// by `ChatConversationPage` itself while it is visible.
final chatConversationsProvider = ReduxProvider<ChatConversationsService, List<ChatConversation>>((ref) {
  return ChatConversationsService(ref.read(chatDatabaseProvider));
});

class ChatConversationsService extends ReduxNotifier<List<ChatConversation>> {
  final ChatDatabase db;

  ChatConversationsService(this.db);

  @override
  List<ChatConversation> init() => [];
}

extension ChatConversationsStateX on List<ChatConversation> {
  int get totalUnreadCount => fold(0, (sum, c) => sum + c.unreadCount);

  ChatConversation? byFingerprint(String fingerprint) {
    for (final c in this) {
      if (c.peerFingerprint == fingerprint) {
        return c;
      }
    }
    return null;
  }
}

/// Subscribes to the conversations table forever. Should be started exactly
/// once, from `postInit()`.
class StartWatchingChatConversationsAction extends AsyncReduxAction<ChatConversationsService, List<ChatConversation>> {
  @override
  Future<List<ChatConversation>> reduce() async {
    await for (final conversations in notifier.db.watchConversations()) {
      dispatch(_SetConversationsAction(conversations));
    }
    return state;
  }
}

class _SetConversationsAction extends ReduxAction<ChatConversationsService, List<ChatConversation>> {
  final List<ChatConversation> conversations;

  _SetConversationsAction(this.conversations);

  @override
  List<ChatConversation> reduce() => conversations;
}
