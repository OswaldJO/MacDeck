# Mac Game Library — Features and Inner Workings

This document describes **how the app behaves today** and **where implementation lives**. For a short, commit-adjacent summary of recent changes, see `source control log.md`.

---

## Product shape

- **SwiftUI** app with a tabbed shell: **Library**, **Emulators**, **Paths**, **Streaming**. Controller mapping is **companion-only** (no **Controllers** tab on the Mac app).
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

- `LibraryGameInspectorView`: display name; for emulator-linked games — **File** (basename) and **Path** (full `romPath`, link-styled; tap opens **Finder** via `NSWorkspace.activateFileViewerSelecting`); for **Mac** entries with no emulator — editable game path + **Choose Game…**.
- **Multi-disc set:** link with suggestions or **Link with other discs…** sheet (`DiscGroupLinkSheet`); list linked discs with ▲/▼ reorder; **Reset order from filenames**; **Unlink this disc**. Linked discs share cover art and ScreenScraper `gameid`/`systemeid`; changes propagate via `DiscGroupService.propagateSharedState`.
- Cover art: choose file, ScreenScraper manual search, reorder detected covers, set primary, clear.

Grid tiles show a **Disc N** badge when the game is in a linked set and a disc number is parsed from the path/title.

**Key types:** `RootView.swift`, `LibraryGame.swift`, `DiscGroupService.swift`, `DiscGroupLinkSheet.swift`.

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
- **Toggle:** *Auto-link multi-disc games on scan* — `EmulatorProfile.autoLinkMultiDiscGames` (default `false`). After each **Scan Paths**, `DiscGroupService.autoLinkAllEnabledEmulators` clusters games on that emulator with the same normalized base title (same logic as manual link suggestions) and links sets of 2+; `ScanSummary.autoLinkedDiscSets` reports count.

**Key types:** `PathsView.swift`, `GameFolderPath.swift`, `GamePathScanner.swift`, `DiscGroupService.swift`.

### RPCS3 / PS3 folder scanning

When a configured **game folder** belongs to an RPCS3 (or PS3-style) emulator, `GamePathScanner` uses **folder-aware** import instead of treating every file under `dev_hdd0/game` as a ROM:

| Detection | Behavior |
|-----------|----------|
| **Title folder** | Subfolder with `PARAM.SFO` and `USRDIR/EBOOT.BIN` (RPCS3 install) or `PS3_GAME/USRDIR/EBOOT.BIN` (disc dump layout). |
| **Title** | Read from `PARAM.SFO` (`TITLE`, else `TITLE_ID`, else folder name). |
| **Launch path** | Stored `romPath` is the **`EBOOT.BIN`** file; `GameLauncher` substitutes it into the emulator’s `{ImagePath}` / `{rom}` template (RPCS3 catalog default: `"{ImagePath}"`). |
| **Category filter** | Only **`GD`** (disc install) and **`HG`** (PSN/HDD install) folders are imported; patch/DLC/UCC/APPDATA-style siblings are skipped. |
| **File scan** | For PS3-style emulators with no per-emulator extension list, only **`.iso`** files are imported at file depth — avoids pulling thousands of `.bin` assets from `dev_hdd0/game`. |

**Typical path:** `~/Library/Application Support/rpcs3/dev_hdd0/game` assigned to the RPCS3 `EmulatorProfile` on the **Paths** tab.

**Rescan:** If a library row already exists for the same normalized `EBOOT.BIN` path, scan **updates the title** from `PARAM.SFO` (and can reassign emulator if the path moved profiles). Counts toward `ScanSummary.reassigned`.

**Limits:** Retail **GD** HDD folders often contain **game data only** (no `USRDIR/EBOOT.BIN`); RPCS3 boots those from the Blu-ray image or its internal list, not from an EBOOT path in `dev_hdd0/game`. Import those titles via **PS3 `.iso`** paths (or manual add) if you want them in the library grid.

**Help:** App menu **RPCS3 Game not launching** — if RPCS3 is already open, close it before launching a different PS3 game from the library (single-instance / open-document behavior).

**Key implementation:** `GamePathScanner.ps3LaunchPathIfPresent`, `ps3Metadata` / `parsePS3SFO`, `shouldIncludePS3Folder`, `isPS3StyleEmulator`.

