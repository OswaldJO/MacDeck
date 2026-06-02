import Foundation

/// Default ports for Sunshine-class hosts (Apollo inherits this model).
/// Web UI / HTTPS API: see LizardByte Sunshine docs; pairing and settings use this server.
/// Video/streaming use separate ports—only control plane is routed through `InAppControlPlaneClient`.
enum ControlPlanePorts {
    /// Moonlight HTTP pairing / serverinfo (companion discovery).
    static let moonlightHTTP: UInt16 = 47989
    /// HTTPS web UI + REST (same surface area Safari would use; we call it from the app instead).
    static let webUIHTTPS: UInt16 = 47990
}

extension URL {
    /// Loopback control plane base (host must be running, e.g. bundled Apollo).
    static func localhostControlPlane(port: UInt16 = ControlPlanePorts.webUIHTTPS) -> URL {
        URL(string: "https://127.0.0.1:\(port)")!
    }
}
