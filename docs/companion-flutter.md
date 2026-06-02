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

- Cross-platform Flutter UI with 3 tabs:
  - **Hosts** — discovery (stub returns sample data)
  - **Pairing** — PIN entry (same PIN the Mac **Streaming** tab shows)
  - **Session** — start/stop stream actions
- Method channel bridge in Dart:
  - Channel: `com.playnite.companion/streaming_bridge`
  - Methods: `discoverHosts`, `pairWithPin`, `startStream`, `stopStream`
- Native method channel stubs (**both platforms**):
  - Android: `companion_app/android/app/src/main/kotlin/com/example/companion_app/MainActivity.kt`
  - iOS: `companion_app/ios/Runner/AppDelegate.swift`

Stubs return placeholder responses so the UI flow works on **either** OS before Moonlight integration.

## Run

```bash
cd companion_app
flutter pub get
flutter run          # pick a connected iOS or Android device/simulator
flutter run -d ios
flutter run -d android
```

## Next integration tasks

1. Replace native stub responses with real host discovery + pairing on **iOS and Android** (same Dart API; different native implementations).
2. Hook `pairWithPin` to Apollo/Sunshine-compatible PIN endpoints (`https://<mac-ip>:47990` or your fork’s routes). PIN is **platform-agnostic**.
3. Wire `startStream` / `stopStream` to Moonlight-derived native code:
   - iOS → logic from `Vendor/streaming-repos/moonlight-ios`
   - Android → logic from `Vendor/streaming-repos/moonlight-android`
4. Keep Flutter as UX/business logic; keep low-latency media/input in native code on each OS.
5. iOS: add `NSLocalNetworkUsageDescription` (and Bonjour services if you use mDNS) when implementing discovery.
6. Android: document user steps if installing the APK outside Play Store; use network security config for pinned host TLS if needed.

## Related docs

- Mac host + fork clones: [`streaming-setup.md`](streaming-setup.md)
- Vendor README: [`Vendor/streaming-repos/README.md`](../Vendor/streaming-repos/README.md)
