import Foundation

/// UI state for PIN pairing; later: forward `pin` to `StreamingControlPlaneClient` + Apollo.
@Observable
final class StreamingPairingSession {
    enum Phase: Equatable {
        case idle
        case awaiting(code: String, expiresAt: Date)
        case paired(deviceName: String)
    }

    var phase: Phase = .idle

    private let pairingCodeLifetime: TimeInterval = 10 * 60

    init() {}

    func startPairing() {
        let code = String(format: "%06d", Int.random(in: 0..<1_000_000))
        phase = .awaiting(code: code, expiresAt: Date().addingTimeInterval(pairingCodeLifetime))
    }

    func cancelPairing() {
        phase = .idle
    }

    func markPaired(deviceName: String) {
        let trimmed = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        phase = .paired(deviceName: trimmed.isEmpty ? "Phone" : trimmed)
    }

    func disconnect() {
        phase = .idle
    }
}
