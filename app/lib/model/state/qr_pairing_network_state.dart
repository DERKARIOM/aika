/// State of the "prepare a usable local network before showing the Smart QR
/// Code" flow on [QrPairingDisplayPage].
///
/// This is plain, hand-written local UI state (not a `dart_mappable` /
/// Refena redux state): it lives only inside the page's `State` object and is
/// never observed elsewhere, so it doesn't need the equality/copyWith codegen
/// machinery used by actual app-wide providers (e.g. `NetworkState`).
enum QrNetworkPrepStatus {
  /// Checking whether the device already has a usable local network.
  checking,

  /// A local network is already available (existing Wi-Fi, Ethernet, an
  /// already-active hotspot, ...): behaves exactly like before this feature
  /// existed.
  ready,

  /// No network was available; a local-only Wi-Fi hotspot is being started
  /// (Android only).
  activatingHotspot,

  /// The hotspot (or a network the user just enabled manually via Settings)
  /// reported as started/likely-active; waiting for `localIpProvider` to
  /// pick up a usable IP address on it.
  waitingForIp,

  /// A freshly created local-only hotspot is active and has an IP: the QR
  /// code can be generated, and the hotspot's SSID/password should be shown
  /// next to it so a second device can join the same network.
  hotspotReady,

  /// Brief transitional confirmation ("Your network is ready") shown right
  /// after the hotspot got an IP address and right before the QR code
  /// itself appears, so the loading state doesn't jump straight to the QR
  /// without any acknowledgement.
  readyFlash,

  /// Automatic activation is not possible (iOS, unsupported Android
  /// version, permission permanently denied, or the platform call failed):
  /// the user must enable a hotspot/Wi-Fi manually via system Settings.
  needsManualAction,

  /// A manual action is in flight: Settings was opened and we are waiting
  /// for the user to come back to the app before re-checking connectivity.
  waitingForUserInSettings,

  /// Preparation failed (e.g. timed out waiting for an IP after the
  /// hotspot/Settings round-trip) and there is nothing more to try
  /// automatically.
  failed,
}

class QrNetworkPrepState {
  final QrNetworkPrepStatus status;

  /// SSID of the local-only hotspot, when [status] is [QrNetworkPrepStatus.hotspotReady].
  final String? hotspotSsid;

  /// Passphrase of the local-only hotspot, when [status] is [QrNetworkPrepStatus.hotspotReady].
  final String? hotspotPassphrase;

  /// Human-readable reason, set for [QrNetworkPrepStatus.needsManualAction] and
  /// [QrNetworkPrepStatus.failed].
  final String? reason;

  const QrNetworkPrepState({
    required this.status,
    this.hotspotSsid,
    this.hotspotPassphrase,
    this.reason,
  });

  const QrNetworkPrepState.checking() : this(status: QrNetworkPrepStatus.checking);

  const QrNetworkPrepState.ready() : this(status: QrNetworkPrepStatus.ready);

  const QrNetworkPrepState.activatingHotspot() : this(status: QrNetworkPrepStatus.activatingHotspot);

  const QrNetworkPrepState.waitingForIp() : this(status: QrNetworkPrepStatus.waitingForIp);

  const QrNetworkPrepState.hotspotReady({required String? ssid, required String? passphrase})
    : this(status: QrNetworkPrepStatus.hotspotReady, hotspotSsid: ssid, hotspotPassphrase: passphrase);

  const QrNetworkPrepState.readyFlash() : this(status: QrNetworkPrepStatus.readyFlash);

  const QrNetworkPrepState.needsManualAction({String? reason})
    : this(status: QrNetworkPrepStatus.needsManualAction, reason: reason);

  const QrNetworkPrepState.waitingForUserInSettings() : this(status: QrNetworkPrepStatus.waitingForUserInSettings);

  const QrNetworkPrepState.failed({String? reason}) : this(status: QrNetworkPrepStatus.failed, reason: reason);
}