---

## Metadata and ScreenScraper

- **IGDB removed.** Remote metadata uses **ScreenScraper API v2** (`https://api.screenscraper.fr/api2/…`).
- **Credentials:** `MetadataCredentials` — `devid` / `devpassword` required; `ssid` / `sspassword` optional. Persisted in `UserDefaults` (see `docs/metadata-setup.md`).
- **Matching waterfall** (`MetadataService`, per game):
  1. Pinned `screenScraperGameId` + `screenScraperSystemId` on `LibraryGame` (if set).
  2. **`jeuInfos.php`** hash lookup (`RomFingerprint`: MD5/CRC32/SHA1, `.cue`/`.m3u` payload, PS3 folder `dossier`) — requires resolved **`systemeid`**.
  3. **`jeuInfos.php`** exact filename (`romnom` + size + `romtype`).
  4. **`jeuRecherche.php`** fuzzy search with query variants (`RomTitleNormalizer`, `.hack` `//` forms, roman → arabic numerals).
  5. Auto-select from ambiguous set (user toggle) or `ScreenScraperDisambiguationCoordinator` sheet.
- **Platform resolution** before scrape: `EmulatorProfileLookup` (SwiftData relationship or `emulatorIDString`) → `EmulatorPlatformResolver`; fallback `MetadataSystemResolver` (`platformHint`, Epic → PC **135**); fallback **`RomPathPlatformResolver`** (longest matching **Paths** game-folder root). Scrape logs include `emulatorSystemeid=`.
- **Title safety:** `pickTitleIsCompatible` blocks wrong-platform fuzzy picks; Part/Vol numbers optional when subtitle matches (`.hack Part 1` ↔ `.hack//Infection`). Scraped title applied only when compatible (hash/exact always apply).
- **Background fetcher:** `MetadataBackgroundFetcher` — periodic batches; **schedule extra** after scans; full library scrape from Screen Scrapper sidebar (`scrapeAllNow`). Session logs: `playnite-scrape-*.log` in Downloads. **`clearAllScrapedMetadata`** wipes covers, ScreenScraper IDs, disambiguation queue.
- **Covers:** `CoverImageCache` disk cache; validates decoded `NSImage` before save. Local folder discovery first; remote appended to `coverImageOptions`; primary respects `preferScreenScraperCovers`. **Multi-disc:** cover + ScreenScraper IDs propagate to siblings in the same `discGroupIDString`.

**Key types:** `MetadataService.swift`, `ScreenScraperClient.swift`, `RomFingerprint.swift`, `RomTitleNormalizer.swift`, `MetadataSystemResolver.swift`, `RomPathPlatformResolver.swift`, `MetadataBackgroundFetcher.swift`, `ScreenScraperLibraryView.swift`, `ScreenScraperDisambiguationCoordinator.swift`, `CoverImageCache.swift`.

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

