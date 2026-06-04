This log will change with every commit in version control.

The purpose of this is to give a brief description of what happened since the last commit.

For the **living product and architecture handbook**, see `Features and Inner Workings.md`.

---

current release: 1  

## Updates
- **Companion + Mac — stream shortcuts verified (Jun 3 2026):** **Command + Q** (and other chords) work on the Mac. Android logs show `PNK1` sends; fix was **`PlayniteKeyboardPlayback`**: US ANSI **Windows VK → `CGKeyCode`** table (e.g. `Q` = 12, not `vk - 0x41`), modifiers update **`CGEvent.flags`** only (Command/Option not posted as separate key events). Session-scoped **`PlayniteStreamSession.keyboardSender`** survives leaving the video view so notification/home shortcuts still work.
- **Companion — pairing cancel + host button styling (Jun 3 2026):** While waiting on the Mac, host **Pair** becomes **Cancel** (same outlined style as Pair). **`POST /playnite/v1/pair/cancel`** withdraws the pending request on the Mac. **Add IP**, **Pair**, and **Cancel** use **`OutlinedButton`** (no fill; border + label use **Appearance** primary text color). **Chips** in mapping/shortcut editors match (transparent fill, outline from `chipTheme`).
- **Companion — stream notification hardening (Jun 3 2026):** Custom notification layout (`playnite_stream_notification.xml`) shows **Stop | Controller | Shortcuts** inline; channel **`playnite_stream_session_v2`**, no `DecoratedCustomViewStyle` (Samsung was collapsing to title-only). Standard `addAction` fallback retained. Fixed crash: **`NotificationShadeUtils`** no longer broadcasts `CLOSE_SYSTEM_DIALOGS` (SecurityException killed the app when tapping **Shortcuts**). Shade collapse is best-effort only, after the action runs.
- **Companion — appearance + Close app shortcut (Jun 3 2026):** **Settings → Appearance** presets (White, Purple, Lavender, Blue, Mint, Peach) plus **Custom** RGB picker; updates primary text color app-wide via `CompanionAppearanceSettings`. Default **Close app** shortcut is **Command + Q** (migrates stored ⌘⌥Esc default on next launch).
- **Companion — stream shortcuts (Jun 3 2026):** **Settings** tab lists named keyboard chords (create / edit / delete). Notification **Shortcuts** (right of Controller); tap opens overlay on the video and sends the chord to the Mac via `PNK1`.
- **Companion — Mac modifier keys + stream notification (Jun 3 2026):** Controller mapping chord picker includes **Option**, **Option (right)**, **Command**, and **Command (right)** (Moonlight Windows VK → Mac `CGEvent` in `PlayniteKeyboardPlayback`). Android stream session uses a native ongoing notification (**Stop** ends Mac + phone stream; **Controller** opens mapping overlay on the video view). Flutter debug banner disabled (`debugShowCheckedModeBanner: false`).
- **Native Playnite streaming — audio + Mac mute (Jun 3 2026, verified):** Phone playback works end-to-end. Mac captures system audio via ScreenCaptureKit (planar stereo interleave when ≥2 buffers have data), sends **`PNA1`** over **TCP 28769** (length-prefixed frames; UDP **28767** still used for **`PNAS`** subscribe). Android **`PlayniteAudioReceiver`**: dedicated network + playback threads, ~150 ms `AudioTrack` buffer (not multi-second), `PERFORMANCE_MODE_LOW_LATENCY`. Mac **`PlayniteLocalOutputMute`** mutes default output while streaming and restores on stop. Smoke test: sustained `Audio packet #N` on phone, audible media on device, Mac speakers quiet during stream.
- **Native Playnite streaming (Android video verified, Jun 3 2026):** Mac **in-app host** (ScreenCaptureKit + H.264, no Sunshine) — companion opens **`PlayniteVideoActivity`**, TCP **`PNV1`** on **28766**, Annex-B + `c2.android.avc.decoder`. Latest phone log: **913 frames received / 908 rendered** (~34 s), clean stop via Back. Ports: control **28765**, video **28766**, audio UDP **28767**, audio TCP **28769**, input **28768**.
- **Touch (working on Android):** UDP `PNI1` on background thread + Mac **Accessibility** — relative cursor; tap/drag gestures; **Settings → Controllers → Touchpad (stream view):** cursor speed, tap movement %, tap time ms, tap pressure %. Fixed **inverted Y** (`PlayniteRemoteInputPlayback`: `CGDisplayBounds` + `loc.y += dy`). Removed companion **Mouse emulation** toggle (native stream uses direct touch).
- **Streaming (legacy Sunshine path):** Companion Moonlight `/launch` path still documented in older notes; current default is native host above.
- **Streaming (Sunshine host):** **Streaming** tab starts and monitors Sunshine via `SunshineHostManager`; pairing uses `StreamingPairingSession` + `SunshineControlPlaneClient` — Mac submits a 4-digit PIN to Sunshine `/api/pin` (port **47990**). Run **only one** Sunshine instance (avoid port **48010** “already in use”).
- **Companion app (Flutter):** Moonlight-compatible pairing in `SunshinePairingService`; **Hosts** / **Session** tabs; Android **`PlayniteVideoActivity`** is the reference native stream client; iOS native video receiver still limited.
- **Streaming docs:** `streaming-native.md`, `streaming-quickstart.md`, `streaming-setup.md`, `companion-flutter.md`.
- **Metadata:** Replaced IGDB with **ScreenScraper** (`ScreenScraperClient`, `jeuRecherche.php`). Credentials in `MetadataCredentials`. Settings: `ScreenScraperSettingsSheet`; Library toolbar **Metadata Settings**.
- **Covers:** Local folder discovery first; remote art appended to `coverImageOptions`; primary cover respects per-emulator **prioritize ScreenScraper** toggle.
- **Library UI:** **Mac Games** filter; **Add Game**; **Import Epic Installed Games**; context menu to clear Mac-only entries. **Screen Scrapper** sidebar: credentials + **Scrape Library Now**.
- **Epic:** `EpicInstalledGamesImporter`; `GameLauncher` tries Epic URI before direct open.
- **Inspector:** Mac games can edit **game path** and cover controls.
- **Help:** “Keystrokes permission” explains macOS input prompts.
- **Persistence:** `EmulatorProfile.preferScreenScraperCovers` default **`false`** for migration.

