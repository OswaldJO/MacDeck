import Foundation

/// PIN shown on the Mac and typed on the phone—bridges UI to Apollo/Sunshine pairing APIs.
struct PINPairingChallenge: Equatable, Sendable {
    var pin: String
    var expiresAt: Date
}

/// After the phone completes pairing against the host, store a stable label for UI.
struct PairedClientIdentity: Equatable, Sendable {
    var displayName: String
}
