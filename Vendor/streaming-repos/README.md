# Streaming: Apollo + Moonlight (forks, PIN pairing, in-app HTTP)

This folder is where **your forks** of the streaming stack live locally:

| Component | Upstream | Role |
|-----------|----------|------|
| [Apollo](https://github.com/ClassicOldSong/Apollo) | Sunshine fork | **Host** on the Mac (encode + Moonlight protocol) |
| [Moonlight iOS](https://github.com/moonlight-stream/moonlight-ios) | — | **Client** native core for iPhone / iPad / Apple TV |
| [Moonlight Android](https://github.com/moonlight-stream/moonlight-android) | — | **Client** native core for Android phones / tablets |

The Mac app does **not** embed these as submodules by default. Run the clone script after you create forks on GitHub.

**Cross-platform UX:** [`companion_app/`](../../companion_app/) is a **Flutter** app (one UI for **iOS and Android**) for discovery, PIN pairing, and session controls. Low-latency decode/input stays in **platform-native** Moonlight code wired through `MethodChannel` on each OS.

## Why forks?

- **Apollo**: host on the Mac.
- **Moonlight iOS / Android**: official clients; fork each so pairing and control-plane HTTPS run in **native code** (or in-app WebView)—**not Chrome/Safari** for setup.

Pairing uses a **PIN** the Mac shows and the phone/tablet enters (same model as Sunshine/Moonlight today). **One PIN flow** works for both client platforms because Apollo speaks the standard Moonlight pairing protocol.

## 1. Create forks on GitHub

Fork into your account (GitHub UI or `gh repo fork`):

- https://github.com/ClassicOldSong/Apollo
- https://github.com/moonlight-stream/moonlight-ios
- https://github.com/moonlight-stream/moonlight-android

Point `git remote origin` at **your** forks.

## 2. Clone into this repo

From the repo root:

```bash
chmod +x Scripts/clone-streaming-forks.sh
./Scripts/clone-streaming-forks.sh
```

Clone **your** forks:

```bash
export APOLLO_GIT_URL=https://github.com/<you>/Apollo.git
export MOONLIGHT_IOS_GIT_URL=https://github.com/<you>/moonlight-ios.git
export MOONLIGHT_ANDROID_GIT_URL=https://github.com/<you>/moonlight-android.git
./Scripts/clone-streaming-forks.sh
```

Clones land in `Vendor/streaming-repos/` (gitignored):

- `Apollo/`
- `moonlight-ios/`
- `moonlight-android/`

(`MOONLIGHT_GIT_URL` is still accepted as an alias for `MOONLIGHT_IOS_GIT_URL`.)

## 3. What to change (high level)

### Apollo (host)

- Keep the **HTTPS server** on localhost (see `ControlPlanePorts` in Swift).
- Ensure **pairing PIN** endpoints work without a browser: Mac app + both mobile clients call them via native HTTP stacks.
- TLS: self-signed host cert; pin trust in Keychain (Mac) and platform trust stores / custom delegates on iOS and Android.

### Moonlight iOS

- Replace **Safari** (or external-browser) PC setup with PIN entry + `URLSession` / in-app `WKWebView` against `https://<mac-lan-ip>:<port>`, or native REST calls Moonlight already uses.
- PIN must match the Mac **Streaming** tab.

### Moonlight Android

- Same goals as iOS: **no Chrome Custom Tab / browser** for routine pairing; use in-app HTTP (`HttpsURLConnection`, OkHttp, or WebView) for the control plane.
- PIN channel identical so **one Mac pairing screen** serves Android and iOS users.

### Flutter companion (`companion_app/`)

- Shared Dart UI for Hosts / Pairing / Session on **both** stores.
- `StreamingBridge` (`com.playnite.companion/streaming_bridge`): implement stubs in:
  - `companion_app/ios/Runner/AppDelegate.swift`
  - `companion_app/android/.../MainActivity.kt`
- Delegate `startStream` / `stopStream` to code from your **moonlight-ios** / **moonlight-android** forks (or embedded modules).

See [`docs/companion-flutter.md`](../../docs/companion-flutter.md) and [`docs/streaming-setup.md`](../../docs/streaming-setup.md).

## 4. Mac app integration

Swift types under `Sources/MacGameLibrary/Streaming/`: ports, PIN models, `StreamingControlPlaneClient` (replace stub with Apollo routes). The host does **not** need separate pairing logic per phone OS—only the client apps differ.

## References

- [Sunshine](https://github.com/LizardByte/Sunshine) (upstream of Apollo)
- [Apollo](https://github.com/ClassicOldSong/Apollo)
- [Moonlight iOS](https://github.com/moonlight-stream/moonlight-ios)
- [Moonlight Android](https://github.com/moonlight-stream/moonlight-android)
