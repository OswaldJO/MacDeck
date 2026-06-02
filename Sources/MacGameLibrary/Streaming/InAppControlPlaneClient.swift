import Foundation

/// Calls the Sunshine host HTTPS control plane from native code (no Safari).
protocol StreamingControlPlaneClient: Sendable {
    func ping() async throws -> Bool
    func submitPairingPIN(_ pin: String, deviceName: String) async throws
    func fetchPairedClientNames() async throws -> [String]
}

extension StreamingControlPlaneClient {
    func submitPairingPIN(_ pin: String) async throws {
        try await submitPairingPIN(pin, deviceName: "Companion")
    }
}

enum StreamingControlPlaneError: Error, LocalizedError {
    case notImplemented
    case hostUnreachable
    case pairingFailed(String)
    case missingCredentials

    var errorDescription: String? {
        switch self {
        case .notImplemented:
            return "Control plane client not configured."
        case .hostUnreachable:
            return "Sunshine is not running or not reachable on the control plane port (default 47990)."
        case .pairingFailed(let detail):
            return detail
        case .missingCredentials:
            return "Streaming host credentials are not ready yet. Open the Streaming tab to set up Sunshine."
        }
    }
}
