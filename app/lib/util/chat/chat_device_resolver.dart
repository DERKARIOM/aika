import 'package:collection/collection.dart';
import 'package:localsend_app/model/chat/chat_database.dart';
import 'package:localsend_app/provider/favorites_provider.dart';
import 'package:localsend_app/provider/network/nearby_devices_provider.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// Resolves the best currently-known [Device] for a chat peer.
///
/// A conversation only stores the peer's fingerprint (its permanent
/// identity), never a fixed IP - exactly like `FavoriteDevice`, this keeps
/// conversations valid across DHCP lease changes / device restarts. This
/// helper reconstructs a full [Device] on demand:
/// 1. If the peer is currently visible via discovery, use that (fresh IP,
///    guaranteed reachable).
/// 2. Otherwise, fall back to its `FavoriteDevice` entry, if any (last
///    known IP - may be stale, but better than nothing while offline).
/// 3. Otherwise, a "ghost" [Device] with `ip: null`, which every send
///    attempt in `ChatService` recognizes as unreachable and queues in the
///    persistent outbox instead of trying to connect.
Device resolveConversationDevice(Ref ref, ChatConversation conversation) {
  return resolveDeviceByFingerprint(
    ref,
    conversation.peerFingerprint,
    fallbackAlias: conversation.peerAlias,
    fallbackDeviceModel: conversation.peerDeviceModel,
  );
}

/// Same as [resolveConversationDevice], but usable before a conversation
/// row exists yet (e.g. the very first message of a brand-new chat opened
/// from [NewConversationPage]).
Device resolveDeviceByFingerprint(
  Ref ref,
  String fingerprint, {
  String? fallbackAlias,
  String? fallbackDeviceModel,
}) {
  for (final device in ref.read(nearbyDevicesProvider).devices.values) {
    if (device.fingerprint == fingerprint) {
      return device;
    }
  }

  final favorite = ref.read(favoritesProvider).firstWhereOrNull((f) => f.fingerprint == fingerprint);

  return Device(
    signalingId: null,
    ip: favorite?.ip,
    version: '2.1',
    port: favorite?.port ?? -1,
    https: true,
    fingerprint: fingerprint,
    alias: favorite?.alias ?? fallbackAlias ?? fingerprint.substring(0, fingerprint.length < 8 ? fingerprint.length : 8),
    deviceModel: fallbackDeviceModel,
    deviceType: DeviceType.mobile,
    download: false,
    discoveryMethods: const {},
  );
}

/// Whether [fingerprint] is currently visible via discovery (i.e. reachable
/// right now, as opposed to just "known").
bool isDeviceOnline(Ref ref, String fingerprint) {
  return ref.read(nearbyDevicesProvider).devices.values.any((d) => d.fingerprint == fingerprint);
}
