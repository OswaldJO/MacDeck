# Flutter Companion App (iOS + Android)

The companion app at `companion_app/` is the **single mobile shell** for both **iOS and Android**. Users install it from the App Store or Play Store (once published); pairing and session UX are identical on both platforms.

Native **Moonlight** forks (`moonlight-ios`, `moonlight-android`) supply decode/input; Flutter owns discovery, PIN pairing UI, and session controls via a shared `MethodChannel`.

## Project layout (Dart)

- `companion_app/lib/main.dart` — entrypoint only (`runApp`).
- `companion_app/lib/src/app.dart` — `MaterialApp` / theme.
- `companion_app/lib/src/screens/home_page.dart` — tabs + UI state.
- `companion_app/lib/src/services/streaming_bridge.dart` — `MethodChannel` API (`StreamingBridge.channelName` must match native code).
- `companion_app/lib/src/models/host_info.dart` — host row model.

## What is included

- Cross-platform Flutter UI with 4 tabs:
  - **Hosts** — discovers your Mac via Moonlight `serverinfo`; shows **Paired** when saved pairing + HTTPS `applist` probe succeed
  - **Pairing** — full Sunshine/Moonlight PIN handshake in Dart (`SunshinePairingService`)
  - **Session** — **Start Desktop 1080p60** launches native Moonlight decode (Android `Game` activity; iOS `StreamFrameViewController` modal)
  - **Settings** — Mac LAN IP + Save & discover
- Dart services:
  - `streaming_bridge.dart` — MethodChannel for `startStream` / `stopStream` only (pairing stays in Dart)
  - `sunshine_pairing_service.dart` — HTTP/HTTPS pairing + host discovery
  - `pairing_state_store.dart` — per-host paired flag + pinned server cert
  - `moonlight_stream_service.dart` — builds launch config for native stream
- Native:
  - **Android**: `moonlight-stream` Gradle module (vendored Moonlight sources + JNI). Syncs to `~/.cache/playnite-moonlight-ndk` because NDK cannot build in paths with spaces (e.g. `Playnite Mac`).
  - **iOS**: `PlayniteMoonlight` CocoaPod (`companion_app/ios/MoonlightStream/`) — syncs patched Limelight sources from `Vendor/streaming-repos/moonlight-ios`, builds `moonlight-common.xcframework`, presents full-screen stream UI from `PlayniteStreamLaunchHelper`.

## Run

```bash
cd companion_app
flutter pub get
# Clone Moonlight forks first (from repo root)
../Scripts/clone-streaming-forks.sh
flutter run -d android   # or -d ios / physical device
```

Pair once on **Pairing** tab, confirm **Hosts** shows **Paired**, then **Session** → **Start Desktop 1080p60**.

## Android build notes

- Requires `Vendor/streaming-repos/moonlight-android` (run `Scripts/clone-streaming-forks.sh`).
- Native build output is redirected to `~/.cache/playnite-companion-native/` when the repo path contains spaces.
- Before launch, `StreamLaunchHelper` copies the Dart pairing client cert/key into Moonlight’s `filesDir` (`client.crt`, `client.key`, `uniqueid`).

## iOS build notes

- Requires `Vendor/streaming-repos/moonlight-ios` and Xcode (first `pod install` builds `moonlight-common` and may fetch OpenSSL via SPM — keychain prompt for `github.com` is normal).
- Run from `companion_app/ios`: `pod install` (or let `flutter run` trigger it).
- `PlayniteMoonlight` copies vendored libs into `MoonlightStream/Vendor/prebuilt/` (SDL2 is stripped of `SDL_uikit_main` so it does not conflict with Flutter’s `@main`).
- Before launch, `PlayniteStreamLaunchHelper` writes `client.crt`, `client.key`, `client.p12`, and `uniqueid` into the app Documents directory (same pairing material as Android).

## Next integration tasks

1. **Stop stream** — track native stream lifecycle for reliable `stopStream` on both platforms.
2. **Discovery** — optional mDNS beyond configured LAN IP.
3. **iOS device smoke test** — verify E2E stream on a physical iPhone (build succeeds; streaming not yet validated in CI).

## Related docs

- Mac host + fork clones: [`streaming-setup.md`](streaming-setup.md)
- Vendor README: [`Vendor/streaming-repos/README.md`](../Vendor/streaming-repos/README.md)
