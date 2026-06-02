import AppKit
import SwiftUI

struct StreamingView: View {
    @State private var session: StreamingPairingSession
    @State private var hostManager = SunshineHostManager.shared
    @State private var confirmDisconnect = false
    @State private var showOpenSourceReferences = false

    @State private var pinEntry = ""
    @State private var deviceNameEntry = "Companion"

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(session: StreamingPairingSession = StreamingPairingSession()) {
        _session = State(initialValue: session)
    }

    var body: some View {
        NavigationStack {
            Form {
                heroSection
                sunshineHostSection

                switch session.phase {
                case .idle:
                    idlePairingSection
                case .awaiting(let expiresAt):
                    awaitingSections(expiresAt: expiresAt)
                case .paired(let deviceName):
                    pairedSections(deviceName: deviceName)
                }

                capabilitiesSection
                openSourceReferencesSection
            }
            .formStyle(.grouped)
            .navigationTitle("Streaming")
        }
        .padding()
        .frame(minWidth: 520, minHeight: 520)
        .onAppear {
            Task { await hostManager.ensureReady() }
            session.refreshHostStatus()
        }
        .onReceive(timer) { _ in
            guard case .awaiting(let exp) = session.phase, Date() >= exp else { return }
            session.cancelPairing()
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
                        "Playnite starts Sunshine for you. Pair from the companion app on iOS or Android—enter the PIN here when the phone shows it. No browser or manual Sunshine setup."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var sunshineHostSection: some View {
        Section("Streaming host") {
            hostStateRow
            if let lanIP = LocalNetworkAddress.primaryIPv4() {
                LabeledContent("LAN IP (enter in companion Settings)") {
                    Text(lanIP)
                        .textSelection(.enabled)
                }
            }
            if let binary = SunshineBinaryLocator.resolvedLabel() {
                LabeledContent("Sunshine binary") {
                    Text(binary)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
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
                hostManager.stopManagedProcess()
                Task {
                    await hostManager.ensureReady()
                    session.refreshHostStatus()
                }
            }
        }
    }

    @ViewBuilder
    private var hostStateRow: some View {
        switch hostManager.state {
        case .running where session.hostReachable:
            Label("Running and reachable", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .running:
            Label("Running", systemImage: "checkmark.circle")
                .foregroundStyle(.green)
        case .preparing, .starting:
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

    private var hostIsUnavailable: Bool {
        if case .unavailable = hostManager.state { return true }
        return false
    }

    private var idlePairingSection: some View {
        Section("Pairing") {
            VStack(alignment: .leading, spacing: 10) {
                pairingStepRow(number: 1, text: "Phone → Pairing → Start pairing. Keep that screen open until it says “Waiting for Mac…”.")
                pairingStepRow(number: 2, text: "Mac → Start pairing below, enter the same 4-digit PIN, then Submit PIN to Sunshine.")
                pairingStepRow(number: 3, text: "Do not submit on the Mac until the phone is waiting.")
            }
            .padding(.vertical, 4)

            Button {
                session.startPairing()
            } label: {
                Label("Start pairing", systemImage: "key.horizontal")
            }
            .disabled(hostIsUnavailable)
        }
    }

    private func awaitingSections(expiresAt: Date) -> some View {
        Group {
            Section("PIN from companion") {
                Text("The companion app displays a 4-digit PIN. Enter the same PIN here so Sunshine can accept the pairing.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField("4-digit PIN", text: $pinEntry)
                    .textFieldStyle(.roundedBorder)
                    .font(.title2.monospacedDigit())
                    .onChange(of: pinEntry) { _, newValue in
                        let filtered = String(newValue.filter(\.isNumber).prefix(4))
                        if filtered != newValue { pinEntry = filtered }
                    }

                TextField("Device name", text: $deviceNameEntry)
                    .textFieldStyle(.roundedBorder)

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = max(0, expiresAt.timeIntervalSince(context.date))
                    LabeledContent("Time left") {
                        Text(formatRemaining(remaining))
                            .monospacedDigit()
                            .foregroundStyle(remaining < 60 ? .orange : .secondary)
                    }
                }

                pinSubmitFeedback

                HStack {
                    Button("Cancel", role: .cancel) {
                        session.cancelPairing()
                        pinEntry = ""
                    }
                    .disabled(session.pinSubmitState == .submitting)

                    Spacer()

                    Button {
                        session.submitPIN(pinEntry, deviceName: deviceNameEntry)
                    } label: {
                        if session.pinSubmitState == .submitting {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Submitting…")
                            }
                        } else {
                            Label("Submit PIN to Sunshine", systemImage: "paperplane.fill")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(pinEntry.count != 4 || session.pinSubmitState == .submitting)
                }
            }

            Section {
                if session.pinSubmitState == .accepted {
                    Text("Sunshine accepted the PIN. Keep the phone on the Pairing screen until this advances to Paired.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Wait until the phone shows “Waiting for Mac…” before submitting. This screen advances automatically when pairing completes.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    @ViewBuilder
    private var pinSubmitFeedback: some View {
        switch session.pinSubmitState {
        case .idle:
            EmptyView()
        case .submitting:
            HStack(spacing: 10) {
                ProgressView()
                Text("Sending PIN to Sunshine…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        case .accepted:
            Label {
                Text("PIN accepted — waiting for phone to finish pairing.")
                    .font(.subheadline)
            } icon: {
                Image(systemName: "checkmark.circle.fill")
            }
            .foregroundStyle(.green)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.green.opacity(0.12)))
        case .failed(let message):
            Label {
                Text(message)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .foregroundStyle(.red)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.10)))
        }
    }

    private func pairedSections(deviceName: String) -> some View {
        Group {
            Section("Status") {
                LabeledContent("Device") {
                    Label(deviceName, systemImage: "iphone.gen3")
                }
                LabeledContent("Mac") {
                    Text(ProcessInfo.processInfo.hostName)
                        .textSelection(.enabled)
                }
                LabeledContent("Streaming") {
                    Label("Ready — start a stream from the companion", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button("Disconnect…", systemImage: "link.badge.minus", role: .destructive) {
                    confirmDisconnect = true
                }
            }
        }
    }

    private var capabilitiesSection: some View {
        Section("After pairing") {
            Label("Encode on the Mac with Sunshine; decode on the phone via Moonlight protocol", systemImage: "arrow.left.arrow.right")
            Label("Session start/stop from the companion app (stream stub for now)", systemImage: "play.circle")
        }
    }

    private var openSourceReferencesSection: some View {
        Section {
            DisclosureGroup("Upstream references", isExpanded: $showOpenSourceReferences) {
                VStack(alignment: .leading, spacing: 10) {
                    referenceRow(
                        title: "Sunshine",
                        subtitle: "Mac host — fork this for in-app pairing changes.",
                        url: URL(string: "https://github.com/LizardByte/Sunshine")!
                    )
                    referenceRow(
                        title: "Moonlight iOS / Android",
                        subtitle: "Client cores; companion uses a Dart pairing shim for now.",
                        url: URL(string: "https://github.com/moonlight-stream/moonlight-android")!
                    )
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func referenceRow(title: String, subtitle: String, url: URL) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Link(title, destination: url)
                .font(.body.weight(.medium))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pairingStepRow(number: Int, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.accentColor))
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func formatRemaining(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

#Preview("Idle") {
    StreamingView()
}

#Preview("Paired") {
    let s = StreamingPairingSession()
    s.phase = .paired(deviceName: "Demo phone")
    return StreamingView(session: s)
}
