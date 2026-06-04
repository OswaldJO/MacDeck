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

- **`PlayniteStreamHostManager`** — starts HTTP control (**28765**), TCP video (**28766**), UDP audio subscribe (**28767**), TCP audio downlink (**28769**), UDP input (**28768**); on stream start calls **`PlayniteLocalOutputMute`** to mute Mac default output; unmutes on stream stop or host stop.
- **`PlayniteStreamControlServer`** — pairing queue, stream start/stop; JSON includes `videoPort`, `audioPort`, `audioTcpPort`, `inputPort`.
- **`PlayniteVideoStreamServer`** — one TCP client; sends framed **`PNV1`** H.264 (Annex-B from `PlayniteH264Encoder`).
- **`PlayniteDisplayCapture`** — SCK display + **system audio** (`capturesAudio`); PCM converted to s16le (packed or planar stereo interleave when ScreenCaptureKit returns multiple buffers).
- **`PlayniteAudioStreamServer`** — phone sends **`PNAS`** on UDP **28767**; Mac streams **`PNA1`** PCM primarily over **TCP 28769** (4-byte little-endian length + frame); UDP downlink remains as fallback. Serial TCP send queue with subscribe ack (silent frames) on connect.
- **`PlayniteStreamInputServer`** — receives **`PNI1`** touch packets; **`PlayniteRemoteInputPlayback`** posts `CGEvent` pointer events (relative move, tap, drag). **`PNK1`** keyboard packets from mapped gamepad chords; **`PlayniteKeyboardPlayback`** maps Moonlight short key codes (Windows VK + `0x80` prefix) to macOS virtual keys, including **Option** (`0xA4` / `0xA5`) and **Command** (`0x5B` / `0x5C`).
- **`PlayniteLocalOutputMute`** — CoreAudio mute on default output device during an active stream; restores prior mute state afterward.
- **`StreamingView`** — LAN IP, port summary, Screen Recording + **Accessibility** status, **Test cursor on streamed display**, pairing approve/deny; notes that playback is on the phone and Mac speakers are muted while streaming.

### macOS permissions

| Permission | Purpose | UI name |
|------------|---------|---------|
| **Screen Recording** | Desktop video + system audio capture | Mac Game Library |
| **Accessibility** | Synthetic mouse move/click from phone touch | Mac Game Library (same list entry; not a separate “touch” item) |

Restart the Mac app after toggling Accessibility. Stream audio is **not** a separate item in **System Settings → Sound → Output**; it is captured and sent to the phone. While a stream is active, the Mac’s default output is **muted** so speakers stay quiet and the phone is the playback device (use phone **media** volume during a stream).

### Playnite stream ports

| Port | Protocol | Role |
|------|----------|------|
| 28765 | HTTP | Control — `playnite-stream/1`, pairing, stream start/stop |
| 28766 | TCP | Video — `PNV1` framed H.264 |
| 28767 | UDP | Audio subscribe — phone `PNAS` → Mac registers client; optional UDP `PNA1` fallback |
| 28769 | TCP | Audio downlink — length-prefixed `PNA1` PCM (primary path on Android) |
| 28768 | UDP | Input — phone `PNI1` normalized touch |

**Key types:** `StreamingView.swift`, `PlayniteStreamHostManager.swift`, `PlayniteStreamControlServer.swift`, `PlayniteVideoStreamServer.swift`, `PlayniteDisplayCapture.swift`, `PlayniteAudioStreamServer.swift`, `PlayniteLocalOutputMute.swift`, `PlayniteStreamInputServer.swift`, `PlayniteRemoteInputPlayback.swift`, `PlayniteStreamPorts.swift`, `AccessibilityPermission.swift`.

Setup: `docs/streaming-native.md`.

---

## Companion app (`companion_app/`)

Flutter shell (iOS + Android) for discovery, HTTP pairing with the native Mac host, and LAN streaming.

### Tabs

- **Settings** — Mac LAN IP; saved in `StreamingHostSettings`.
- **Hosts** — discover Mac via Playnite HTTP control plane.
- **Pairing** — device requests pairing; user approves on Mac **Streaming** tab.
- **Session** — **`StreamingBridge.startPlayniteStream`** → **Android** `PlayniteVideoActivity` (full-screen `SurfaceView` + `MediaCodec`). Passes `videoPort`, `audioPort`, `audioTcpPort`, `inputPort`, width/height from stream start response.

### Android native (Playnite video)

