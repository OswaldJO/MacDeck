# Streaming setup (Mac host + iOS / Android clients)

This project aims for **Steam Link–style** pairing and streaming: control stays in **native apps** on the Mac and on **phones/tablets** (iOS and Android), not in Safari or Chrome. The stack uses **Sunshine / Apollo** on the desktop and **Moonlight** on mobile—the same family Playnite users often reference for remote play.

More detail on fork layout: [`Vendor/streaming-repos/README.md`](../Vendor/streaming-repos/README.md).  
Companion app (shared mobile UI): [`companion-flutter.md`](companion-flutter.md).

## Architecture (two layers)

| Layer | Where | Purpose |
|-------|--------|---------|
| **Host** | Mac — [Apollo](https://github.com/ClassicOldSong/Apollo) | Encode desktop; Moonlight protocol; HTTPS control plane + PIN |
| **Client UX** | `companion_app/` (Flutter) | One app build for **iOS + Android**: discovery, PIN entry, session buttons |
| **Client media** | Forked Moonlight repos | Low-latency decode/input per platform (wired via `MethodChannel`) |

The Mac **Streaming** tab shows the PIN once; **either** mobile OS can complete pairing with the same code.

## What you need to do

### 1. Create GitHub forks

Fork these into **your** GitHub account:

- [Apollo](https://github.com/ClassicOldSong/Apollo) — host on macOS
- [Moonlight iOS](https://github.com/moonlight-stream/moonlight-ios) — iPhone / iPad client core
- [Moonlight Android](https://github.com/moonlight-stream/moonlight-android) — Android client core

Push pairing / in-app HTTP changes to your forks on each repo.

### 2. Clone the forks locally

From the **root of this repo**:

```bash
chmod +x Scripts/clone-streaming-forks.sh
./Scripts/clone-streaming-forks.sh
```

Clone **your** forks:

```bash
export APOLLO_GIT_URL='https://github.com/<your-username>/Apollo.git'
export MOONLIGHT_IOS_GIT_URL='https://github.com/<your-username>/moonlight-ios.git'
export MOONLIGHT_ANDROID_GIT_URL='https://github.com/<your-username>/moonlight-android.git'
./Scripts/clone-streaming-forks.sh
```

Sources:

- `Vendor/streaming-repos/Apollo`
- `Vendor/streaming-repos/moonlight-ios`
- `Vendor/streaming-repos/moonlight-android`

Those directories are **gitignored**.

### 3. Implement product behavior (your forks)

**Apollo (host on Mac)**

- Run the Sunshine/Apollo **HTTPS control plane** (default port reference: `ControlPlanePorts.webUIHTTPS` in `Sources/MacGameLibrary/Streaming/ControlPlanePorts.swift`).
- Expose **pairing** (PIN) and session APIs for `URLSession` from the Mac app—no Safari.
- Handle **TLS** (self-signed cert; trust in-app after pairing).
- One host serves **both** iOS and Android Moonlight clients; no OS-specific host forks required.

**Moonlight iOS**

- PIN entry matching the Mac **Streaming** tab.
- Control plane via `URLSession` / in-app `WKWebView` to `https://<mac-lan-ip>:<port>`—not Safari for setup.

**Moonlight Android**

- Same PIN and HTTPS control plane as iOS—in-app only (no external browser for routine pairing).
- Align TLS trust handling with Android network security config if you pin the host cert.

**Flutter companion**

- Implement `discoverHosts`, `pairWithPin`, `startStream`, `stopStream` on **both** native sides (see `docs/companion-flutter.md`).
- Run on device: `cd companion_app && flutter run` (pick iOS or Android simulator/device).

### 4. Wire the Mac app to Apollo

Swift scaffolding: `Sources/MacGameLibrary/Streaming/`

- `ControlPlanePorts.swift` — e.g. `https://127.0.0.1:47990`
- `PINPairingTypes.swift` — PIN / paired device models
- `InAppControlPlaneClient.swift` — replace `StubStreamingControlPlaneClient` with real Apollo routes
- `StreamingPairingSession.swift` — connect pairing UI to the client when any mobile device completes handshake

### 5. Runtime and permissions

- **Same Wi‑Fi** (or routed LAN) between Mac and phone/tablet.
- **Firewall**: allow Apollo/Sunshine streaming and control-plane ports.
- **Mac**: sandbox / network entitlements if you bundle Apollo.
- **iOS**: local network usage description when discovering the Mac on LAN.
- **Android**: `INTERNET` (already in manifest); consider `ACCESS_NETWORK_STATE`; cleartext not needed if you stay on HTTPS.

## References

- [Sunshine](https://github.com/LizardByte/Sunshine)
- [Apollo](https://github.com/ClassicOldSong/Apollo)
- [Moonlight iOS](https://github.com/moonlight-stream/moonlight-ios)
- [Moonlight Android](https://github.com/moonlight-stream/moonlight-android)
