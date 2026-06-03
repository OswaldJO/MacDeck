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

## Streaming tab (Sunshine host)

Playnite Mac acts as a **Sunshine streaming host** so a phone/tablet can pair over the Moonlight protocol and stream the Mac desktop (and, later, launched games) over the LAN.

### Host lifecycle

- **`SunshineHostManager`** — ensures Sunshine is installed/located (`SunshineBinaryLocator`, Homebrew or staged binary), starts/stops the process, surfaces status in the UI.
- **`StreamingView`** — shows **Running and reachable**, **LAN IP** (`LocalNetworkAddress`), binary path, **Restart streaming host**, and pairing controls.
- Credentials for the Sunshine **control plane** live in `StreamingHostSettings` (dev builds; used by `SunshineControlPlaneClient` with `SunshineTLSDelegate` for HTTPS to port **47990**).
- **macOS requirement:** the Sunshine process must have **Screen & System Audio Recording** for the actual binary (typically `/opt/homebrew/opt/sunshine/bin/sunshine`). Without it, `~/.config/sunshine/sunshine.log` shows `No screen capture permission!` and Moonlight `/launch` returns **503** (“Failed to initialize video capture/encoding”). **Restart Sunshine after changing permissions.** Only one Sunshine instance should run (duplicate starts can fail RTSP bind on **48010**).
- **Reachability caveat:** “Running and reachable” means the control plane on **47990** responds; it does not guarantee encoders or capture are healthy — use the Sunshine log before streaming from a client.

### Pairing (Mac side)

- **`StreamingPairingSession`** — phases: `idle` → `awaiting` (10-minute window) → `paired(deviceName)`.
- User flow: companion starts pairing first; Mac **Start pairing** → enter same 4-digit PIN → **Submit PIN to Sunshine** (`POST /api/pin`).
- After PIN accept, session polls **`fetchPairedClientNames()`** until a new client name appears (baseline snapshot taken at pairing start).
- **`InAppControlPlaneClient`** — alternate/test control-plane implementation; production path uses **`SunshineControlPlaneClient`**.

**Key types:** `StreamingView.swift`, `StreamingPairingSession.swift`, `SunshineControlPlaneClient.swift`, `SunshineHostManager.swift`, `StreamingHostSettings.swift`, `ControlPlanePorts.swift`.

### Moonlight ports (defaults)

| Port | Role |
|------|------|
| 47989 | HTTP — `/serverinfo`, `/pair`, `/launch` (companion uses HTTPS **47984** for launch) |
| 47984 | HTTPS — `pairchallenge`, `/launch`, mTLS |
| 47990 | Sunshine control plane — `/api/pin`, `/api/clients/list` |
| 48010 | RTSP (session) |
| 47998 / 48000 / 47999 | Video / audio / control (UDP during stream) |

Setup and staging: `docs/streaming-quickstart.md`, `docs/streaming-setup.md`, `docs/streaming-bundled-host.md`.

---

## Companion app (`companion_app/`)

Flutter app (iOS + Android) for discovery, pairing, and LAN streaming to the Mac Sunshine host.

### Tabs

- **Settings** — Mac LAN IP (no port suffix); saved in `StreamingHostSettings` (SharedPreferences).
- **Hosts** — `discoverHosts()` via HTTP `serverinfo` on configured IP; **Paired** when `PairingStateStore` + HTTPS `applist` probe succeed.
- **Pairing** — **`SunshinePairingService.pair()`**; status is separate from host discovery (`home_page.dart`).
- **Session** — **`MoonlightStreamService`** resolves Desktop app id from `applist`, then **`StreamingBridge.startStream`** with the same **`StreamLaunchConfig`** map on both platforms. Client cert/key from Dart pairing are synced into each native Moonlight identity store before launch. **Android:** **`StreamLaunchHelper`** → vendored **`Game`** activity (`moonlight-stream`). **iOS:** **`PlayniteStreamLaunchHelper`** → modal **`StreamFrameViewController`** (`PlayniteMoonlight` pod). **Android** E2E verified; **iOS** builds and launches native stream UI (device smoke test pending).

### Pairing (companion side)

Port of moonlight-android **`PairingManager`** logic in Dart:

1. Generate/load persistent RSA client cert (`PairingCryptoStore`).
2. Long-poll **`getservercert`** with salt + PIN until Mac submits matching PIN.
3. AES challenge exchange over HTTP `/pair`.
4. **`clientpairingsecret`** — client cert registered with Sunshine.
5. HTTPS **`pairchallenge`** — `SecurityContext` with client cert; server cert pinned from `plaincert`; hostname mismatch skipped when connecting by LAN IP (same as Moonlight).

Fixed Moonlight **`uniqueid`**: `0123456789ABCDEF`. Device name in pair URL: `roth`.

**Key types:** `sunshine_pairing_service.dart`, `moonlight_stream_service.dart`, `streaming_bridge.dart`, `pairing_crypto_store.dart`, `pairing_state_store.dart`, `streaming_host_settings.dart`, `home_page.dart`, `StreamLaunchHelper.kt`.

### Android native (Moonlight)

- **`moonlight-stream`** — vendored moonlight-android library module; `build.gradle.kts` patches `AndroidCryptoProvider` for API 28+ (platform `CertificateFactory` / `KeyFactory`, no BC provider on load).
- **`StreamLaunchHelper`** — builds `PcView.Computer` + `NvApp` (Desktop), writes `client.crt` / `client.key` / `uniqueid`, starts `com.limelight.Game`.

### Correct pairing order

1. Phone: **Pairing → Start pairing** — wait for **Waiting for Mac…** (keep app in foreground).
2. Mac: **Streaming → Start pairing** — same PIN → **Submit PIN to Sunshine**.
3. Phone completes HTTPS step; both sides show **Paired**.

**Doc:** `docs/companion-flutter.md`.

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
- **Streaming pairing** requires phone **Start pairing before** Mac PIN submit; backgrounding the companion during long-poll can stall until reconnect/retry. Mac “PIN accepted” only means Sunshine got the PIN — the phone must still finish the HTTP/HTTPS handshake.
- **Android streaming** needs Mac Sunshine with Screen Recording + working encoders (`Found H.264 encoder` in log). Typical failures: **503** (no capture permission / no encoder), **unexpected end of stream** (host down or broken HTTPS), port **48010** in use (second Sunshine instance).
- **Companion Session on iOS** does not decode video yet; Android Desktop stream is the supported video path today.
- **Sunshine** must be reachable on LAN (firewall, same Wi‑Fi, UDP for media); companion must not use `127.0.0.1` for the Mac IP.

---

## Cross-reference

- **What changed lately:** `docs/source control log.md`
- **Credential setup detail:** `docs/metadata-setup.md`
- **Streaming quickstart:** `docs/streaming-quickstart.md`
- **Streaming setup / bundled host:** `docs/streaming-setup.md`, `docs/streaming-bundled-host.md`
- **Companion app:** `docs/companion-flutter.md`, `companion_app/README.md`
