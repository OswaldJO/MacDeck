import Foundation
import Network

/// Broadcasts `PNV1` H.264 frames to one connected phone client.
actor PlayniteVideoStreamServer {
    private var listener: NWListener?
    private var client: NWConnection?
    private var capture: PlayniteDisplayCapture?

    var isStreaming: Bool { capture != nil }

    func startListener(port: UInt16 = PlayniteStreamPorts.videoTCP) async throws {
        if listener != nil { return }
        let nwPort = NWEndpoint.Port(rawValue: port)!
        let listener = try NWListener(using: .tcp, on: nwPort)
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            Task { await self.accept(connection: connection) }
        }
        listener.start(queue: .global(qos: .userInitiated))
        self.listener = listener
    }

    func startStream(
        width: Int,
        height: Int,
        fps: Int,
        audioHandler: PlayniteDisplayCapture.AudioHandler? = nil
    ) async throws {
        if capture != nil { return }
        try await startListener()

        let capture = PlayniteDisplayCapture(
            encodedHandler: { [weak self] data, isKeyframe, w, h in
                guard let self else { return }
                Task { await self.sendFrame(data: data, isKeyframe: isKeyframe, width: w, height: h) }
            },
            audioHandler: audioHandler
        )
        try await capture.start(width: width, height: height, fps: fps)
        self.capture = capture
    }

    func stopStream() async {
        if let capture {
            await capture.stop()
        }
        capture = nil
        client?.cancel()
        client = nil
    }

    func stop() async {
        await stopStream()
        listener?.cancel()
        listener = nil
    }

    private var framesSent = 0
    private var waitingForKeyframe = false
    private struct PendingPacket {
        let data: Data
        let isKeyframe: Bool
        let width: UInt16
        let height: UInt16
        let payloadBytes: Int
    }

    private var sendInFlight = false
    private var pendingPackets: [PendingPacket] = []
    private let maxQueuedPackets = 45

    private func accept(connection: NWConnection) {
        client?.cancel()
        client = connection
        framesSent = 0
        waitingForKeyframe = true
        sendInFlight = false
        pendingPackets.removeAll()

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            Task { await self.handleConnectionState(state) }
        }

        connection.start(queue: .global(qos: .userInitiated))
        print("[PlayniteVideo] phone connected to TCP video port; requesting keyframe with SPS/PPS")
        capture?.requestKeyframe()
    }

    private func handleConnectionState(_ state: NWConnection.State) {
        switch state {
        case .ready:
            break
        case .failed(let error):
            print("[PlayniteVideo] client connection failed: \(error.localizedDescription)")
            dropClient()
        case .cancelled:
            print("[PlayniteVideo] client disconnected")
            dropClient()
        default:
            break
        }
    }

    private func dropClient() {
        client = nil
        sendInFlight = false
        pendingPackets.removeAll()
        waitingForKeyframe = true
    }

    private func sendFrame(data: Data, isKeyframe: Bool, width: UInt16, height: UInt16) {
        guard client != nil else { return }
        if waitingForKeyframe {
            guard isKeyframe else { return }
            waitingForKeyframe = false
        }
        let packet = PlayniteVideoFrameFormat.pack(payload: data, width: width, height: height, isKeyframe: isKeyframe)
        pendingPackets.append(
            PendingPacket(
                data: packet,
                isKeyframe: isKeyframe,
                width: width,
                height: height,
                payloadBytes: data.count
            )
        )
        if pendingPackets.count > maxQueuedPackets {
            let dropped = pendingPackets.count - maxQueuedPackets
            pendingPackets.removeFirst(dropped)
            if framesSent == 0 || framesSent % 60 == 0 {
                print("[PlayniteVideo] dropped \(dropped) queued frame(s); client not keeping up")
            }
        }
        flushPendingSends()
    }

    private func flushPendingSends() {
        guard let client, !sendInFlight, !pendingPackets.isEmpty else { return }

        let packet = pendingPackets.removeFirst()
        sendInFlight = true
        client.send(content: packet.data, completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            Task { await self.completeSend(sent: packet, error: error) }
        })
    }

    private func completeSend(sent: PendingPacket, error: NWError?) {
        sendInFlight = false
        if let error {
            print("[PlayniteVideo] send failed: \(error.localizedDescription)")
            dropClient()
            return
        }

        framesSent += 1
        if framesSent == 1 || framesSent % 60 == 0 {
            print(
                "[PlayniteVideo] sent frame #\(framesSent) keyframe=\(sent.isKeyframe) " +
                    "bytes=\(sent.payloadBytes) \(sent.width)x\(sent.height) " +
                    "queued=\(pendingPackets.count)"
            )
        }
        flushPendingSends()
    }
}
