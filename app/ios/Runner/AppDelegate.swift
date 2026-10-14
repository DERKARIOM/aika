import UIKit
import Flutter

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    let channel = FlutterMethodChannel(
        name: "ios-delegate-channel",
        binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
        if call.method == "isReduceMotionEnabled" {
          result(UIAccessibility.isReduceMotionEnabled)
        } else if call.method == "getStorageInfo" {
          // Storage card of the "Recevoir" page: the volume holding the app's
          // data, with the space iOS really leaves to apps ("important usage").
          let url = URL(fileURLWithPath: NSHomeDirectory())
          let values = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
          ])
          if let free = values?.volumeAvailableCapacityForImportantUsage {
            var info: [String: Any] = ["free": Int(free)]
            if let total = values?.volumeTotalCapacity {
              info["total"] = total
            }
            result(info)
          } else {
            result(nil)
          }
        } else {
          result(FlutterMethodNotImplemented)
        }
    }
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
