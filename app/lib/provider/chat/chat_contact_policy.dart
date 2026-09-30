import 'dart:async';

import 'package:flutter/material.dart';
import 'package:localsend_app/provider/chat/blocked_devices_provider.dart';
import 'package:localsend_app/provider/chat/chat_database_provider.dart';
import 'package:localsend_app/provider/favorites_provider.dart';
import 'package:localsend_app/widget/dialogs/chat_new_contact_dialog.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

/// Whether chat traffic from [sender] may be accepted, whatever the
/// transport (legacy envelope or WebSocket):
/// - blocked devices: never;
/// - devices with a conversation, or favorites: always;
/// - anyone else: asked once with [ChatNewContactDialog]; "Block" blocks it.
///
/// Concurrent calls for the same device share one dialog.
Future<bool> acceptChatSender(Ref ref, Device sender) async {
  final pending = _pending[sender.fingerprint];
  if (pending != null) {
    return pending;
  }
  final decision = _decide(ref, sender);
  _pending[sender.fingerprint] = decision;
  try {
    return await decision;
  } finally {
    // Discards the returned future on purpose: it is `decision` itself.
    unawaited(_pending.remove(sender.fingerprint));
  }
}

final _pending = <String, Future<bool>>{};

Future<bool> _decide(Ref ref, Device sender) async {
  final fingerprint = sender.fingerprint;
  if (ref.read(blockedDevicesProvider).isFingerprintBlocked(fingerprint)) {
    return false;
  }
  if (await ref.read(chatDatabaseProvider).getConversation(fingerprint) != null) {
    return true;
  }
  if (ref.read(favoritesProvider).any((f) => f.fingerprint == fingerprint)) {
    return true;
  }

  // First message ever from this device: ask once, explicitly.
  final accepted = await showDialog<bool>(
    // ignore: use_build_context_synchronously
    context: Routerino.context,
    builder: (_) => ChatNewContactDialog(sender: sender),
  );
  if (accepted == false) {
    // The user explicitly chose "Block" rather than dismissing the dialog.
    await ref.redux(blockedDevicesProvider).dispatchAsync(BlockDeviceAction(fingerprint: fingerprint, alias: sender.alias));
  }
  return accepted == true;
}
