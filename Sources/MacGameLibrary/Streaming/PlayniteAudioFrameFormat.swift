import Foundation

/// `PNA1` length-prefixed PCM for the phone speaker (s16le interleaved).
enum PlayniteAudioFrameFormat {
    static let headerSize = 9

    static func pack(payload: Data, sampleRate: UInt16, channels: UInt8) -> Data {
        var packet = Data(capacity: headerSize + payload.count)
        var magic = PlayniteStreamPorts.audioMagic.littleEndian
        var length = UInt32(payload.count).littleEndian
        var rate = sampleRate.littleEndian
        var ch = channels
        withUnsafeBytes(of: &magic) { packet.append(contentsOf: $0) }
        withUnsafeBytes(of: &length) { packet.append(contentsOf: $0) }
        withUnsafeBytes(of: &rate) { packet.append(contentsOf: $0) }
        withUnsafeBytes(of: &ch) { packet.append(contentsOf: $0) }
        packet.append(payload)
        return packet
    }
}
