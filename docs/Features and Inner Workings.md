# Mac Game Library — Features and Inner Workings

This document describes **how the app behaves today** and **where implementation lives**. For a short, commit-adjacent summary of recent changes, see `source control log.md`.

---

## Product shape

- **SwiftUI** app with a tabbed shell: **Library**, **Emulators**, **Paths**, **Streaming**, **Controllers**.
- **SwiftData** persists emulators, game folder paths, and library games. Store file: see `PersistenceStoreLocation` (default under Application Support).

---

## Library tab

### Sidebar

- **All** — every visible game (emulator-linked + standalone Mac/Epic-style entries that pass filters).
- **Mac Games** — games with **no** `emulatorUUID` (native Mac adds, Epic imports, etc.). Context menu can clear only these entries.
- **Per-emulator** — games linked to that `EmulatorProfile`.
- **Cover Art and Metadata → Screen Scrapper** — detail pane for ScreenScraper: open credentials sheet, run a **full-library** metadata/cover scrape (not the game grid).

### Toolbar (Library)

- **Add Game** — `NSOpenPanel` for app/executable/directory; creates `LibraryGame` with no emulator.
- **Scan Paths** — `GamePathScanner.scan` plus `EpicInstalledGamesImporter.importInstalledGames`; may schedule metadata pass.
- **Import Epic Installed Games** — Epic-only import.
- **Metadata Settings** — presents `ScreenScraperSettingsSheet`.

### Grid and play

- `LibraryGamesGridView` / `GameLibraryTile`: tap for play/info overlay; play goes through `GameLauncher`.

### Inspector (Info)

- `LibraryGameInspectorView`: display name, file path (editable for **Mac** entries with no emulator), cover art list (choose file, reorder, set primary, remove).

**Key types:** `RootView.swift`, `LibraryGame.swift`.

---

## Emulators tab

- Add/configure `EmulatorProfile`: executable path, Playnite-style `{ImagePath}` / `{rom}` template, optional per-emulator ROM extensions.
- Export/import configured profiles. Bundled catalog + custom launch-argument presets live in `BuiltinEmulatorCatalog` / `CustomEmulatorLibraryStore`.

**Key types:** `EmulatorsView.swift`, `EmulatorProfile.swift`.

---

## Paths tab

Per **selected emulator**:

- **Game folders** — scanned by `GamePathScanner`.
- **Cover folders** — local images matched to ROM names on scan.
- **Exclude folders** — skipped during scan.
- **Toggle:** *Prioritize ScreenScraper art over local covers* — stored on `EmulatorProfile.preferScreenScraperCovers` (default `false`). Affects **auto-selected primary** cover after a metadata pass; all sources still accumulate in `coverImageOptions`.

**Key types:** `PathsView.swift`, `GameFolderPath.swift`, `GamePathScanner.swift`.

---

## Metadata and ScreenScraper

- **IGDB removed.** Remote metadata uses **ScreenScraper API v2** (`https://api.screenscraper.fr/api2/…`), currently **name search** via `jeuRecherche.php` in `ScreenScraperClient`.
- **Credentials:** `MetadataCredentials` — `devid` / `devpassword` required; `ssid` / `sspassword` optional. Persisted in `UserDefaults` (see `docs/metadata-setup.md`).
- **Background fetcher:** `MetadataBackgroundFetcher` — periodic small batches; can **schedule extra** after scans. Full pass: `scrapeAllNow` (used from Screen Scrapper sidebar).
- **Flow per game (simplified):** resolve local cover candidates when possible; if configured, fetch ScreenScraper result; merge **local + remote** URLs into `coverImageOptions`; set **primary** `coverImageURLString` using emulator’s `preferScreenScraperCovers` vs. local-first default; update title from scraper when useful; throttle via `metadataLastFetchAt`.

**Key types:** `MetadataService.swift`, `ScreenScraperClient.swift`, `MetadataBackgroundFetcher.swift`, `ScreenScraperSettingsSheet.swift`.

---

## Epic Games (installed only, no OAuth in-app)

