import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:localsend_app/util/native/channel/android_channel.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:logging/logging.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:system_settings_2/system_settings_2.dart';

/// Helpers backing the "no Wi-Fi? try a local-only hotspot" step of the
/// Smart QR Code pairing feature (see [QrPairingDisplayPage]).
///
/// Kept platform-check-based (like the rest of `lib/util/native/`) rather
/// than tied to Refena, so it can be unit-tested and reused independently of
/// the page's widget state.
final _logger = Logger('HotspotHelper');

/// Whether the device currently reports a usable local network (Wi-Fi or
/// Ethernet). Mobile data alone does *not* count: it cannot reach another
/// device on the same LAN, which is what the Smart QR Code pairing needs.
Future<bool> hasUsableNetworkConnection() async {
  try {
    final results = await Connectivity().checkConnectivity();
    return results.any((r) => r == ConnectivityResult.wifi || r == ConnectivityResult.ethernet);
  } catch (e) {
    _logger.warning('Failed to check connectivity', e);
    // Fail open: let the caller fall back to its normal "wait for an IP"
    // path instead of assuming there is definitely no network.
    return true;
  }
}

/// Whether this platform could ever support automatic local-only hotspot
/// activation. Only `WifiManager.startLocalOnlyHotspot()` on Android (API
/// 26+, checked again at the native layer) can start a hotspot without
/// sending the user to system Settings; iOS and desktop platforms never can
/// (see the feature's architecture notes).
bool get canAutoActivateHotspot => checkPlatform([TargetPlatform.android]);

/// Outcome of [tryActivateLocalOnlyHotspot].
class HotspotActivationResult {
  final bool success;
  final String? ssid;
  final String? passphrase;

  /// Machine-readable failure reason (native error code, "permission_denied",
  /// or "unsupported_platform") — not shown to the user directly, but useful
  /// for logging/telemetry and for deciding whether retrying makes sense.
  final String? failureReason;

  const HotspotActivationResult.success({this.ssid, this.passphrase}) : success = true, failureReason = null;

  const HotspotActivationResult.failure(this.failureReason) : success = false, ssid = null, passphrase = null;
}

/// Requests whichever runtime permission `startLocalOnlyHotspot` needs for
/// [androidSdkInt]: `NEARBY_WIFI_DEVICES` on Android 13+ (API 33), or
/// `ACCESS_FINE_LOCATION` below that. See AndroidManifest.xml for why both
/// are declared and the wifi-permissions architecture note for the sources.
Future<bool> requestHotspotPermission(int? androidSdkInt) async {
  final permission = (androidSdkInt ?? 0) >= 33 ? Permission.nearbyWifiDevices : Permission.locationWhenInUse;
  try {
    final status = await permission.request();
    return status.isGranted;
  } catch (e) {
    _logger.warning('Failed to request hotspot permission', e);
    return false;
  }
}

/// Attempts to start a local-only Wi-Fi hotspot (Android only), requesting
/// the necessary runtime permission first.
///
/// Never throws: every failure (unsupported platform/OS version, permission
/// denied, or the platform call itself failing — e.g. because system
/// Location services are off, which some OEMs additionally require) is
/// reported through [HotspotActivationResult.failure] so the caller can fall
/// back to guiding the user to Settings instead of retrying blindly.
Future<HotspotActivationResult> tryActivateLocalOnlyHotspot({required int? androidSdkInt}) async {
  if (!canAutoActivateHotspot) {
    return const HotspotActivationResult.failure('unsupported_platform');
  }

  final granted = await requestHotspotPermission(androidSdkInt);
  if (!granted) {
    return const HotspotActivationResult.failure('permission_denied');
  }

  try {
    final info = await startLocalOnlyHotspotAndroid();
    return HotspotActivationResult.success(ssid: info.ssid, passphrase: info.passphrase);
  } on LocalOnlyHotspotException catch (e) {
    _logger.warning('Local-only hotspot activation failed: ${e.code}');
    return HotspotActivationResult.failure(e.code);
  } catch (e) {
    _logger.warning('Local-only hotspot activation failed', e);
    return const HotspotActivationResult.failure('unknown');
  }
}

/// Stops the local-only hotspot started by [tryActivateLocalOnlyHotspot], if
/// any is still active. Safe to call unconditionally (e.g. when leaving the
/// QR pairing page) even if no hotspot was ever started.
Future<void> stopLocalOnlyHotspotIfActive() async {
  if (!canAutoActivateHotspot) {
    return;
  }
  try {
    await stopLocalOnlyHotspotAndroid();
  } catch (e) {
    _logger.warning('Failed to stop local-only hotspot', e);
  }
}

/// Opens the best available system settings screen for enabling Wi-Fi / a
/// hotspot manually. This is the fallback used whenever automatic
/// activation is not possible or failed.
///
/// Best-effort by nature: on iOS there is no public, reliable deep link
/// straight to the Personal Hotspot screen (Apple does not expose one), so
/// this may only open the general Settings app. The calling UI must always
/// pair this with a clear textual instruction rather than relying on landing
/// on the right screen.
Future<void> openHotspotOrWifiSettings() async {
  if (checkPlatform([TargetPlatform.android])) {
    try {
      await openHotspotSettingsAndroid();
      return;
    } catch (e) {
      _logger.warning('Failed to open Android hotspot settings', e);
    }
  }
  await SystemSettings.wifi();
}

/// Whether this platform could ever support automatically joining a Wi-Fi network by
/// SSID/passphrase from app code. Only `WifiNetworkSpecifier` on Android (API 29+, checked
/// again at the native layer) can do this without sending the user to system Settings; iOS
/// has no equivalent public API.
bool get canAutoJoinWifi => checkPlatform([TargetPlatform.android]);

/// Tries to automatically join the Wi-Fi network described by [ssid]/[passphrase] (see
/// [joinWifiNetworkAndroid]) and route this app's traffic through it.
///
/// Used on the *scanning* device of the Smart QR Code pairing feature when the scanned QR
/// code carries credentials for a hotspot the emitter just created (see
/// [QrPairingPayload.wifiSsid]/[QrPairingPayload.wifiPassphrase]). Never throws: on any
/// failure (unsupported platform, timeout, permission/config issue) this returns `false` so
/// the caller can silently fall back to attempting the connection over whatever network is
/// already active — the same behavior as before this capability existed, which still works
/// if the user already joined the hotspot by hand using the SSID/password shown next to the
/// QR code.
///
/// On success, the caller MUST call [unbindAutoJoinedWifiNetwork] once it no longer needs
/// this network (right after the pairing HTTP call completes), since the join binds the
/// *entire app process* to it until then.
Future<bool> tryAutoJoinWifiNetwork({required String ssid, required String? passphrase}) async {
  if (!canAutoJoinWifi) {
    return false;
  }
  try {
    return await joinWifiNetworkAndroid(ssid: ssid, passphrase: passphrase);
  } catch (e) {
    _logger.warning('Failed to auto-join Wi-Fi network', e);
    return false;
  }
}

/// Releases whatever [tryAutoJoinWifiNetwork] set up (network request + process binding).
/// Safe to call unconditionally, even if no join was ever attempted.
Future<void> unbindAutoJoinedWifiNetwork() async {
  if (!canAutoJoinWifi) {
    return;
  }
  try {
    await unbindWifiNetworkAndroid();
  } catch (e) {
    _logger.warning('Failed to unbind auto-joined Wi-Fi network', e);
  }
}