- **`PlayniteStreamHostManager`** — in **`ensureReady()`** starts HTTP control (**28765**) and keeps transport listeners bound for the life of the host: TCP video (**28766**), UDP audio subscribe (**28767**), TCP audio downlink (**28769**), UDP input (**28768**). A companion session only starts/stops **capture** (`video.startCapture` / `video.stopStream`); listeners are torn down only on host **`stop()`** / **`restartHost()`**. Stream start/stop is serialized on **`streamOperationChain`**; **`beginVideoStream`** ends any prior capture first, then starts a new capture task. On stream start, **`PlayniteLocalOutputMute`** mutes Mac default output; unmutes on stream stop or host stop. **`isVideoStreaming`** mirrors **`videoStreaming`** on the control API for companion preflight. **`stopActiveVideoStream()`** (Streaming tab) ends capture if the phone quit without **`stream/stop`**.
- **`PlayniteStreamControlServer`** — pairing queue (approve / deny / **cancel**), stream start/stop; **`POST /playnite/v1/stream/start`** and **`POST /playnite/v1/stream/stop`** return **200** immediately and run handlers in a background **`Task`** (phone connects to ports that are already listening). JSON includes `videoPort`, `audioPort`, `audioTcpPort`, `inputPort`, and **`videoStreaming`** on **`GET /playnite/v1/status`** (companion polls until false when clearing a stale capture session).
- **`PlayniteVideoStreamServer`** — one TCP client; sends framed **`PNV1`** H.264 (Annex-B from `PlayniteH264Encoder`).
- **`PlayniteDisplayCapture`** — SCK display + **system audio** (`capturesAudio`); PCM converted to s16le (packed or planar stereo interleave when ScreenCaptureKit returns multiple buffers).
- **`PlayniteAudioStreamServer`** — phone sends **`PNAS`** on UDP **28767**; Mac streams **`PNA1`** PCM primarily over **TCP 28769** (4-byte little-endian length + frame); UDP downlink remains as fallback. Serial TCP send queue with subscribe ack (silent frames) on connect.
- **`PlayniteStreamInputServer`** — receives **`PNI1`** touch packets; **`PlayniteRemoteInputPlayback`** posts `CGEvent` pointer events (relative move, tap, drag). **`PNK1`** keyboard packets from gamepad mapping and stream shortcuts; **`PlayniteKeyboardPlayback`** maps Moonlight short codes (Windows VK in the low byte) to US ANSI **`CGKeyCode`** via Carbon `kVK_ANSI_*` (letters are **not** `vk - 0x41`). Modifiers (**Shift**, **Control**, **Option** `0xA4`/`0xA5`, **Command** `0x5B`/`0x5C`) update **`CGEvent.flags`** only; chord keys (e.g. **Q** for quit) are posted with those flags held. Requires **Accessibility**; logs `[PlayniteInput] PNK1` / `keyboard` lines to Console when packets arrive.
- **`PlayniteLocalOutputMute`** — CoreAudio mute on default output device during an active stream; restores prior mute state afterward.
- **`StreamingView`** — LAN IP, port summary, Screen Recording + **Accessibility** status, **Test cursor on streamed display**, pairing approve/deny; when **`isVideoStreaming`**, **Stop active stream** tears down capture/transport; notes that playback is on the phone and Mac speakers are muted while streaming.

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

**Key types:** `StreamingView.swift`, `PlayniteStreamHostManager.swift`, `PlayniteStreamControlServer.swift`, `PlayniteVideoStreamServer.swift`, `PlayniteDisplayCapture.swift`, `PlayniteAudioStreamServer.swift`, `PlayniteLocalOutputMute.swift`, `PlayniteStreamInputServer.swift`, `PlayniteRemoteInputPlayback.swift`, `PlayniteKeyboardPlayback.swift`, `PlayniteStreamPorts.swift`, `AccessibilityPermission.swift`.

Setup: `docs/streaming-native.md`.

---

## Companion app (`companion_app/`)

Flutter shell (iOS + Android) for discovery, HTTP pairing with the native Mac host, and LAN streaming.

### Tabs

- **Hosts** — discover Mac via Playnite HTTP control plane; **Add IP** (outlined); **Pair** / **Cancel** while a pairing request is pending (`PairingCancellation` + **`POST /playnite/v1/pair/cancel`** on the Mac).
- **Session** — **`PlayniteHostClient.startStream`**: if status shows **`videoStreaming: true`**, sends **`stream/stop`** and polls until idle; then **`POST /playnite/v1/stream/start`** (single request; Mac returns ports immediately). **`StreamingBridge.startPlayniteStream`** → **Android** `PlayniteVideoActivity` (full-screen `SurfaceView` + `MediaCodec`). **Back** sets **`leaveViewerWithoutMacStop`** and closes the viewer **without** Mac **`stream/stop`** (capture can keep running; listeners stay up). **Stop** (Session tab) runs **`PlayniteStreamStopCoordinator`** + **`ensureHostStreamStopped`** + idle poll. **Resume stream view** when **`hostStreamActive`** and viewer closed → native **`resumeStream`**. **Start Desktop 1080p60** after **Stop** (or when idle) for a new capture session. Repeat **Stop → Start** works without rebinding Mac ports (verified Jun 4 2026).
- **Controller** — per-button **keyboard chords**, **Link gamepad** (button, D-pad hat, or stick direction for the slot being linked), **Assign Swap** (toggle mouse mode; not **A**, **B**, **X**, or **left stick** directions), and **Touchpad (stream view)** tunables. Mappable elements include **left/right stick up/down/left/right** (axis-held chords, not L3/R3). Bindings persist in **`StreamControllerMappingStore`**; optional **`targetAction: toggleSwap`**. Phone **media** volume keys work in the Flutter shell and stream view (`volumeControlStream = STREAM_MUSIC`).
- **Settings** — **Appearance**, **Notification Swap button** (behavior + **Swap stick cursor speed**), **Shortcuts** (named chords), Mac LAN IP (`StreamingHostSettings`).

