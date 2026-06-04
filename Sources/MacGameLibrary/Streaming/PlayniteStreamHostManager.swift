import Foundation

/// Native Playnite streaming host (in-app capture + HTTP control + H.264 video).
@MainActor
@Observable
final class PlayniteStreamHostManager {
    static let shared = PlayniteStreamHostManager()

    enum HostState: Equatable {
        case idle
        case preparing
        case running
        case unavailable(String)
    }

    private(set) var state: HostState = .idle
    private(set) var pendingPairRequests: [PlayniteStreamControlServer.PendingPairRequest] = []
    private(set) var isVideoStreaming = false

    private let server = PlayniteStreamControlServer()
    private let video = PlayniteVideoStreamServer()
    private let audio = PlayniteAudioStreamServer()
    private let input = PlayniteStreamInputServer()
    private let capture = PlayniteScreenCapturePipeline()
    private var pendingPollTask: Task<Void, Never>?
    private var captureTask: Task<Void, Never>?
    private var streamOperationChain: Task<Void, Never>?
    private var lastStreamStartSucceeded = false

    private init() {
        PlayniteLocalOutputMute.setStreamingMuted(false)
    }

    var isCaptureReady: Bool {
        capture.isReady
    }

    /// Show the Allow button only when capture is not ready and we still need TCC consent.
    var needsScreenCaptureConsent: Bool {
        !capture.isReady && !capture.hasSystemAuthorization
    }

    var captureGuidance: String? {
        guard let err = capture.lastError else { return nil }
        if needsScreenCaptureConsent {
            return "\(err) Tap Allow Screen Recording below for the system prompt."
        }
        return "\(err) Restart the streaming host after changing Screen Recording."
    }

    /// Shows the macOS Screen Recording consent dialog (not Settings). No-op if already granted.
    func requestScreenCaptureAccess() async -> Bool {
        let granted = await capture.requestSystemPrompt()
        await server.setCaptureReady(capture.isReady)
        return granted
    }

    var statusLine: String {
        switch state {
        case .idle: return "Pairing host is idle."
        case .preparing: return "Starting pairing host…"
        case .running:
            if isVideoStreaming {
                return "Streaming desktop to the companion."
            }
            return "Ready for pairing — capture starts when the companion starts a stream."
        case .unavailable(let message): return message
        }
    }

    func refreshCapturePermission() async {
        await capture.refresh()
        await server.setCaptureReady(capture.isReady)
    }

    /// Starts HTTP control (pairing/discovery) only. Video/audio/input transport and capture begin on companion `stream/start`.
    func ensureReady() async {
        state = .preparing
        PlayniteLocalOutputMute.setStreamingMuted(false)
        await refreshCapturePermission()
        await wireStreamCallbacks()
        await wirePairingCallbacks()

        do {
            try await server.start()
            AccessibilityPermission.promptIfNeeded()
            state = .running
            await refreshPendingPairRequests()
            startPendingPoll()
        } catch {
            state = .unavailable("Could not start Playnite pairing host: \(error.localizedDescription)")
        }
    }

    /// Ends an active companion stream (e.g. after the phone force-quit without Stop).
    func stopActiveVideoStream() async {
        await endVideoStream()
    }

    func restartHost() async {
        stopPendingPoll()
        await endVideoStream()
        await server.stop()
        state = .idle
        await ensureReady()
    }

    func stop() async {
        stopPendingPoll()
        await endVideoStream()
        await server.stop()
        PlayniteLocalOutputMute.setStreamingMuted(false)
        state = .idle
        pendingPairRequests = []
    }

    func startWatchingPairingRequests() {
        startPendingPoll()
    }

    func stopWatchingPairingRequests() {
        stopPendingPoll()
    }

    func approvePairing(deviceID: String) async -> Bool {
        await server.approve(deviceID: deviceID)
    }

    func denyPairing(deviceID: String) async -> Bool {
        await server.deny(deviceID: deviceID)
    }

    func fetchPairedClientNames() async -> [String] {
        await server.pairedNames()
    }

    func ping() async -> Bool {
        await server.isListening
    }

