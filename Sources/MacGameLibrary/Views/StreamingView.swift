import AppKit
import SwiftUI

// MARK: - View

struct StreamingView: View {
    @State private var session: StreamingPairingSession
    @State private var showFinishPairingSheet = false
    @State private var pendingDeviceName = ""
    @State private var confirmDisconnect = false
    @State private var showOpenSourceReferences = false

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(session: StreamingPairingSession = StreamingPairingSession()) {
        _session = State(initialValue: session)
    }

    var body: some View {
        NavigationStack {
            Form {
                heroSection
                approachSection
                controlPlaneSection

                switch session.phase {
                case .idle:
                    idlePairingSection
                case .awaiting(let code, let expiresAt):
                    awaitingSections(code: code, expiresAt: expiresAt)
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
        .frame(minWidth: 520, minHeight: 480)
        .onReceive(timer) { _ in
            guard case .awaiting(_, let exp) = session.phase, Date() >= exp else { return }
            session.cancelPairing()
        }
        .sheet(isPresented: $showFinishPairingSheet) {
            finishPairingSheet
        }
        .confirmationDialog(
            "Disconnect “\(pairedNameForDialog)” from streaming?",
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
                    Text("Steam Link–style, open stack")
                        .font(.headline)
                    Text(
                        "Target experience: low-latency game video to your iPhone on the same network, with pairing and trust handled entirely inside this Mac app and a companion app—like Steam Link, not like signing in through a browser."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var approachSection: some View {
        Section("How we use Sunshine / Moonlight ideas") {
            Text(
                "Sunshine and forks such as Apollo are open hosts that speak the protocol Moonlight clients expect; Moonlight for iOS is the usual phone client. Expand “Upstream open-source references” below for the GitHub projects."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)

            Text(
                "Those hosts often rely on a local web UI for first-time login and advanced settings. This app’s direction is to keep pairing, credentials, and everyday controls in native UI on the Mac and on the phone—no Safari setup step for normal use."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }

    private var controlPlaneSection: some View {
        Section("In-app control plane (Apollo)") {
            LabeledContent("HTTPS base") {
                Text(URL.localhostControlPlane().absoluteString)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
            }
            Text(
                "Fork Apollo and Moonlight iOS under Vendor (see Scripts + README). The Mac app will talk to this URL with URLSession—same HTTP as the web UI, without Safari. Pairing PIN is the channel; TLS trust is handled in-app."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var idlePairingSection: some View {
        Section("Pairing") {
            VStack(alignment: .leading, spacing: 10) {
                pairingStepRow(number: 1, text: "Install the Mac Game Library companion app on your iPhone (Moonlight-compatible client path).")
                pairingStepRow(number: 2, text: "Put the phone on the same Wi‑Fi as this Mac.")
                pairingStepRow(number: 3, text: "Tap Start pairing, then enter the code on the phone when asked—same rhythm as Steam Link, without opening a browser on either device.")
            }
            .padding(.vertical, 4)

            Button {
                session.startPairing()
            } label: {
                Label("Start pairing", systemImage: "key.horizontal")
            }
        }
    }

    private func awaitingSections(code: String, expiresAt: Date) -> some View {
        Group {
            Section("Enter this code on your phone") {
                Text(code)
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .tracking(10)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .accessibilityLabel("Pairing code \(code)")

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = max(0, expiresAt.timeIntervalSince(context.date))
                    LabeledContent("Time left") {
                        Text(formatRemaining(remaining))
                            .monospacedDigit()
                            .foregroundStyle(remaining < 60 ? .orange : .secondary)
                    }
                }

                HStack {
                    Button("Copy code") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(code, forType: .string)
                    }
                    Spacer()
                    Button("Cancel pairing", role: .cancel) {
                        session.cancelPairing()
                    }
                }

                Button {
                    pendingDeviceName = defaultPhoneName()
                    showFinishPairingSheet = true
                } label: {
                    Label("Phone shows connected", systemImage: "checkmark.circle")
                }
                .buttonStyle(.borderedProminent)
            }

            Section {
                Text(
                    "With a real host implementation, this screen advances automatically when the phone completes the handshake (same role as Moonlight pairing with a Sunshine PIN, but driven from native UI)."
                )
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
        }
    }

    private func pairedSections(deviceName: String) -> some View {
        Group {
            Section("Status") {
                LabeledContent("Phone") {
                    Label(deviceName, systemImage: "iphone")
                        .foregroundStyle(.primary)
                }
                LabeledContent("Mac") {
                    Text(ProcessInfo.processInfo.hostName)
                        .textSelection(.enabled)
                }
                LabeledContent("Streaming") {
                    Label("Ready when you start a game", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button("Disconnect phone…", systemImage: "link.badge.minus", role: .destructive) {
                    confirmDisconnect = true
                }
            }
        }
    }

    private var capabilitiesSection: some View {
        Section("After pairing") {
            Label("Encode on the Mac, decode on the phone over LAN (host/client model as in Sunshine + Moonlight)", systemImage: "arrow.left.arrow.right")
            Label("Resolution and bitrate tuned for the phone without forcing a browser for routine changes", systemImage: "rectangle.on.rectangle")
            Label("Session controls stay in-app (goal: parity with Steam Link’s simplicity)", systemImage: "slider.horizontal.3")
        }
    }

    private var openSourceReferencesSection: some View {
        Section {
            DisclosureGroup("Upstream open-source references", isExpanded: $showOpenSourceReferences) {
                VStack(alignment: .leading, spacing: 10) {
                    referenceRow(
                        title: "Sunshine",
                        subtitle: "Self-hosted stream host for Moonlight clients.",
                        url: URL(string: "https://github.com/LizardByte/Sunshine")!
                    )
                    referenceRow(
                        title: "Apollo",
                        subtitle: "Sunshine fork focused on native client resolution.",
                        url: URL(string: "https://github.com/ClassicOldSong/Apollo")!
                    )
                    referenceRow(
                        title: "Moonlight iOS",
                        subtitle: "GameStream/Moonlight client for iPhone and Apple TV.",
                        url: URL(string: "https://github.com/moonlight-stream/moonlight-ios")!
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

    private var finishPairingSheet: some View {
        NavigationStack {
            Form {
                Section {
                    Text("The phone can supply its device name automatically once the protocol is wired up.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Section("Device name") {
                    TextField("e.g. Josh’s iPhone", text: $pendingDeviceName)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Finish pairing")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showFinishPairingSheet = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        session.markPaired(deviceName: pendingDeviceName)
                        showFinishPairingSheet = false
                    }
                }
            }
        }
        .frame(minWidth: 400, minHeight: 220)
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
        let m = s / 60
        let r = s % 60
        return String(format: "%d:%02d", m, r)
    }

    private func defaultPhoneName() -> String {
        let name = Host.current().localizedName ?? "Mac"
        return "\(name)’s iPhone"
    }
}

// MARK: - Previews

#Preview("Idle") {
    StreamingView()
}

#Preview("Paired") {
    let s = StreamingPairingSession()
    s.phase = .paired(deviceName: "Demo iPhone")
    return StreamingView(session: s)
}