### Android native (Playnite video)

- **`PlayniteVideoActivity`** — TCP `PNV1` reader thread; codec pump on `HandlerThread`; decode profiles (Annex-B passthrough + `c2.android.avc.decoder` first). **`volumeControlStream`**: media volume. Gamepad motion: if **Swap** on, **`PlayniteGamepadMouseSender`** runs first (left stick → **`PNI1`** cursor); then **`PlayniteGamepadMapping`** (triggers, hat D-pad, analog stick directions). Keys: **Back** → **`GamepadLinkCapture`** → mapping (including **toggleSwap**) → Swap mouse for **A/B/X** only → swallow other gamepad keys. **`onDestroy`**: Mac **`stream/stop`** only when the activity did **not** exit via **Back** (`leaveViewerWithoutMacStop`).
- **`MainActivity`** (Flutter shell) — **`GamepadInputFilter`** swallows gamepad keys/motion outside the stream viewer; **volume** keys pass through. **`GamepadLinkCapture`** during link (with target **`elementId`**). **`onDestroy`**: best-effort Mac stop if a stream was still marked active.
- **`PlayniteAudioReceiver`** — prefers **TCP 28769** (length-prefixed `PNA1`); falls back to UDP after `PNAS` subscribe on **28767**. Separate network and playback threads; `AudioTrack` buffer ~150 ms with low-latency mode; small PCM queue to avoid blocking the socket reader.
- **`PlayniteInputSender`** — relative cursor, tap/drag gestures on the video `SurfaceView` → UDP `PNI1` to Mac (background thread). Tunables in **Settings → Controllers → Touchpad (stream view)**. Primary pointer path during native stream (no Moonlight mouse-emulation toggle).
- **`PlayniteRemoteInputPlayback`** (Mac) — maps normalized touch to the **captured display** frame; Y uses `minY + ny × height` so finger-up on the phone moves the cursor up on the Mac.
- **`PlayniteStreamLog`** — writes `playnite_stream.log` under app files dir for export/debug.
- **Appearance (companion)** — **Settings → Appearance**: primary text color presets (White, Purple, Lavender, Blue, Mint, Peach) or **Custom** RGB sliders. Default on fresh install is **Mint** (`#80CBC4`). Persisted in `companion.appearance.primaryTextColor`; `CompanionApp` rebuilds `CompanionTheme.dark(primaryText:)` when the value changes (`CompanionAppearanceSettings.themeRevision`). The color drives **`outlinedButtonTheme`** (Hosts **Add IP**, **Pair**, **Cancel**) and **`chipTheme`** (mapping/shortcut key chips: transparent fill, matching outline and label).
- **Stream shortcuts (Android)** — **Settings → Shortcuts**: named keyboard chords (multi-key). Default **Close app** = **Command + Q** (macOS quit foreground app); upgrades a stored ⌘⌥Esc default on launch. Stored in `stream.shortcuts` SharedPreferences; native overlay reads the same JSON. **`PlayniteStreamSession.keyboardSender`** is shared for the whole stream (survives leaving `PlayniteVideoActivity` with Back). Notification **Shortcuts** opens a picker on the video overlay or, if the viewer is closed, a Flutter sheet + `fireStreamShortcut`. Chords are sent as **`PNK1`** UDP on **28768** (~140 ms hold). Verified Jun 3 2026 with Mac **`PlayniteKeyboardPlayback`** VK table fix.
- **Controller mapping (Android)** — **Controller** tab: elements → **chords**, **Link gamepad**, or **Assign Swap**. Includes **left/right stick** cardinal directions (held while deflected; separate from L3/R3). **Link** waits for the control matching the row (e.g. push **right stick up** for **Right stick up**; D-pad rows accept hat or stick). Many pads report D-pad as **`AXIS_HAT_X/Y`** — **`handleHatDpad`** sends chords without blocking Swap when hat is centered. Manual links use synthetic key codes in **`GamepadKeyCodes`** for stick directions. **A / B / X** and **left stick** directions cannot **Assign Swap**. **`PlayniteGamepadMapping`**: keys, triggers, hat, sticks; **`toggleSwap`** on each **ACTION_DOWN** (no stuck latch). Bindings reload from prefs in the stream view; **`PlayniteKeyboardSender`** survives **Back**.
- **Swap mouse mode (Android)** — Notification **Swap** or **Assign Swap** toggles **`swapMouseModeActive`**. While on: left stick → cursor (**Swap stick cursor speed** in Settings); **A** click, **B** right-click, **X** drag; other mappings (Y, bumpers, right stick, D-pad chords, etc.) still fire. **`releaseAllKeys`** on toggle off avoids stuck modifiers on the Mac.
- **Stream notification (Android)** — channel **`playnite_stream_session_v2`**. Custom layout: row 1 **Stop | Swap**, row 2 **Controller | Shortcuts**; `addAction` fallback on OEMs that collapse custom views. **`PlayniteStreamNotificationReceiver`**: **Stop** → **`PlayniteStreamStopCoordinator.stopSession`** (deactivate session, dismiss notification, finish **`PlayniteVideoActivity`** or end log file, background Mac **`stream/stop`**, optional Flutter **`notifyFlutterStreamStoppedExternally`**); **Swap** → **`PlayniteStreamSwapActions.toggle`**; **Controller** / **Shortcuts** → mapping overlay or shortcut picker. No `CLOSE_SYSTEM_DIALOGS` broadcast (crash fix). Best-effort shade collapse after the action.