- **Import:** `EpicInstalledGamesImporter` reads Epic launcher manifests under `~/Library/Application Support/Epic/.../Manifests`.
- **Model:** `LibraryGame.librarySourceID` (`"epic"`), `epicAppName` for launcher URI.
- **Launch:** `GameLauncher` — if `epicAppName` is set, tries `com.epicgames.launcher://apps/...` before falling back to direct path.

**Key types:** `EpicInstalledGamesImporter.swift`, `GameLauncher.swift`.

---

## Launch pipeline

- **Emulator games:** resolve `EmulatorProfile`, substitute `{ImagePath}` / `{rom}`, `NSWorkspace` open; handles some “already running .app” cases.
- **Standalone / no emulator:** Epic URI path above, else open `.app` or file URL.

**Key type:** `GameLauncher.swift`.

---

## Streaming tab (native Playnite host)

The Mac app embeds its own **Playnite stream host** (ScreenCaptureKit → H.264, HTTP control plane, UDP audio/input). The companion pairs over HTTP and opens a **native video activity** on Android (`PlayniteVideoActivity`); Sunshine/Moonlight RTSP is no longer required for the default Android desktop stream path.

### Host lifecycle

- **`PlayniteStreamHostManager`** — starts HTTP control (**28765**), TCP video listener (**28766**), UDP audio (**28767**), UDP input (**28768**); begins capture when the phone calls `POST /playnite/v1/stream/start`.
- **`PlayniteStreamControlServer`** — pairing queue, stream start/stop, returns `videoPort`, `audioPort`, `inputPort` to the companion.
- **`PlayniteVideoStreamServer`** — one TCP client; sends framed **`PNV1`** H.264 (Annex-B from `PlayniteH264Encoder`).
- **`PlayniteDisplayCapture`** — SCK display capture; optional **system audio** (`capturesAudio`) forwarded as PCM to the audio server.
- **`PlayniteAudioStreamServer`** — after phone sends **`PNAS`** subscribe datagram, replies with **`PNA1`** PCM (s16le) over UDP.
- **`PlayniteStreamInputServer`** — receives **`PNI1`** touch packets; **`PlayniteRemoteInputPlayback`** posts `CGEvent` pointer events.
- **`StreamingView`** — LAN IP, all four ports, Screen Recording + **Accessibility** status, **Test cursor on streamed display**, pairing approve/deny.

### macOS permissions

| Permission | Purpose | UI name |
|------------|---------|---------|
| **Screen Recording** | Desktop video + system audio capture | Mac Game Library |
| **Accessibility** | Synthetic mouse move/click from phone touch | Mac Game Library (same list entry; not a separate “touch” item) |

Restart the Mac app after toggling Accessibility. Audio is **not** routed through **System Settings → Sound → Output**; it is sent over the network to the phone speaker.

### Playnite stream ports

| Port | Protocol | Role |
|------|----------|------|
| 28765 | HTTP | Control — `playnite-stream/1`, pairing, stream start/stop |
| 28766 | TCP | Video — `PNV1` framed H.264 |
| 28767 | UDP | Audio — phone `PNAS` subscribe → Mac `PNA1` PCM |
| 28768 | UDP | Input — phone `PNI1` normalized touch |

**Key types:** `StreamingView.swift`, `PlayniteStreamHostManager.swift`, `PlayniteStreamControlServer.swift`, `PlayniteVideoStreamServer.swift`, `PlayniteDisplayCapture.swift`, `PlayniteAudioStreamServer.swift`, `PlayniteStreamInputServer.swift`, `PlayniteRemoteInputPlayback.swift`, `PlayniteStreamPorts.swift`, `AccessibilityPermission.swift`.

Setup: `docs/streaming-native.md`.

---

## Companion app (`companion_app/`)

Flutter shell (iOS + Android) for discovery, HTTP pairing with the native Mac host, and LAN streaming.

### Tabs

- **Settings** — Mac LAN IP; saved in `StreamingHostSettings`.
- **Hosts** — discover Mac via Playnite HTTP control plane.
- **Pairing** — device requests pairing; user approves on Mac **Streaming** tab.
- **Session** — **`StreamingBridge.startPlayniteStream`** → **Android** `PlayniteVideoActivity` (full-screen `SurfaceView` + `MediaCodec`). Passes `videoPort`, `audioPort`, `inputPort`, width/height from stream start response.

