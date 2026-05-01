This log will change with every commit in version control.

The purpose of this is to give a brief description of what happened since the last commit.

For the **living product and architecture handbook**, see `Features and Inner Workings.md`.

---

current release: 1  

## Updates
- **Metadata:** Replaced IGDB with **ScreenScraper** (`ScreenScraperClient`, `jeuRecherche.php`). Credentials in `MetadataCredentials` (dev + optional user). Settings: `ScreenScraperSettingsSheet`; Library toolbar **Metadata Settings**.
- **Covers:** Local folder discovery still runs first; remote art is **appended** to each game’s `coverImageOptions` so the Info panel cover list shows scraped images. Primary cover respects **Paths → per-emulator** toggle: default favors local; optional “prioritize ScreenScraper over local.”
- **Library UI:** **Mac Games** filter; **Add Game** opens a file picker for native `.app`/executables; **Import Epic Installed Games** (toolbar); context menu to clear Mac-only entries. **Cover Art and Metadata → Screen Scrapper** sidebar: credentials + **Scrape Library Now** (full pass).
- **Epic:** `EpicInstalledGamesImporter` reads launcher manifests; entries get `epicAppName` for URI launch; `GameLauncher` tries Epic protocol before direct open.
- **Inspector:** Mac games can edit **game path** and use existing cover controls.
- **Help:** “Keystrokes permission” explains macOS input prompts and trying Deny first.
- **Persistence:** `EmulatorProfile.preferScreenScraperCovers` added with **default `false`** so existing stores migrate without crashing.

## Focus for next release
- Harden ScreenScraper matching (system IDs, checksum-based `jeuInfos` where useful).
- Optional progress UI for full-library scrape; rate-limit awareness vs. ScreenScraper quotas.

## Minimum for next release
- Smoke test: fresh install, migrate from prior store, Paths toggle + scrape + grid/Info covers.

## Future plans
- Keychain for ScreenScraper secrets; richer metadata fields in inspector if API responses are expanded.