## Focus for next release
- **iOS:** Native video/audio receiver still stub; Android is reference path.
- Harden ScreenScraper matching (system IDs, checksum-based `jeuInfos` where useful).
- Optional progress UI for full-library scrape; rate-limit awareness vs. ScreenScraper quotas.
- Regression: video + touch + audio on Android after Mac/Xcode rebuild; confirm Mac mute restores after stream stop or host stop.
- OEM notification layouts (some devices still collapse custom views); document if a dedicated “stream controls” in-app panel is needed.

## Minimum for next release
- Smoke test: Mac **Streaming** host running; companion **Pair** + **Start Desktop stream** on Android — video visible (**passed** Jun 3).
- Smoke test: phone touch moves Mac cursor, correct Y (**passed**).
- Smoke test: Mac audio audible on phone; Mac speakers muted during stream (**passed** Jun 3).
- Smoke test: **Close app** shortcut (notification or Settings) sends **⌘Q** to Mac foreground app (**passed** Jun 3).
- Smoke test: **Pair** → **Cancel** clears Mac pending request; re-pair when ready (**passed** Jun 3).
- Smoke test: notification **Shortcuts** does not crash app; stream stays active (**passed** Jun 3).
- Smoke test: fresh install, migrate from prior store, Paths toggle + scrape + grid/Info covers.

## Future plans
- Keychain for ScreenScraper and streaming credentials; richer metadata fields in inspector if API responses are expanded; optional virtual audio device only if in-app capture path is insufficient on some Mac setups.
