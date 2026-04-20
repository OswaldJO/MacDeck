# Flutter Companion App (iOS + Android)

This repo now contains a starter Flutter companion app at `companion_app/`.

## Project layout (Dart)

- `companion_app/lib/main.dart` — entrypoint only (`runApp`).
- `companion_app/lib/src/app.dart` — `MaterialApp` / theme.
- `companion_app/lib/src/screens/home_page.dart` — tabs + UI state.
- `companion_app/lib/src/services/streaming_bridge.dart` — `MethodChannel` API (`StreamingBridge.channelName` must match native code).
- `companion_app/lib/src/models/host_info.dart` — host row model.

## What is included

- Cross-platform Flutter UI with 3 tabs:
  - Hosts (discovery)
  - Pairing (PIN entry)
  - Session (start/stop stream actions)
- Method channel bridge in Dart:
  - Channel: `com.playnite.companion/streaming_bridge`
  - Methods: `discoverHosts`, `pairWithPin`, `startStream`, `stopStream`
- Native method channel stubs:
  - Android: `companion_app/android/app/src/main/kotlin/com/example/companion_app/MainActivity.kt`
  - iOS: `companion_app/ios/Runner/AppDelegate.swift`

The native handlers currently return stub responses so the UI flow works immediately.

## Run

```bash
cd companion_app
flutter pub get
flutter run
```

## Next integration tasks

1. Replace native stub responses with real host discovery + pairing calls.
2. Hook `pairWithPin` to your Apollo/Sunshine-compatible PIN endpoint.
3. Wire `startStream`/`stopStream` to platform-native streaming cores (Moonlight-derived code per platform).
4. Keep the Flutter layer as UX/business logic, with low-latency media/input in native code.
