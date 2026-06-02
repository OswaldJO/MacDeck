import Foundation

/// Pairing with Sunshine: companion shows a 4-digit PIN; Mac submits it via `/api/pin` and polls paired clients.
@MainActor
@Observable
final class StreamingPairingSession {
    enum Phase: Equatable {
        case idle
        case awaiting(expiresAt: Date)
        case paired(deviceName: String)
    }

    enum PinSubmitState: Equatable {
        case idle
        case submitting
        case accepted
        case failed(String)
    }

    var phase: Phase = .idle
    var hostReachable = false
    var statusMessage = ""
    var lastError: String?
    var pinSubmitState: PinSubmitState = .idle

    private let pairingLifetime: TimeInterval = 10 * 60
    private let controlPlane: any StreamingControlPlaneClient
    private let hostManager: SunshineHostManager
    private var pollTask: Task<Void, Never>?
    private var baselineClientNames: [String] = []

    init(
        controlPlane: any StreamingControlPlaneClient = SunshineControlPlaneClient(),
        hostManager: SunshineHostManager = .shared
    ) {
        self.controlPlane = controlPlane
        self.hostManager = hostManager
    }

    func refreshHostStatus() {
        Task { @MainActor in
            await hostManager.ensureReady(controlPlane: controlPlane)
            guard StreamingHostSettings.hasCredentials else {
                hostReachable = false
                statusMessage = hostManager.statusLine
                return
            }
            do {
                hostReachable = try await controlPlane.ping()
                statusMessage = hostReachable
                    ? "Sunshine control plane is reachable."
                    : hostManager.statusLine
            } catch {
                hostReachable = false
                statusMessage = error.localizedDescription
            }
        }
    }

    func startPairing() {
        cancelPairing()
        lastError = nil
        pinSubmitState = .idle
        phase = .awaiting(expiresAt: Date().addingTimeInterval(pairingLifetime))
        statusMessage = "On your phone: companion → Pairing → Start pairing. Wait until it says “Waiting for Mac…”, then enter the PIN here."

        Task { @MainActor in
            await hostManager.ensureReady(controlPlane: controlPlane)
        }

        pollTask = Task { @MainActor in
            do {
                baselineClientNames = try await controlPlane.fetchPairedClientNames()
            } catch {
                baselineClientNames = []
            }
            while !Task.isCancelled {
                guard case .awaiting = phase else { break }
                if Date() >= expiresAt {
                    cancelPairing()
                    statusMessage = "Pairing timed out."
                    break
                }
                await pollForNewClient()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func submitPIN(_ pin: String, deviceName: String) {
        let trimmed = pin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 4, trimmed.allSatisfy(\.isNumber) else {
            pinSubmitState = .failed("PIN must be exactly 4 digits.")
            return
        }
        guard StreamingHostSettings.hasCredentials else {
            pinSubmitState = .failed(StreamingControlPlaneError.missingCredentials.localizedDescription)
            return
        }
        guard pinSubmitState != .submitting else { return }

        pinSubmitState = .submitting
        statusMessage = "Submitting PIN to Sunshine…"

        Task { @MainActor in
            await hostManager.ensureReady(controlPlane: controlPlane)
            do {
                try await controlPlane.submitPairingPIN(trimmed, deviceName: deviceName)
                pinSubmitState = .accepted
                statusMessage = "PIN accepted. Waiting for the phone to finish pairing…"
                await pollForNewClient()
            } catch {
                pinSubmitState = .failed(error.localizedDescription)
                statusMessage = "PIN submit failed."
            }
        }
    }

    func cancelPairing() {
        pollTask?.cancel()
        pollTask = nil
        phase = .idle
        statusMessage = ""
        lastError = nil
        pinSubmitState = .idle
    }

    func disconnect() {
        cancelPairing()
    }

    private var expiresAt: Date {
        if case .awaiting(let exp) = phase { return exp }
        return .distantPast
    }

    @MainActor
    private func pollForNewClient() async {
        guard StreamingHostSettings.hasCredentials else { return }
        do {
            let names = try await controlPlane.fetchPairedClientNames()
            if let newName = names.first(where: { !baselineClientNames.contains($0) }) {
                phase = .paired(deviceName: newName)
                pinSubmitState = .idle
                statusMessage = "Paired with \(newName)."
                pollTask?.cancel()
                pollTask = nil
            }
        } catch {
            // Keep polling; host may still be pairing.
        }
    }
}