- **`PlayniteVideoActivity`** — TCP `PNV1` reader thread; codec pump on `HandlerThread`; decode profiles (Annex-B passthrough + `c2.android.avc.decoder` first).
- **`PlayniteAudioReceiver`** — prefers **TCP 28769** (length-prefixed `PNA1`); falls back to UDP after `PNAS` subscribe on **28767**. Separate network and playback threads; `AudioTrack` buffer ~150 ms with low-latency mode; small PCM queue to avoid blocking the socket reader.
- **`PlayniteInputSender`** — relative cursor, tap/drag gestures on the video `SurfaceView` → UDP `PNI1` to Mac (background thread). Tunables in **Settings → Controllers → Touchpad (stream view)**. Primary pointer path during native stream (no Moonlight mouse-emulation toggle).
- **`PlayniteRemoteInputPlayback`** (Mac) — maps normalized touch to the **captured display** frame; Y uses `minY + ny × height` so finger-up on the phone moves the cursor up on the Mac.
- **`PlayniteStreamLog`** — writes `playnite_stream.log` under app files dir for export/debug.
- **Appearance (companion)** — **Settings → Appearance**: primary text color presets (White, Purple, Lavender, Blue, Mint, Peach) or **Custom** RGB sliders. Persisted in `companion.appearance.primaryTextColor`; `CompanionApp` rebuilds `CompanionTheme.dark(primaryText:)` when the value changes (`CompanionAppearanceSettings.themeRevision`).
- **Stream shortcuts (Android)** — **Settings → Shortcuts**: named keyboard chords (multi-key). Default **Close app** = **Command + Q** (macOS quit); upgrades a stored ⌘⌥Esc default on launch. Stored in `stream.shortcuts` SharedPreferences; native overlay reads the same JSON. Notification **Shortcuts** action (right of **Controller**) opens a picker over the live stream; tapping a row sends the chord to the Mac (`PlayniteKeyboardSender`, press then release). If the video view is not open but the host stream is still active, the app shows a Flutter picker and uses `fireStreamShortcut` on the method channel.
- **Controller mapping (Android)** — **Controller** tab: list of gamepad elements → keyboard **chords** (multi-select from `kMoonlightKeyboardKeys`, including Mac **Option** and **Command**), optional **Link gamepad** per element, four macro slots. Bindings JSON is passed into `PlayniteVideoActivity` and applied by **`PlayniteGamepadMapping`** + **`PlayniteKeyboardSender`** (`PNK1` on UDP **28768**). While a stream is active, the system notification **Controller** action opens a semi-transparent overlay on the video for quick gamepad linking; **Stop** ends the session without reopening the app.
- **`PlayniteStreamNotificationHelper`** — ongoing notification channel `playnite_stream_session` (DEFAULT importance) for stream controls when the native host is active (including after Back leaves the video view).

**Key types:** `streaming_bridge.dart`, `playnite_host_client.dart`, `moonlight_key_codes.dart`, `controller_mapping_section.dart`, `PlayniteVideoActivity.kt`, `PlayniteAudioReceiver.kt`, `PlayniteInputSender.kt`, `PlayniteKeyboardSender.kt`, `PlayniteGamepadMapping.kt`, `PlayniteStreamNotificationHelper.kt`, `PlayniteStreamProtocols.kt`, `PlayniteKeyboardPlayback.swift`.

### Keyboard chord codes (companion → Mac)

Companion labels use Moonlight’s Windows virtual-key codes (`moonlightKeyCode = (0x80 << 8) | vk`). Mac playback maps the low byte to `CGKeyCode`. Mac-specific modifiers:

| UI label | Windows VK | Mac key |
|----------|------------|---------|
| Option | `0xA4` | Left Option |
| Option (right) | `0xA5` | Right Option |
| Command | `0x5B` | Left Command |
| Command (right) | `0x5C` | Right Command |

Legacy bindings that used **Alt** (`0x12`) still map to left Option on the Mac.

### Phone export log (what to look for)

| Log line | Meaning |
|----------|---------|
| `Rendered frame #N` | Video path healthy |
| `Audio TCP connected` | Phone opened TCP downlink on **28769** |
| `Audio packet #N` | `PNA1` frames received and queued for playback |
| `AudioTrack started … buf=…` | Playback started; `buf` should be tens of KB, not multi-MB |
| `Audio subscribed` | UDP fallback path only (TCP preferred) |
| `Input UDP #1` | Touch packets leaving the phone |
| `Input send failed` | Network/firewall or socket error on input port |
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
- **Native streaming (Android)** is verified: video over TCP **28766** (~99% rendered vs. received); audio over TCP **28769** with Mac output muted during stream; touch over UDP **28768** with Accessibility granted.
- **Audio troubleshooting:** expect `Audio TCP connected`, then `Audio packet #1` and `AudioTrack started` with a modest buffer size. Mac console: `[PlayniteAudio] phone connected (TCP audio)`, `muted Mac default output`, `sent TCP audio frame #N`. If silent, check phone **media** volume and Mac firewall for **28767** / **28769**.
- **Touch** requires Mac **Accessibility** for **Mac Game Library**; phone should log `Input UDP #1`. Rebuild Mac app after input-mapping changes.
- **Companion iOS** native video receiver is still limited; Android `PlayniteVideoActivity` is the reference client.
- Use the Mac’s **LAN IP** (e.g. `192.168.1.x`), not `127.0.0.1`, on the phone.

---

## Cross-reference

- **What changed lately:** `docs/source control log.md`
- **Credential setup detail:** `docs/metadata-setup.md`
- **Native streaming:** `docs/streaming-native.md`
- **Legacy Sunshine quickstart (optional):** `docs/streaming-quickstart.md`, `docs/streaming-setup.md`
- **Companion app:** `docs/companion-flutter.md`, `companion_app/README.md`
