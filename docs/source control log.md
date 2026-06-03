This log will change with every commit in version control.

The purpose of this is to give a brief description of what happened since the last commit.

For the **living product and architecture handbook**, see `Features and Inner Workings.md`.

---

current release: 1  

## Updates
- **Streaming (Sunshine host):** **Streaming** tab starts and monitors Sunshine via `SunshineHostManager`; shows LAN IP, binary path, and host reachability. Pairing uses `StreamingPairingSession` + `SunshineControlPlaneClient` — Mac submits a 4-digit PIN to Sunshine `/api/pin` (port **47990**) and polls `api/clients/list` until the companion appears as a new paired client. No Sunshine web UI required.
- **Companion app (Flutter):** Moonlight-compatible pairing in `SunshinePairingService` — full HTTP handshake (`getservercert` → challenge exchange → `clientpairingsecret`) plus HTTPS **`pairchallenge`** with mTLS client cert. Client cert/key persist in `PairingCryptoStore`; paired host + pinned server cert in `PairingStateStore`. **Hosts** tab shows **Paired** after HTTPS `applist` probe. **Session** tab on **Android** launches vendored Moonlight `Game` activity (`moonlight-stream` module) with native H.264 decode; iOS stream start remains stub until `moonlight-ios` is wired.
- **Streaming docs:** `streaming-quickstart.md`, `streaming-setup.md`, `companion-flutter.md`; vendor forks under `Vendor/streaming-repos/`; `Scripts/clone-streaming-forks.sh` and `stage-sunshine-for-mac-app.sh`.
- **Metadata:** Replaced IGDB with **ScreenScraper** (`ScreenScraperClient`, `jeuRecherche.php`). Credentials in `MetadataCredentials` (dev + optional user). Settings: `ScreenScraperSettingsSheet`; Library toolbar **Metadata Settings**.
- **Covers:** Local folder discovery still runs first; remote art is **appended** to each game’s `coverImageOptions` so the Info panel cover list shows scraped images. Primary cover respects **Paths → per-emulator** toggle: default favors local; optional “prioritize ScreenScraper over local.”
- **Library UI:** **Mac Games** filter; **Add Game** opens a file picker for native `.app`/executables; **Import Epic Installed Games** (toolbar); context menu to clear Mac-only entries. **Cover Art and Metadata → Screen Scrapper** sidebar: credentials + **Scrape Library Now** (full pass).
- **Epic:** `EpicInstalledGamesImporter` reads launcher manifests; entries get `epicAppName` for URI launch; `GameLauncher` tries Epic protocol before direct open.
- **Inspector:** Mac games can edit **game path** and use existing cover controls.
- **Help:** “Keystrokes permission” explains macOS input prompts and trying Deny first.
- **Persistence:** `EmulatorProfile.preferScreenScraperCovers` added with **default `false`** so existing stores migrate without crashing.

## Focus for next release
- **iOS Moonlight streaming** on companion **Session** tab; harden Android stream stop/lifecycle.
- Harden ScreenScraper matching (system IDs, checksum-based `jeuInfos` where useful).
- Optional progress UI for full-library scrape; rate-limit awareness vs. ScreenScraper quotas.

## Minimum for next release
- Smoke test: Sunshine host running, companion **Pairing** end-to-end (phone Start pairing → Mac Submit PIN → both show Paired).
- Smoke test: **Hosts** → **Paired**; **Session** → **Start Desktop 1080p60** on Android (desktop stream visible).
- Smoke test: fresh install, migrate from prior store, Paths toggle + scrape + grid/Info covers.

## Future plans
- Bundle Sunshine in the Mac app build; Keychain for ScreenScraper and streaming credentials; richer metadata fields in inspector if API responses are expanded.
