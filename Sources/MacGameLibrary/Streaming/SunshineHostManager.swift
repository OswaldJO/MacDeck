import Foundation

/// Starts and stops a Playnite-managed Sunshine process using an isolated config directory.
@MainActor
@Observable
final class SunshineHostManager {
    static let shared = SunshineHostManager()

    enum HostState: Equatable {
        case idle
        case preparing
        case starting
        case running
        case unavailable(String)
    }

    private(set) var state: HostState = .idle
    private var managedProcess: Process?
    private var ownsManagedProcess = false

    private init() {}

    var statusLine: String {
        switch state {
        case .idle:
            return "Streaming host is idle."
        case .preparing:
            return "Preparing Sunshine…"
        case .starting:
            return "Starting Sunshine…"
        case .running:
            return "Sunshine is running."
        case .unavailable(let message):
            return message
        }
    }

    /// Ensures Sunshine is configured and responding on the control plane.
    func ensureReady(controlPlane: any StreamingControlPlaneClient = SunshineControlPlaneClient()) async {
        state = .preparing
        do {
            try SunshineBootstrap.prepareEnvironment()
            try await SunshineBootstrap.syncCredentialsToSunshine()
        } catch {
            state = .unavailable(error.localizedDescription)
            return
        }

        if await controlPlaneResponds(controlPlane) {
            state = .running
            return
        }

        state = .starting
        do {
            try await launchManagedSunshine()
            let ready = await waitForControlPlane(controlPlane, timeout: 25)
            if ready {
                state = .running
            } else {
                stopManagedProcess()
                state = .unavailable(
                    "Sunshine did not become reachable on port \(ControlPlanePorts.webUIHTTPS). Check firewall settings."
                )
            }
        } catch {
            state = .unavailable(error.localizedDescription)
        }
    }

    func stopManagedProcess() {
        guard ownsManagedProcess, let managedProcess else { return }
        if managedProcess.isRunning {
            managedProcess.terminate()
        }
        self.managedProcess = nil
        ownsManagedProcess = false
        if case .running = state {
            state = .idle
        }
    }

    private func controlPlaneResponds(_ client: any StreamingControlPlaneClient) async -> Bool {
        guard StreamingHostSettings.hasCredentials else { return false }
        return (try? await client.ping()) == true
    }

    private func launchManagedSunshine() async throws {
        if ownsManagedProcess, managedProcess?.isRunning == true {
            return
        }

        let binary = try SunshineBinaryLocator.locate()
        let process = Process()
        process.executableURL = binary
        process.arguments = [SunshinePaths.configFile.path]
        process.currentDirectoryURL = SunshinePaths.configDirectory

        let stderr = Pipe()
        process.standardOutput = Pipe()
        process.standardError = stderr

        try process.run()
        managedProcess = process
        ownsManagedProcess = true
    }

    private func waitForControlPlane(
        _ client: any StreamingControlPlaneClient,
        timeout: TimeInterval
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if Task.isCancelled { return false }
            if await controlPlaneResponds(client) {
                return true
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        return false
    }
}