**Key types:** `playnite_host_client.dart`, `streaming_bridge.dart`, `stream_controller_mapping_store.dart`, `stream_touch_settings.dart`, `gamepad_elements.dart`, `gamepad_swap_toggle.dart`, `controller_mapping_section.dart`, `PlayniteVideoActivity.kt`, `MainActivity.kt`, `GamepadInputFilter.kt`, `GamepadLinkCapture.kt`, `PlayniteGamepadMouseSender.kt`, `PlayniteGamepadMapping.kt`, `GamepadKeyCodes`, `PlayniteStreamStopCoordinator.kt`, `PlayniteStreamSwapActions.kt`, `PlayniteStreamNotificationHelper.kt`, `PlayniteStreamSession.kt`, `PlayniteKeyboardPlayback.swift`, `PlayniteStreamHostManager.swift`, `PlayniteStreamControlServer.swift`, `GamepadElementCatalog.swift`.

### Keyboard chord codes (companion → Mac)

Companion labels use Moonlight’s Windows virtual-key codes (`moonlightKeyCode = (0x80 << 8) | vk`). Mac playback maps the low byte through a **US ANSI VK → `CGKeyCode`** table (see `PlayniteKeyboardPlayback.swift`). Example: **Q** is Windows `0x51` → Mac key code **12** (`kVK_ANSI_Q`), not `0x51 - 0x41`. Mac-specific modifiers:

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
| `Shortcut "…" (Command + Q) → host:28768` | User fired a stream shortcut |
| `Keyboard PNK1 down key=0x805b` | Modifier/key down (e.g. Command) |
| `Keyboard PNK1 down key=0x8051` | Key down (e.g. Q) |
| `Input send failed` / `Keyboard send failed` | Network/firewall or socket error on input port |
| `Back pressed — leaving stream view` | Video UI closed; host stream may stay active until **Stop** |
| `Swap on` / `Swap off` (toast) | Notification or mapped button toggled Swap mouse mode |
| `Gamepad map leftStickUp` / hat | Stick or D-pad chord down/up to Mac |
| `viewer closed` / `activity destroyed` | Back left stream running; destroy may stop Mac if not viewer-only exit |
| `Pairing cancelled` / `Cancelling pairing` | User tapped **Cancel** on Hosts |

