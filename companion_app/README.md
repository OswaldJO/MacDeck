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

## Android

No NDK / Moonlight module. `startStream` returns a clear “not implemented” error until native decode lands.
