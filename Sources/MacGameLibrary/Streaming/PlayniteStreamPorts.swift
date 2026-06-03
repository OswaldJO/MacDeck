import Foundation

/// Playnite-native streaming (no Sunshine/Moonlight ports).
enum PlayniteStreamPorts {
    /// HTTP control plane: status, pairing, session.
    static let controlHTTP: UInt16 = 28765
    /// Raw H.264 over TCP (`PNV1` framed packets).
    static let videoTCP: UInt16 = 28766
    /// PCM audio over UDP (`PNA1` framed packets). Phone sends `PNAS` subscribe first.
    static let audioUDP: UInt16 = 28767
    /// Touch / pointer events from phone over UDP (`PNI1` packets).
    static let inputUDP: UInt16 = 28768
    static let protocolVersion = "playnite-stream/1"
    static let videoMagic: UInt32 = 0x3156_4E50 // "PNV1" little-endian
    static let audioMagic: UInt32 = 0x3141_4E50 // "PNA1" little-endian
    static let audioSubscribeMagic: UInt32 = 0x5341_4E50 // "PNAS" little-endian
    static let inputMagic: UInt32 = 0x3149_4E50 // "PNI1" little-endian
}
