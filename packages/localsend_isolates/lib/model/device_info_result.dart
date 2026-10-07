import 'package:localsend_isolates/model/device.dart';

class DeviceInfoResult {
  final DeviceType deviceType;
  final String? deviceModel;

  // Used to properly set Edge-to-Edge mode on Android
  // See https://github.com/flutter/flutter/issues/90098
  final int? androidSdkInt;

  /// This application's build number (Android versionCode, e.g. `18` for
  /// `1.1.4+18`), `null` when unknown. Shared with other Aika devices during
  /// a transfer as an informational "update available" hint only.
  final int? appBuild;

  DeviceInfoResult({
    required this.deviceType,
    required this.deviceModel,
    required this.androidSdkInt,
    this.appBuild,
  });
}
