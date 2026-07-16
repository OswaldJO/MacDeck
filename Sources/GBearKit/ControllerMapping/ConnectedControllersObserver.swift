import GameController
import Foundation

@Observable
final class ConnectedControllersObserver: @unchecked Sendable {
    private(set) var controllers: [GCController] = []
    private var connectObserver: NSObjectProtocol?
    private var disconnectObserver: NSObjectProtocol?

    init() {
        connectObserver = NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
        disconnectObserver = NotificationCenter.default.addObserver(
            forName: .GCControllerDidDisconnect,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
        refresh()
    }

    deinit {
        if let connectObserver {
            NotificationCenter.default.removeObserver(connectObserver)
        }
        if let disconnectObserver {
            NotificationCenter.default.removeObserver(disconnectObserver)
        }
    }

    func refresh() {
        controllers = GCController.controllers()
    }

    func displayName(for controller: GCController) -> String {
        if let name = controller.vendorName, !name.isEmpty {
            return name
        }
        return "Controller"
    }
}
