import Foundation

/// PIN shown on the phone and confirmed on the Mac for Playnite native pairing.
struct PINPairingChallenge: Equatable, Sendable {
    var pin: String
    var expiresAt: Date
}

/// After the phone completes pairing against the host, store a stable label for UI.
struct PairedClientIdentity: Equatable, Sendable {
    var displayName: String
}
