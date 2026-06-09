# Playnite companion app

Flutter app (iOS + Android) for LAN pairing with Mac Game Library’s native stream host.

## Setup

```bash
flutter pub get
flutter run
```

**Settings:** enter the Mac’s LAN IPv4 from Mac → Streaming (port **28765** is automatic).

**Pairing:** phone starts pairing first; Mac confirms the same PIN in Streaming.

**Video:** not wired yet — pairing and discovery work over `playnite-stream/1`.

## iOS

```bash
cd ios && pod install && cd ..
flutter run
```

Moonlight pods were removed; only Flutter + GameController remain.

### Physical iPhone / iPad (blank white screen + `flutter run` stuck)

On **real devices** running **iOS 18.4 or newer**, Apple blocks the JIT that Flutter **debug** builds need. The app can install but shows a **white screen**, crash in `Dart_Initialize`, and the terminal sits on **“Installing and launching…”** / **“Dart VM Service was not discovered”** because the engine never starts.

**Fix — use profile (or release) mode on the device:**

```bash
flutter run --profile
# or
./scripts/run-ios-device.sh
```

- **Simulator** and **Android** can still use plain `flutter run` (debug + hot reload).
- Profile mode has no hot reload; stop and re-run after code changes.
- If profile still fails, try `flutter upgrade` (newer Flutter adds debug fallbacks on recent iOS), then `flutter clean && flutter pub get`.

**Settings on device:** Mac **LAN IP** only (e.g. `192.168.1.14`), not `127.0.0.1`.

## Android

No NDK / Moonlight module. `startStream` returns a clear “not implemented” error until native decode lands.
