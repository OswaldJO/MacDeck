import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let channelName = "com.playnite.companion/streaming_bridge"
  private var streamingChannelRegistered = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(playniteStreamDidEnd),
      name: NSNotification.Name("PlayniteMoonlightStreamDidEndNotification"),
      object: nil
    )

    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    registerStreamingChannelIfNeeded()
    return result
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    registerStreamingChannelIfNeeded()
  }

  private func registerStreamingChannelIfNeeded() {
    guard !streamingChannelRegistered else { return }
    guard let controller = window?.rootViewController as? FlutterViewController else { return }
    streamingChannelRegistered = true

    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: controller.binaryMessenger)
    channel.setMethodCallHandler { [weak controller] call, result in
      switch call.method {
      case "discoverHosts":
        result([])

      case "pairWithPin":
        if let args = call.arguments as? [String: Any], let pin = args["pin"] as? String {
          result(pin.count >= 4)
        } else {
          result(false)
        }

      case "startStream":
        guard let controller else {
          result(FlutterError(code: "no_controller", message: "Missing root view controller", details: nil))
          return
        }
        guard let args = call.arguments as? [String: Any] else {
          result(FlutterError(code: "invalid_args", message: "Missing stream configuration", details: nil))
          return
        }
        let started = PlayniteStreamLaunchHelper.startStream(
          from: controller,
          arguments: args
        )
        if started {
          result(true)
        } else {
          result(
            FlutterError(
              code: "stream_start_failed",
              message: PlayniteStreamLaunchHelper.lastStreamStartErrorMessage()
                ?? "Native stream failed to start",
              details: nil
            )
          )
        }

      case "stopStream":
        PlayniteStreamLaunchHelper.stopStream()
        result(nil)

      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  @objc private func playniteStreamDidEnd() {
    // Reserved for future cleanup hooks.
  }
}
