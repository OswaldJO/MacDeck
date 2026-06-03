import Flutter
import GameController
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let channelName = "com.playnite.companion/streaming_bridge"
  private var streamingChannelRegistered = false
  private var videoController: PlayniteVideoViewController?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
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
    channel.setMethodCallHandler { [weak self, weak controller] call, result in
      switch call.method {
      case "discoverHosts":
        result([])

      case "pairWithPin":
        result(true)

      case "startStream":
        guard let controller else {
          result(FlutterError(code: "no_controller", message: "Missing root view controller", details: nil))
          return
        }
        guard let args = call.arguments as? [String: Any],
              let host = args["host"] as? String,
              let port = args["videoPort"] as? Int else {
          result(FlutterError(code: "invalid_args", message: "Missing stream configuration", details: nil))
          return
        }
        let player = PlayniteVideoViewController(host: host, port: UInt16(port))
        player.modalPresentationStyle = .fullScreen
        controller.present(player, animated: true)
        self?.videoController = player
        result(true)

      case "stopStream":
        self?.videoController?.dismiss(animated: true)
        self?.videoController = nil
        result(nil)

      case "listConnectedControllers":
        result(Self.listConnectedControllers())

      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func listConnectedControllers() -> [[String: Any]] {
    GCController.startWirelessControllerDiscovery(completionHandler: {})
    return GCController.controllers().map { controller in
      let name = controller.vendorName?.trimmingCharacters(in: .whitespacesAndNewlines)
      let displayName = (name?.isEmpty == false) ? name! : "Game Controller"
      var entry: [String: Any] = [
        "id": controller.playerIndex.rawValue.description,
        "name": displayName,
      ]
      if #available(iOS 13.0, *) {
        entry["vendor"] = controller.productCategory
      } else {
        entry["vendor"] = "gamepad"
      }
      return entry
    }
  }
}
