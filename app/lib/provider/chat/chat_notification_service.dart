import 'dart:async';
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:localsend_app/model/chat/chat_envelope.dart';
import 'package:localsend_app/pages/chat/chat_conversation_page.dart';
import 'package:localsend_app/provider/chat/chat_provider.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:logging/logging.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

final _logger = Logger('ChatNotifications');

const _channelId = 'aika_chat_messages';
const _channelName = 'Messages';
const _channelDescription = 'Nouveaux messages de discussion';

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
  bool _initialized = false;

  ChatNotificationService(this._ref);

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;

    try {
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwinSettings = DarwinInitializationSettings();
      const linuxSettings = LinuxInitializationSettings(defaultActionName: 'Ouvrir');
      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
        macOS: darwinSettings,
        linux: linuxSettings,
      );

      await _plugin.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: (response) {
          final fingerprint = response.payload;
          if (fingerprint != null && fingerprint.isNotEmpty) {
            // ignore: discarded_futures, unawaited_futures
            Routerino.context.push(() => ChatConversationPage(peerFingerprint: fingerprint));
          }
        },
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
    } catch (e, st) {
      // Notifications are a nice-to-have on top of the chat feature, not a
      // hard requirement: never let a platform-specific quirk here break
      // messaging itself.
      _logger.warning('Failed to initialize chat notifications', e, st);
    }

    _ref.notifier(chatProvider).onIncomingMessage = _onIncomingMessage;
  }

  void _onIncomingMessage(Device sender, ChatEnvelope envelope) {
    // Don't notify about a message the user is already looking at - it is
    // shown (and immediately marked read) directly in the open conversation.
    if (_ref.notifier(chatProvider).currentlyOpenConversationFingerprint == sender.fingerprint) {
      return;
    }

    final body = switch (envelope.contentType) {
      ChatContentType.image => 'Photo',
      ChatContentType.video => 'Vidéo',
      ChatContentType.audio => 'Audio',
      ChatContentType.document => envelope.attachmentFileName ?? 'Document',
      ChatContentType.text || null => envelope.text ?? '',
    };

    unawaited(_show(sender: sender, body: body));
  }

  Future<void> _show({required Device sender, required String body}) async {
    try {
      const androidDetails = AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.message,
      );
      const details = NotificationDetails(
        android: androidDetails,
        iOS: DarwinNotificationDetails(presentAlert: true, presentBadge: true, presentSound: true),
        macOS: DarwinNotificationDetails(presentAlert: true, presentBadge: true, presentSound: true),
      );

      await _plugin.show(
        id: sender.fingerprint.hashCode,
        title: sender.alias,
        body: body,
        notificationDetails: details,
        payload: sender.fingerprint,
      );
    } catch (e, st) {
      _logger.warning('Failed to show chat notification', e, st);
    }
  }
}
