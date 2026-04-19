import Foundation

/// Calls the host’s HTTPS control plane from native code (no Safari).
/// Wire these methods to Apollo’s REST routes (same as the web dashboard). Use a
/// `URLSessionDelegate` to trust the host’s self-signed certificate after first pairing.
protocol StreamingControlPlaneClient: Sendable {
    /// Whether the control plane responds (host process up).
    func ping() async throws -> Bool

    /// Request or refresh pairing state; map responses to your fork’s actual JSON.
    func submitPairingPIN(_ pin: String) async throws
}

enum StreamingControlPlaneError: Error, LocalizedError {
    case notImplemented
    case hostUnreachable

    var errorDescription: String? {
        switch self {
        case .notImplemented:
            return "Control plane client not wired to Apollo yet."
        case .hostUnreachable:
            return "Streaming host is not running or not reachable on the control plane port."
        }
    }
}

/// Stub until `Vendor/streaming-repos/Apollo` is integrated and routes are mapped.
struct StubStreamingControlPlaneClient: StreamingControlPlaneClient {
    func ping() async throws -> Bool {
        throw StreamingControlPlaneError.notImplemented
    }

    func submitPairingPIN(_ pin: String) async throws {
        _ = pin
        throw StreamingControlPlaneError.notImplemented
    }
}
