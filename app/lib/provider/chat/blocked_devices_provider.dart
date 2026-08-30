import 'package:localsend_app/model/chat/chat_database.dart';
import 'package:localsend_app/provider/chat/chat_database_provider.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// The list of devices the user explicitly blocked from chatting with them.
///
/// Mirrors `favoritesProvider`'s shape (a fingerprint-keyed trust list) but
/// for the opposite purpose: any incoming chat envelope or chat-media
/// `prepare-upload` request whose sender fingerprint is in this list is
/// silently dropped, before any user-visible confirmation UI is shown (see
/// the chat branch added to `ReceiveController.onPrepareUpload`).
///
/// Kept in sync with the on-disk table via a long-lived subscription
/// ([StartWatchingBlockedDevicesAction]), started once in `postInit()`,
/// exactly like `StartMulticastListener` keeps `nearbyDevicesProvider` in
/// sync with the discovery isolate.
final blockedDevicesProvider = ReduxProvider<BlockedDevicesService, List<ChatBlockedDevice>>((ref) {
  return BlockedDevicesService(ref.read(chatDatabaseProvider));
});

class BlockedDevicesService extends ReduxNotifier<List<ChatBlockedDevice>> {
  final ChatDatabase _db;

  BlockedDevicesService(this._db);

  ChatDatabase get db => _db;

  @override
  List<ChatBlockedDevice> init() => [];
}

extension BlockedDevicesStateX on List<ChatBlockedDevice> {
  bool isFingerprintBlocked(String fingerprint) => any((d) => d.fingerprint == fingerprint);
}

/// Subscribes to the blocked-devices table forever. Should be started
/// exactly once, from `postInit()`.
class StartWatchingBlockedDevicesAction extends AsyncReduxAction<BlockedDevicesService, List<ChatBlockedDevice>> {
  @override
  Future<List<ChatBlockedDevice>> reduce() async {
    await for (final devices in notifier.db.watchBlockedDevices()) {
      dispatch(_SetBlockedDevicesAction(devices));
    }
    return state;
  }
}

class _SetBlockedDevicesAction extends ReduxAction<BlockedDevicesService, List<ChatBlockedDevice>> {
  final List<ChatBlockedDevice> devices;

  _SetBlockedDevicesAction(this.devices);

  @override
  List<ChatBlockedDevice> reduce() => devices;
}

class BlockDeviceAction extends AsyncReduxAction<BlockedDevicesService, List<ChatBlockedDevice>> {
  final String fingerprint;
  final String alias;

  BlockDeviceAction({required this.fingerprint, required this.alias});

  @override
  Future<List<ChatBlockedDevice>> reduce() async {
    await notifier.db.blockDevice(fingerprint: fingerprint, alias: alias);
    // The table watcher (StartWatchingBlockedDevicesAction) will push the
    // authoritative new state; return the current state in the meantime.
    return state;
  }
}

class UnblockDeviceAction extends AsyncReduxAction<BlockedDevicesService, List<ChatBlockedDevice>> {
  final String fingerprint;

  UnblockDeviceAction(this.fingerprint);

  @override
  Future<List<ChatBlockedDevice>> reduce() async {
    await notifier.db.unblockDevice(fingerprint);
    return state;
  }
}