    private func wireStreamCallbacks() async {
        await server.setStreamHandlers(
            onStart: { _, width, height, fps in
                await PlayniteStreamHostManager.shared.beginVideoStream(width: width, height: height, fps: fps)
            },
            onStop: {
                await PlayniteStreamHostManager.shared.endVideoStream()
            }
        )
    }

    private func wirePairingCallbacks() async {
        await server.setPairingQueueHandler { [weak self] in
            await self?.refreshPendingPairRequests()
        }
    }

    func refreshPendingPairRequests() async {
        pendingPairRequests = await server.pendingRequests()
    }

    @discardableResult
    func beginVideoStream(width: Int, height: Int, fps: Int) async -> Bool {
        await enqueueStreamOperation {
            self.lastStreamStartSucceeded = await self.beginVideoStreamUnlocked(
                width: width,
                height: height,
                fps: fps
            )
        }
        return lastStreamStartSucceeded
    }

    /// Runs [body] after any prior start/stop work finishes (@MainActor class — no Sendable generic needed).
    private func enqueueStreamOperation(_ body: @escaping @MainActor () async -> Void) async {
        let previous = streamOperationChain
        let task = Task { @MainActor in
            if let previous {
                await previous.value
            }
            await body()
        }
        streamOperationChain = task
        await task.value
    }

    @discardableResult
    private func beginVideoStreamUnlocked(width: Int, height: Int, fps: Int) async -> Bool {
        // Always tear down prior transport/capture so a second session works after app kill or failed connect.
        await endVideoStreamUnlocked()
        if !capture.isReady {
            guard await capture.requestSystemPrompt() else { return false }
            await server.setCaptureReady(capture.isReady)
            guard capture.isReady else { return false }
        }
        do {
            PlayniteKeyboardPlayback.resetModifierState()
            try await startStreamTransport()
            isVideoStreaming = true
            await server.setVideoStreaming(true)
            PlayniteLocalOutputMute.setStreamingMuted(true)
            print("[PlayniteStream] transport ready for companion (starting capture…)")
            let audioServer = audio
            captureTask?.cancel()
            captureTask = Task { @MainActor in
                do {
                    try await video.startCapture(width: width, height: height, fps: fps) { pcm, sampleRate, channels in
                        Task { await audioServer.sendPCM(pcm, sampleRate: sampleRate, channels: channels) }
                    }
                    print("[PlayniteStream] companion stream \(width)x\(height) @ \(fps)fps")
                } catch {
                    if !Task.isCancelled {
                        print("[PlayniteStream] capture start failed: \(error.localizedDescription)")
                        await self.endVideoStreamUnlocked()
                    }
                }
            }
            return true
        } catch {
            await stopStreamTransport()
            PlayniteLocalOutputMute.setStreamingMuted(false)
            isVideoStreaming = false
            await server.setVideoStreaming(false)
            print("[PlayniteStream] stream start failed: \(error.localizedDescription)")
            return false
        }
    }

    private func endVideoStream() async {
        await enqueueStreamOperation {
            await self.endVideoStreamUnlocked()
        }
    }

    private func endVideoStreamUnlocked() async {
        captureTask?.cancel()
        captureTask = nil
        isVideoStreaming = false
        await server.setVideoStreaming(false)
        PlayniteKeyboardPlayback.resetModifierState()
        PlayniteLocalOutputMute.setStreamingMuted(false)
        await video.stopStream()
        await stopListeners()
        print("[PlayniteStream] stream ended")
    }

    private func startStreamTransport() async throws {
        try await video.startListener()
        try await audio.startListener()
        try await audio.startTCPListener()
        try await input.startListener()
    }

    private func stopListeners() async {
        await video.stopListener()
        await audio.stop()
        await input.stop()
    }

    private func stopStreamTransport() async {
        await video.stopStream()
        await stopListeners()
    }

    private func startPendingPoll() {
        pendingPollTask?.cancel()
        pendingPollTask = Task { @MainActor in
            while !Task.isCancelled {
                if case .running = state {
                    await refreshPendingPairRequests()
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }

    private func stopPendingPoll() {
        pendingPollTask?.cancel()
        pendingPollTask = nil
    }
}
