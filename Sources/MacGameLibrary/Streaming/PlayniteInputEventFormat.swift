import Foundation

/// `PNI1` touch / pointer events from the companion (normalized 0…65535).
enum PlayniteInputEventFormat {
    static let packetSize = 13

    enum EventType: UInt8 {
        case move = 0
        case down = 1
        case up = 2
        case scroll = 3
    }

    struct Event: Sendable {
        let type: EventType
        let button: UInt8
        let x: UInt16
        let y: UInt16
        let scrollDelta: Int16
    }

    static func parse(_ data: Data) -> Event? {
        guard data.count >= packetSize else { return nil }
        let magic = data.withUnsafeBytes { $0.load(as: UInt32.self) }.littleEndian
        guard magic == PlayniteStreamPorts.inputMagic else { return nil }
        let typeRaw = data[4]
        guard let type = EventType(rawValue: typeRaw) else { return nil }
        let button = data[5]
        let x = data.subdata(in: 6 ..< 8).withUnsafeBytes { $0.load(as: UInt16.self) }.littleEndian
        let y = data.subdata(in: 8 ..< 10).withUnsafeBytes { $0.load(as: UInt16.self) }.littleEndian
        let scroll = data.subdata(in: 10 ..< 12).withUnsafeBytes { $0.load(as: Int16.self) }.littleEndian
        return Event(type: type, button: button, x: x, y: y, scrollDelta: scroll)
    }
}
