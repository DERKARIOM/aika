import 'dart:async';
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/chat/chat_envelope.dart';
import 'package:localsend_app/pages/chat/chat_conversation_page.dart';
import 'package:localsend_app/provider/chat/chat_provider.dart';
import 'package:localsend_app/util/chat/chat_preview.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:logging/logging.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

final _logger = Logger('ChatNotifications');

const _channelId = 'aika_chat_messages';

/// Windows identity of Aika's notifications. Both must stay the same from
/// one version to the next: Windows ties notifications (and the user's
/// notification settings) to them.
const _windowsAppUserModelId = 'Aika.Aika';
const _windowsNotificationGuid = 'b2d4be65-9348-4382-b5ac-39adfed56c32';

/// Notification id of a conversation. Derived from the fingerprint (hex)
/// rather than `String.hashCode`, which changes between runs: a
/// notification left over from a previous run must still be replaced and
/// cleared.
int chatNotificationId(String fingerprint) {
  final head = fingerprint.length >= 7 ? fingerprint.substring(0, 7) : fingerprint;
  return int.tryParse(head, radix: 16) ?? fingerprint.hashCode & 0x7FFFFFFF;
}

/// The not-yet-read messages shown in each conversation's notification.
class ChatNotificationInbox {
  /// Messages kept per conversation; older ones only count.
  static const maxShown = 6;

  final Map<String, List<(String, DateTime)>> _messages = {};
  final Map<String, int> _counts = {};

  /// Adds a message and returns what the conversation's notification shows.
  ({List<(String, DateTime)> shown, int count}) add(String fingerprint, String text, DateTime at) {
    final list = _messages.putIfAbsent(fingerprint, () => []);
    list.add((text, at));
    if (list.length > maxShown) {
      list.removeAt(0);
    }
    final count = (_counts[fingerprint] ?? 0) + 1;
    _counts[fingerprint] = count;
    return (shown: List.unmodifiable(list), count: count);
  }

  void clear(String fingerprint) {
    _messages.remove(fingerprint);
    _counts.remove(fingerprint);
  }
}

/// Bridges [ChatService] (new incoming messages) to local OS notifications.
///
/// Deliberately a thin, self-contained adapter rather than logic baked into
/// `ChatService` itself: the chat layer stays fully testable/usable without
/// ever depending on the notification plugin (see `ChatService.onIncomingMessage`).
final chatNotificationServiceProvider = Provider<ChatNotificationService>((ref) {
  return ChatNotificationService(ref);
});

class ChatNotificationService {
  final Ref _ref;
  final _plugin = FlutterLocalNotificationsPlugin();
  final _inbox = ChatNotificationInbox();
  bool _initialized = false;

  ChatNotificationService(this._ref);

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;

    _ref.notifier(chatProvider)
      ..onIncomingMessage = _onIncomingMessage
      ..onConversationRead = _clear;

    try {
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwinSettings = DarwinInitializationSettings();
      final linuxSettings = LinuxInitializationSettings(defaultActionName: t.chat.notification.open);
      // Required by the plugin on Windows: without it, initialize() throws
      // and the PC never shows a chat notification.
      const windowsSettings = WindowsInitializationSettings(
        appName: 'Aika',
        appUserModelId: _windowsAppUserModelId,
        guid: _windowsNotificationGuid,
      );
      final initSettings = InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
        macOS: darwinSettings,
        linux: linuxSettings,
        windows: windowsSettings,
      );

      await _plugin.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: (response) => _open(response.payload),
      );

      if (Platform.isAndroid) {
        // No explicit createNotificationChannel() call: passing an
        // AndroidNotificationDetails with this channel id/name/description
        // to show() below lazily creates the channel on first use, which
        // keeps this code resilient to the plugin's channel-API churn.
        await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
      } else if (Platform.isIOS || Platform.isMacOS) {
        await _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
        await _plugin.resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>()?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
      }

      // The app was started by tapping a chat notification: the tap
      // callback above never fires in that case.
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch != null && launch.didNotificationLaunchApp) {
        _open(launch.notificationResponse?.payload);
      }
    } catch (e, st) {
      // Notifications are a nice-to-have on top of the chat feature, not a
      // hard requirement: never let a platform-specific quirk here break
      // messaging itself.
      _logger.warning('Failed to initialize chat notifications', e, st);
    }
  }

  /// Opens the conversation of a tapped notification, unless it is already
  /// the one on screen.
  void _open(String? fingerprint) {
    if (fingerprint == null || fingerprint.isEmpty) {
      return;
    }
    if (_ref.notifier(chatProvider).currentlyOpenConversationFingerprint == fingerprint) {
      return;
    }
    // ignore: discarded_futures, unawaited_futures
    Routerino.context.push(() => ChatConversationPage(peerFingerprint: fingerprint));
  }

  void _clear(String fingerprint) {
    _inbox.clear(fingerprint);
    unawaited(
      _plugin.cancel(id: chatNotificationId(fingerprint)).catchError((Object e) {
        _logger.fine('Failed to clear chat notification: $e');
      }),
    );
  }

  void _onIncomingMessage(Device sender, ChatEnvelope envelope) {
    // Don't notify about a message the user is already looking at - it is
    // shown (and immediately marked read) directly in the open conversation.
    if (_ref.notifier(chatProvider).currentlyOpenConversationFingerprint == sender.fingerprint) {
      return;
    }

    final text = chatPreviewText(
      envelope.contentType ?? ChatContentType.text,
      text: envelope.text,
      attachmentFileName: envelope.attachmentFileName,
    );
    final (:shown, :count) = _inbox.add(sender.fingerprint, text, envelope.timestamp.toLocal());
    unawaited(_show(sender: sender, shown: shown, count: count));
  }

  Future<void> _show({required Device sender, required List<(String, DateTime)> shown, required int count}) async {
    try {
      final person = Person(name: sender.alias, key: sender.fingerprint);
      final androidDetails = AndroidNotificationDetails(
        _channelId,
        t.chat.notification.channelName,
        channelDescription: t.chat.notification.channelDescription,
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.message,
        number: count,
        styleInformation: MessagingStyleInformation(
          person,
          messages: [for (final (text, at) in shown) Message(text, at, person)],
        ),
      );
      final details = NotificationDetails(
        android: androidDetails,
        iOS: DarwinNotificationDetails(presentAlert: true, presentBadge: true, presentSound: true, threadIdentifier: sender.fingerprint),
        macOS: DarwinNotificationDetails(presentAlert: true, presentBadge: true, presentSound: true, threadIdentifier: sender.fingerprint),
      );

      final latest = shown.last.$1;
      await _plugin.show(
        id: chatNotificationId(sender.fingerprint),
        title: sender.alias,
        // Platforms without a messaging style show the latest message, and
        // how many are waiting.
        body: count > 1 ? '${t.chat.notification.newMessages(count: count)} · $latest' : latest,
        notificationDetails: details,
        payload: sender.fingerprint,
      );
    } catch (e, st) {
      _logger.warning('Failed to show chat notification', e, st);
    }
  }
}
