This log will change with every commit in version control.

The purpose of this is to give a brief description of what happened since the last commit.

For the **living product and architecture handbook**, see `Features and Inner Workings.md`.

---

current release: 1  

## Updates
- **Native Playnite streaming (Android video verified, Jun 3 2026):** Mac **in-app host** (ScreenCaptureKit + H.264, no Sunshine) — companion opens **`PlayniteVideoActivity`**, TCP **`PNV1`** on **28766**, Annex-B + `c2.android.avc.decoder`. Latest phone log: **913 frames received / 908 rendered** (~34 s), clean stop via Back. Ports: control **28765**, video **28766**, audio **28767**, input **28768**.
- **Touch (working on Android):** UDP `PNI1` on background thread + Mac **Accessibility** — finger moves Mac cursor during native stream. Fixed **inverted Y** (`PlayniteRemoteInputPlayback`: use `minY + ny × height` so swipe-up on phone moves cursor up on Mac). Removed companion **Settings → Mouse emulation** toggle (direct touch replaces left-stick mouse emulation for native `PlayniteVideoActivity`).
- **Audio (still open):** Phone logs **`Audio subscribed`** every ~3 s (retry) but never **`First audio packet`** / **`AudioTrack started`** — Mac not delivering `PNA1` yet (ScreenCaptureKit audio often uses **AudioBufferList**; fix merged into `PlayniteDisplayCapture`). Audio does **not** appear in macOS **Sound → Output** (network PCM to phone, not a virtual output device).
- **Streaming (legacy Sunshine path, pre-native host):** Companion Moonlight `/launch` path still documented in older notes; current default is native host above.
- **Streaming (Sunshine host):** **Streaming** tab starts and monitors Sunshine via `SunshineHostManager`; shows LAN IP, binary path, and host reachability. Pairing uses `StreamingPairingSession` + `SunshineControlPlaneClient` — Mac submits a 4-digit PIN to Sunshine `/api/pin` (port **47990**) and polls `api/clients/list` until the companion appears as a new paired client. No Sunshine web UI required. Run **only one** Sunshine instance (avoid port **48010** “already in use”).
- **Companion app (Flutter):** Moonlight-compatible pairing in `SunshinePairingService` — full HTTP handshake (`getservercert` → challenge exchange → `clientpairingsecret`) plus HTTPS **`pairchallenge`** with mTLS client cert. Client cert/key persist in `PairingCryptoStore`; paired host + pinned server cert in `PairingStateStore`. **Hosts** tab shows **Paired** after HTTPS `applist` probe. **Session:** `MoonlightStreamService` + `StreamingBridge` → **Android** `StreamLaunchHelper` / **`Game`** activity (`moonlight-stream`); **iOS** `PlayniteMoonlight` pod + `PlayniteStreamLaunchHelper` (patched Limelight `StreamFrameViewController`). Identity sync: Android `filesDir`; iOS Documents (`client.crt`, `client.key`, `client.p12`). **Android crypto:** platform RSA (no BC `KeyFactory` on API 28+). **Android** E2E stream verified; **iOS** release build succeeds (`flutter build ios --no-codesign`).
- **Streaming docs:** `streaming-quickstart.md`, `streaming-setup.md`, `companion-flutter.md`; vendor forks under `Vendor/streaming-repos/`; `Scripts/clone-streaming-forks.sh` and `stage-sunshine-for-mac-app.sh`.
- **Metadata:** Replaced IGDB with **ScreenScraper** (`ScreenScraperClient`, `jeuRecherche.php`). Credentials in `MetadataCredentials` (dev + optional user). Settings: `ScreenScraperSettingsSheet`; Library toolbar **Metadata Settings**.
- **Covers:** Local folder discovery still runs first; remote art is **appended** to each game’s `coverImageOptions` so the Info panel cover list shows scraped images. Primary cover respects **Paths → per-emulator** toggle: default favors local; optional “prioritize ScreenScraper over local.”
- **Library UI:** **Mac Games** filter; **Add Game** opens a file picker for native `.app`/executables; **Import Epic Installed Games** (toolbar); context menu to clear Mac-only entries. **Cover Art and Metadata → Screen Scrapper** sidebar: credentials + **Scrape Library Now** (full pass).
- **Epic:** `EpicInstalledGamesImporter` reads launcher manifests; entries get `epicAppName` for URI launch; `GameLauncher` tries Epic protocol before direct open.
- **Inspector:** Mac games can edit **game path** and use existing cover controls.
- **Help:** “Keystrokes permission” explains macOS input prompts and trying Deny first.
- **Persistence:** `EmulatorProfile.preferScreenScraperCovers` added with **default `false`** so existing stores migrate without crashing.

## Focus for next release
- **Audio:** Confirm Mac console shows `[PlayniteAudio] phone subscribed` → `first capture buffer` → `sent packet #1`; phone log should show `First audio packet` / `AudioTrack started`. Check Mac firewall for UDP **28767**.
- **Touch:** Confirmed on device; keep regression check for `Input UDP #1` + non-inverted Y after Mac rebuild.
- **iOS:** Native video receiver still stub; Android is reference path.
- Harden ScreenScraper matching (system IDs, checksum-based `jeuInfos` where useful).
- Optional progress UI for full-library scrape; rate-limit awareness vs. ScreenScraper quotas.

## Minimum for next release
- Smoke test: Mac **Streaming** host running; companion **Pair** + **Start Desktop stream** on Android — video visible (**passed** Jun 3: 908/913 rendered).
- Smoke test: phone touch moves Mac cursor in correct direction (`Input UDP #1` in export log; Mac `[PlayniteInput]` lines) — **passed** after Y-axis fix.
- Smoke test: Mac audio audible on phone (`AudioTrack started` in export log).
- Smoke test: fresh install, migrate from prior store, Paths toggle + scrape + grid/Info covers.

## Future plans
- Keychain for ScreenScraper and streaming credentials; richer metadata fields in inspector if API responses are expanded; optional virtual audio device only if UDP PCM path is insufficient.