### Android native (Playnite video)

- **`PlayniteVideoActivity`** — TCP `PNV1` reader thread; codec pump on `HandlerThread`; decode profiles (Annex-B passthrough + `c2.android.avc.decoder` first).
- **`PlayniteAudioReceiver`** — UDP subscribe `PNAS`, play `PNA1` via `AudioTrack` (background thread, subscribe retry on timeout).
- **`PlayniteInputSender`** — finger drag/tap on the video `SurfaceView` → UDP `PNI1` to Mac (background thread). This is the primary pointer path during a native stream; the old **Mouse emulation** settings toggle was removed.
- **`PlayniteRemoteInputPlayback`** (Mac) — maps normalized touch to the **captured display** frame; Y uses `minY + ny × height` so finger-up on the phone moves the cursor up on the Mac.
- **`PlayniteStreamLog`** — writes `playnite_stream.log` under app files dir for export/debug.

**Key types:** `streaming_bridge.dart`, `playnite_host_client.dart`, `PlayniteVideoActivity.kt`, `PlayniteAudioReceiver.kt`, `PlayniteInputSender.kt`, `PlayniteStreamProtocols.kt`.

### Phone export log (what to look for)

| Log line | Meaning |
|----------|---------|
| `Rendered frame #N` | Video path healthy |
| `Audio subscribed` | Phone listening; if no `First audio packet` / `AudioTrack started`, Mac is not sending `PNA1` |
| `Input UDP #1` | Touch packets leaving the phone |
| `Input send failed` | Usually main-thread UDP (fixed with executor) or network/firewall |
| `Back pressed — stopping stream` | Clean shutdown |

**Doc:** `docs/companion-flutter.md`, `docs/streaming-native.md`.

---

## Data model (SwiftData)

- **`EmulatorProfile`** — name, paths, launch template, extensions, `preferScreenScraperCovers` (default `false` for migration).
- **`LibraryGame`** — title, `romPath`, optional emulator link, cover URLs/options JSON, `platformHint`, `librarySourceID`, `epicAppName`, sort order, play/metadata timestamps.
- **`GameFolderPath`** — folder path, purpose (games / covers / excludes), linked emulator.

---

## Help menu (app target)

- Replaces default Help group with topic buttons (RetroArch, RPCS3, orphan cleanup, **Keystrokes permission**). Implemented in `MacGameLibraryApp.swift`.

---

## Known constraints / pitfalls

- **ScreenScraper** quotas, threading, and API shape can change; search-by-name without `systemeid` may mismatch platforms.
- **SwiftData migration:** new non-optional attributes need defaults or optional types; a prior crash on `preferScreenScraperCovers` was fixed with `= false` on the property.
- **Full-library scrape** is synchronous per game with delays; large libraries take time and network.
- **Native streaming video (Android)** is verified: Annex-B H.264 over TCP **28766**, typically **~99%** frames rendered vs. received in export logs.
- **Audio** may stay silent while video works: phone retries `Audio subscribed` every ~3 s until Mac sends `PNA1`; check Mac console for `[PlayniteAudio] phone subscribed` and `sent packet #1`; allow UDP **28767** through the Mac firewall.
- **Touch** requires Mac **Accessibility** for **Mac Game Library** and UDP **28768** open; phone must log `Input UDP #1` (not `Input send failed`). Verified on Android; rebuild Mac app after Y-mapping changes.
- **Companion iOS** native video receiver is still limited; Android `PlayniteVideoActivity` is the reference client.
- Use the Mac’s **LAN IP** (e.g. `192.168.1.x`), not `127.0.0.1`, on the phone.

---

## Cross-reference

- **What changed lately:** `docs/source control log.md`
- **Credential setup detail:** `docs/metadata-setup.md`
- **Native streaming:** `docs/streaming-native.md`
- **Legacy Sunshine quickstart (optional):** `docs/streaming-quickstart.md`, `docs/streaming-setup.md`
- **Companion app:** `docs/companion-flutter.md`, `companion_app/README.md`
