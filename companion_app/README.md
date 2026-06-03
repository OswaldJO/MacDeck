# Mac Game Library — companion app (iOS + Android)

Flutter app for **both** mobile platforms: host discovery, PIN pairing with the Mac **Streaming** tab, and stream session controls.

## Run

```bash
cd companion_app
flutter pub get
flutter run
```

Pick an iOS simulator, Android emulator, or physical device when prompted.

## Architecture

- **Dart** (`lib/`): shared UI and `StreamingBridge` API.
- **Native** (`ios/`, `android/`): `StreamingBridge` → Moonlight decode (`moonlight-stream` on Android, `PlayniteMoonlight` pod on iOS). Clone forks with `../Scripts/clone-streaming-forks.sh` before first native build.

See [`../docs/companion-flutter.md`](../docs/companion-flutter.md) and [`../docs/streaming-setup.md`](../docs/streaming-setup.md).
