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

    private init() {}

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
        case .idle: return "Streaming host is idle."
        case .preparing: return "Starting Playnite stream host…"
        case .running: return "Playnite stream host is running."
        case .unavailable(let message): return message
        }
    }

    func refreshCapturePermission() async {
        await capture.refresh()
        await server.setCaptureReady(capture.isReady)
    }

    func ensureReady() async {
        state = .preparing
        await refreshCapturePermission()
        await wireStreamCallbacks()
        await wirePairingCallbacks()

        do {
            try await server.start()
            try await video.startListener()
            try await audio.startListener()
            try await input.startListener()
            AccessibilityPermission.promptIfNeeded()
            state = .running
            await refreshPendingPairRequests()
            startPendingPoll()
        } catch {
            state = .unavailable("Could not start Playnite stream host: \(error.localizedDescription)")
        }
    }

    func restartHost() async {
        stopPendingPoll()
        await video.stop()
        await audio.stop()
        await input.stop()
        await server.stop()
        state = .idle
        isVideoStreaming = false
        await ensureReady()
    }

    func stop() async {
        stopPendingPoll()
        await video.stop()
        await audio.stop()
        await input.stop()
        await server.stop()
        state = .idle
        isVideoStreaming = false
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

    func beginVideoStream(width: Int, height: Int, fps: Int) async {
        if !capture.isReady {
            guard await capture.requestSystemPrompt() else { return }
            await server.setCaptureReady(capture.isReady)
            guard capture.isReady else { return }
        }
        let audioServer = audio
        do {
            try await video.startStream(width: width, height: height, fps: fps) { pcm, sampleRate, channels in
                Task { await audioServer.sendPCM(pcm, sampleRate: sampleRate, channels: channels) }
            }
            isVideoStreaming = true
        } catch {
            isVideoStreaming = false
        }
    }

    private func endVideoStream() async {
        await video.stopStream()
        isVideoStreaming = false
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
