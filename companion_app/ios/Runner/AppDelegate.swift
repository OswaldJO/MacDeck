import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let channelName = "com.playnite.companion/streaming_bridge"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(name: channelName, binaryMessenger: controller.binaryMessenger)
      channel.setMethodCallHandler { call, result in
        switch call.method {
        case "discoverHosts":
          result([])
        case "pairWithPin":
          if
            let args = call.arguments as? [String: Any],
            let pin = args["pin"] as? String
          {
            result(pin.count >= 4)
          } else {
            result(false)
          }
            if let args = call.arguments as? [String: Any] {
              result(FlutterError(
                code: "ios_stream_unavailable",
                message: "Native Moonlight streaming on iOS requires moonlight-ios integration. Use Android for Desktop stream today.",
                details: nil
              ))
            } else {
              result(FlutterError(code: "invalid_args", message: "Missing stream configuration", details: nil))
            }
        case "stopStream":
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
