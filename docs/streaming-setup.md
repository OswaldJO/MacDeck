# Streaming setup (Mac host + iPhone)

This project aims for **Steam Link–style** pairing and streaming: control stays in **native apps** on the Mac and iPhone, not in Safari. The stack is aligned with **Sunshine / Apollo** (host on the desktop) and **Moonlight** (client on iOS), the same family Playnite users often reference for remote play.

More detail on fork layout also lives in [`Vendor/streaming-repos/README.md`](../Vendor/streaming-repos/README.md).

## What you need to do

### 1. Create GitHub forks

Fork these repositories into **your** GitHub account (you will customize them):

- [Apollo](https://github.com/ClassicOldSong/Apollo) (Sunshine fork — host on macOS)
- [Moonlight iOS](https://github.com/moonlight-stream/moonlight-ios) (client for iPhone / Apple TV)

You will push your pairing / in-app HTTP changes to these forks.

### 2. Clone the forks locally

From the **root of this repo**:

```bash
chmod +x Scripts/clone-streaming-forks.sh
```

Clone **upstream** (for a quick look):

```bash
./Scripts/clone-streaming-forks.sh
```

Clone **your** forks:

```bash
export APOLLO_GIT_URL='https://github.com/<your-username>/Apollo.git'
export MOONLIGHT_GIT_URL='https://github.com/<your-username>/moonlight-ios.git'
./Scripts/clone-streaming-forks.sh
```

Sources are created under:

- `Vendor/streaming-repos/Apollo`
- `Vendor/streaming-repos/moonlight-ios`

Those directories are **gitignored** so large clones are not committed by mistake.

### 3. Implement the product behavior (your forks)

**Apollo (host on Mac)**

- Run the Sunshine/Apollo **HTTPS control plane** on localhost (port is documented upstream; this app’s default reference is `ControlPlanePorts.webUIHTTPS` in `Sources/MacGameLibrary/Streaming/ControlPlanePorts.swift`).
- Expose **pairing** (PIN) and session APIs so they can be called with **`URLSession`** from the Mac app instead of requiring the user to open Safari.
- Handle **TLS**: the host typically uses a self-signed certificate; the Mac app will need a `URLSessionDelegate` (or equivalent) to trust that cert after pairing or first launch.
- Optionally hide or skip browser-only onboarding in release builds; advanced settings can remain behind an in-app **WKWebView** if you still need HTML.

**Moonlight iOS (phone)**

- Replace flows that open **Safari** for PC setup with:
  - PIN entry that matches the Mac **Streaming** tab, plus
  - Calls to the **same HTTPS endpoints** the web UI uses (`URLSession` or **WKWebView** loaded to `https://<your-mac-lan-ip>:<port>`), **or** native UI that hits the same REST routes Moonlight already uses.

### 4. Wire this Mac app to your host

Swift scaffolding lives under `Sources/MacGameLibrary/Streaming/`:

- `ControlPlanePorts.swift` — default HTTPS base (e.g. `https://127.0.0.1:47990`).
- `PINPairingTypes.swift` — PIN / paired identity models.
- `InAppControlPlaneClient.swift` — replace `StubStreamingControlPlaneClient` with real `URLSession` calls to Apollo’s routes once you map them.
- `StreamingPairingSession.swift` — UI state for the Streaming tab; connect `submitPairingPIN` (or equivalent) to your client when the host confirms pairing.

The **Streaming** tab in the app is the place users see the PIN and status; backend work is in Apollo + Moonlight + the stub client above.

### 5. Runtime and permissions

- **Same Wi‑Fi** (or routed LAN) between Mac and phone for typical Moonlight use.
- **Firewall**: allow the host process and the ports Sunshine/Apollo documents for streaming and control plane.
- If you embed or launch Apollo as a helper, add the right **sandbox / network** entitlements in the Xcode app target (exact keys depend on how you package the host).

## References

- [Sunshine](https://github.com/LizardByte/Sunshine) (upstream of Apollo)
- [Apollo](https://github.com/ClassicOldSong/Apollo)
- [Moonlight iOS](https://github.com/moonlight-stream/moonlight-ios)
