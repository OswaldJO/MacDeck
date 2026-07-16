import Darwin
import Foundation

/// Receives `PNI1` touch packets from the phone and posts Mac pointer events.
actor PlayniteStreamInputServer {
    private var udp: PlayniteUDPSocket?
    private nonisolated(unsafe) static var packetsReceived = 0

    private nonisolated(unsafe) static var keyboardPacketsReceived = 0

    private nonisolated static func noteKeyboard(_ event: PlayniteKeyboardEventFormat.Event) {
        keyboardPacketsReceived += 1
        if keyboardPacketsReceived <= 8 || keyboardPacketsReceived % 20 == 0 {
            print(
                "[PlayniteInput] PNK1 #\(keyboardPacketsReceived) " +
                    "\(event.down ? "down" : "up") key=0x\(String(event.moonlightKeyCode, radix: 16))"
            )
        }
    }

    private nonisolated static func noteReceived(_ event: PlayniteInputEventFormat.Event) {
        packetsReceived += 1
        if packetsReceived == 1 || packetsReceived % 100 == 0 {
            print(
                "[PlayniteInput] packet #\(packetsReceived) type=\(event.type) " +
                    "x=\(event.x) y=\(event.y)"
            )
        }
    }

    func startListener(port: UInt16 = PlayniteStreamPorts.inputUDP) async throws {
        if udp != nil { return }
        let socket = PlayniteUDPSocket()
        socket.onDatagram = { (data: Data, _: sockaddr_storage, _: socklen_t) in
            if let keyboard = PlayniteKeyboardEventFormat.parse(data) {
                PlayniteStreamInputServer.noteKeyboard(keyboard)
                PlayniteKeyboardPlayback.handle(keyboard)
                return
            }
            guard let event = PlayniteInputEventFormat.parse(data) else { return }
            PlayniteStreamInputServer.noteReceived(event)
            PlayniteRemoteInputPlayback.handle(event)
        }
        try socket.start(port: port)
        udp = socket
    }

    func stop() async {
        udp?.stop()
        udp = nil
    }
}
