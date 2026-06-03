import AppKit
import SwiftUI

struct StreamingView: View {
    @State private var session: StreamingPairingSession
    @State private var hostManager = PlayniteStreamHostManager.shared
    @State private var confirmDisconnect = false

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(session: StreamingPairingSession = StreamingPairingSession()) {
        _session = State(initialValue: session)
    }

    var body: some View {
        NavigationStack {
            Form {
                heroSection
                streamHostSection
                pairingRequestsSection

                if case .paired(let deviceName) = session.phase {
                    pairedSections(deviceName: deviceName)
                }

                accessibilitySection
                capabilitiesSection
            }
            .formStyle(.grouped)
            .navigationTitle("Streaming")
        }
        .padding()
        .frame(minWidth: 520, minHeight: 520)
        .onAppear {
            Task {
                await hostManager.ensureReady()
                await hostManager.refreshPendingPairRequests()
                session.refreshHostStatus()
                session.beginListeningForRequests()
            }
        }
        .onDisappear {
            session.stopListeningForRequests()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task {
                await hostManager.refreshCapturePermission()
                session.refreshHostStatus()
            }
        }
        .confirmationDialog(
            "Disconnect “\(pairedNameForDialog)” from streaming on this Mac?",
            isPresented: $confirmDisconnect,
            titleVisibility: .visible
        ) {
            Button("Disconnect", role: .destructive) {
                session.disconnect()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var pairedNameForDialog: String {
        if case .paired(let name) = session.phase { return name }
        return ""
    }

    private var heroSection: some View {
        Section {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "iphone.gen3.radiowaves.right")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                    .symbolRenderingMode(.hierarchical)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Stream to your phone")
                        .font(.headline)
                    Text(
                        "On the companion app: Discover your Mac, then tap Pair. Approve or deny the request here — no PINs. Grant Screen Recording for Mac Game Library once."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var streamHostSection: some View {
        Section("Streaming host") {
            hostStateRow
            if let lanIP = LocalNetworkAddress.primaryIPv4() {
                LabeledContent("LAN IP (enter in companion Settings)") {
                    Text(lanIP)
                        .textSelection(.enabled)
                }
            }
            LabeledContent("Protocol") {
                Text(PlayniteStreamPorts.protocolVersion)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Ports") {
                Text(
                    "control \(PlayniteStreamPorts.controlHTTP), video \(PlayniteStreamPorts.videoTCP), " +
                        "audio \(PlayniteStreamPorts.audioUDP), input \(PlayniteStreamPorts.inputUDP)"
                )
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            }
            if hostManager.isVideoStreaming {
                Label("Streaming video to phone", systemImage: "dot.radiowaves.left.and.right")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            screenRecordingPermissionBlock
            if let guidance = hostManager.captureGuidance {
                Text(guidance)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !session.statusMessage.isEmpty {
                Text(session.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let err = session.lastError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Button("Restart streaming host") {
                Task {
                    await hostManager.restartHost()
                    session.refreshHostStatus()
                }
            }
        }
    }

    @ViewBuilder
    private var pairingRequestsSection: some View {
        Section("Pairing requests") {
            if hostManager.pendingPairRequests.isEmpty {
                Text("No pending requests. Open the companion app, discover this Mac, and tap Pair.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(hostManager.pendingPairRequests) { request in
                    VStack(alignment: .leading, spacing: 10) {
                        Label {
                            Text("\(request.deviceName) is trying to pair")
                                .font(.headline)
                        } icon: {
                            Image(systemName: "iphone.gen3.circle")
                        }
                        Text("Device ID: \(request.deviceID)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.tertiary)
                            .textSelection(.enabled)
                        HStack {
                            Button("Deny", role: .destructive) {
                                session.deny(request)
                            }
                            Spacer()
                            Button("Pair") {
                                session.approve(request)
                            }
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.defaultAction)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }

    @ViewBuilder
    private var screenRecordingPermissionBlock: some View {
        if hostManager.isCaptureReady {
            Label("Screen Recording enabled for Mac Game Library", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        } else if case .running = hostManager.state {
            VStack(alignment: .leading, spacing: 8) {
                Label("Screen Recording required", systemImage: "rectangle.dashed.badge.record")
                    .font(.subheadline.weight(.medium))
                if hostManager.needsScreenCaptureConsent {
                    Text(
                        "Tap Allow below for the macOS permission prompt. You only need to do this once; pairing will not ask again after access is granted."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    Button {
                        Task {
                            _ = await hostManager.requestScreenCaptureAccess()
                            session.refreshHostStatus()
                        }
                    } label: {
                        Label("Allow Screen Recording", systemImage: "checkmark.shield")
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Text("Permission is on but capture is not ready. Restart the streaming host.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button("Open Screen Recording settings") {
                    PlayniteScreenCapturePipeline.openScreenRecordingSettings()
                }
                .font(.caption)
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var hostStateRow: some View {
        switch hostManager.state {
        case .running where session.hostReachable && hostManager.isCaptureReady:
            Label("Ready to pair and stream", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .running where session.hostReachable:
            Label("Host up — grant Screen Recording", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        case .running:
            Label("Running", systemImage: "checkmark.circle")
                .foregroundStyle(.green)
        case .preparing:
            Label(hostManager.statusLine, systemImage: "arrow.trianglehead.2.clockwise")
                .foregroundStyle(.secondary)
        case .unavailable(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        case .idle:
            Label("Not started", systemImage: "circle.dashed")
                .foregroundStyle(.secondary)
        }
    }

    private func pairedSections(deviceName: String) -> some View {
        Group {
            Section("Paired device") {
                LabeledContent("Device") {
                    Label(deviceName, systemImage: "iphone.gen3")
                }
                LabeledContent("Mac") {
                    Text(ProcessInfo.processInfo.hostName)
                        .textSelection(.enabled)
                }
            }

            Section {
                Button("Forget pairing…", systemImage: "link.badge.minus", role: .destructive) {
                    confirmDisconnect = true
                }
            }
        }
    }

    private var accessibilitySection: some View {
        Section("Remote touch (Mac pointer)") {
            if AccessibilityPermission.isGranted {
                Label("Accessibility enabled", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Button("Test cursor on streamed display") {
                    PlayniteRemoteInputPlayback.wigglePointerForTest()
                }
                Text("If the Mac cursor jumps, touch injection works. Restart the Mac app after changing Accessibility.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Label("Accessibility required for phone touch", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text(
                    "In System Settings → Privacy & Security → Accessibility, enable **\(AccessibilityPermission.settingsAppName)**. " +
                        "There is no separate “touch” entry — it is the same permission as controller mapping."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                Button("Show permission dialog…") {
                    AccessibilityPermission.promptIfNeeded()
                }
                Button("Open Accessibility Settings…") {
                    AccessibilityPermission.openSystemSettings()
                }
            }
        }
    }

    private var capabilitiesSection: some View {
        Section("After pairing") {
            Label("Phone: Session → Start Desktop stream", systemImage: "play.circle")
            Label("Video TCP \(PlayniteStreamPorts.videoTCP), audio UDP \(PlayniteStreamPorts.audioUDP)", systemImage: "film")
            Label("Touch on the phone moves the Mac pointer (UDP \(PlayniteStreamPorts.inputUDP))", systemImage: "hand.tap")
            Text(
                "Audio is sent over the network to your phone — it does not appear in System Settings → Sound → Output. " +
                    "Play something on the Mac while streaming; volume on the phone controls playback there."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

#Preview("Idle") {
    StreamingView()
}