**Doc:** `docs/companion-flutter.md`, `docs/streaming-native.md`.

---

## Data model (SwiftData)

- **`EmulatorProfile`** — name, paths, launch template, extensions, `preferScreenScraperCovers`, `autoLinkMultiDiscGames` (both default `false` for migration).
- **`LibraryGame`** — title, `libraryDisplayName`, `romPath`, optional emulator link (`emulatorIDString` + relationship), cover URLs/options JSON, `platformHint`, `screenScraperGameId` / `screenScraperSystemId`, `screenScraperSelectionSkipped`, `discGroupIDString`, `discGroupOrder`, `librarySourceID`, `epicAppName`, `sortOrder`, play/metadata timestamps.
- **`GameFolderPath`** — folder path, purpose (games / covers / excludes), linked emulator.

---

## Help menu (app target)

- Replaces default Help group with topic buttons (RetroArch, RPCS3, orphan cleanup, **Keystrokes permission**). Implemented in `MacGameLibraryApp.swift`.

---

## Known constraints / pitfalls

- **RPCS3 `dev_hdd0/game`:** Assign the folder to the **RPCS3** emulator profile (not a generic multi-system profile) so folder import and ISO-only file rules apply. After scanner fixes, run **Scan Paths** to rename stale **EBOOT** entries. PSN/HDD (**HG**) installs need `USRDIR/EBOOT.BIN`; disc **GD** data folders without EBOOT are not launchable from this path alone.
- **ScreenScraper** quotas, threading, and API shape can change. Without resolved **`systemeid`**, hash lookup is skipped and fuzzy search may pick wrong consoles (DS/Xbox/NES) or return `no_match`. Run **Scan Paths** so `RomPathPlatformResolver` can infer platform from folder roots; check scrape log for `emulatorSystemeid=nil`.
- **Multi-disc auto-link** uses normalized base titles — enable per emulator on **Paths**; manual link/unlink still available in inspector.
- **SwiftData migration:** new non-optional attributes need defaults or optional types; a prior crash on `preferScreenScraperCovers` was fixed with `= false` on the property.
- **Full-library scrape** is synchronous per game with delays; large libraries take time and network.
- **Native streaming (Android)** is verified: video over TCP **28766** (~99% rendered vs. received); audio over TCP **28769** with Mac output muted during stream; touch over UDP **28768** with Accessibility granted.
- **Audio troubleshooting:** expect `Audio TCP connected`, then `Audio packet #1` and `AudioTrack started` with a modest buffer size. Mac console: `[PlayniteAudio] phone connected (TCP audio)`, `muted Mac default output`, `sent TCP audio frame #N`. If silent, check phone **media** volume and Mac firewall for **28767** / **28769**.
- **Touch** requires Mac **Accessibility** for **Mac Game Library**; phone should log `Input UDP #1`. Rebuild Mac app after input-mapping changes.
- **Keyboard shortcuts** require the same **Accessibility** grant; phone logs `Keyboard PNK1`; Mac Console shows `[PlayniteInput] PNK1` / `keyboard`. Rebuild Mac app after `PlayniteKeyboardPlayback` changes.
- **Stream notification** on some OEMs may still collapse custom layouts; two-row inline buttons + `addAction` fallback are both present. Do not rely on `CLOSE_SYSTEM_DIALOGS` from the app (blocked on modern Android).
- **Swap stick sensitivity** is independent of touchpad **Cursor speed**; raise Swap stick speed in **Settings** if the cursor feels too slow after fixing inversion (stick up = cursor up on Mac).
- **Companion iOS** native video receiver is still limited; Android `PlayniteVideoActivity` is the reference client.
- Use the Mac’s **LAN IP** (e.g. `192.168.1.x`), not `127.0.0.1`, on the phone.

---

## Cross-reference

- **What changed lately:** `docs/source control log.md`
- **Credential setup detail:** `docs/metadata-setup.md`
- **Native streaming:** `docs/streaming-native.md`
- **Legacy Sunshine quickstart (optional):** `docs/streaming-quickstart.md`, `docs/streaming-setup.md`
- **Companion app:** `docs/companion-flutter.md`, `companion_app/README.md`
