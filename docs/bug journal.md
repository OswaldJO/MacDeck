# Bug journal

Chronicle of bugs encountered in **Playnite Mac** and the **companion app**, and how they were fixed. Entries are grouped by area; dates come from git commits unless noted as **in progress** (not yet committed).

For release notes style summaries, see `source control log.md`. For architecture context, see `Features and Inner Workings.md`.

---

## Mac library — scanning & covers

### BJ-001 — Exclude folders ignored due to path string mismatch
| | |
|---|---|
| **When** | Apr 21, 2026 (`7586490` *scan bugs*) |
| **Symptom** | ROMs under configured exclude paths were still imported, or excludes behaved inconsistently vs. Finder paths. |
| **Cause** | Exclude checks compared raw path strings without normalizing (`standardizingPath`, trailing slashes, case). |
| **Fix** | `GamePathScanner.normalizedPathForComparison()`; all exclude/root/existing-ROM lookups use normalized lowercase paths. |
| **Commit** | `7586490` |

### BJ-002 — “Ghost” library games after emulator removed
| | |
|---|---|
| **When** | Apr 21, 2026 (`1933de3` *scan bugs pt2*) |
| **Symptom** | Deleted or missing emulators left games visible in the grid; Play failed silently or behaved oddly. |
| **Cause** | `LibraryGame` rows kept stale `emulatorUUID`; filter showed all games regardless of live `EmulatorProfile` rows. |
| **Fix** | Filter library to `visibleLibraryGames` (game’s emulator must exist); startup `removeOrphanedGamesFromLibrary()` with user-facing cleanup alert; Play guards with clear `scanFeedback` when emulator reference is invalid. |
| **Commit** | `1933de3` |

### BJ-003 — Scan gave no useful feedback / games not reassigned to correct emulator
| | |
|---|---|
| **When** | Apr 21, 2026 (`7586490`, `51575dd`) |
| **Symptom** | Scan appeared to do nothing; ROMs stayed tied to wrong emulator after path changes. |
| **Cause** | Scan only returned a count; path keys didn’t match when re-scanning; limited logging. |
| **Fix** | `ScanSummary` (added / reassigned / linked covers); per-emulator scan logging; reassignment when an existing path is scanned under a different emulator; cover linking improvements in *Cover link algorithm*. |
| **Commit** | `7586490`, `51575dd` |

### BJ-004 — SwiftData crash on `preferScreenScraperCovers`
| | |
|---|---|
| **When** | Metadata / ScreenScraper work (documented in `Features and Inner Workings.md`) |
| **Symptom** | App crashed on launch or migration after adding a new non-optional model field. |
| **Cause** | New attribute without a default for existing stores. |
| **Fix** | Default `preferScreenScraperCovers = false` on `EmulatorProfile`. |
| **Commit** | (field added during ScreenScraper integration; see metadata commits ~`526b1b3`) |

### BJ-005 — Builtin emulator catalog entries “hide and reappear”
| | |
|---|---|
| **When** | Apr 20, 2026 (`46891e0` *hide and reappear*) |
| **Symptom** | Emulators or path UI state confusing after catalog regeneration / launch path changes. |
| **Cause** | Catalog JSON regeneration and `PathsView` / `GameLauncher` behavior out of sync with user expectations. |
| **Fix** | Catalog generation script + `BuiltinEmulatorCatalog` / `PathsView` / `GameLauncher` updates so hidden or path-related state is consistent. |
| **Commit** | `46891e0` |

---

## Streaming — architecture (Sunshine → native Playnite)

### BJ-010 — Sunshine/Moonlight path fragile (ports, PIN, dual instances)
| | |
|---|---|
| **When** | Jun 2–3, 2026 (Sunshine era: `f373265`, `cead3f0`, `a0a1ee1`; removed `df1f254`) |
| **Symptom** | Pairing/streaming depended on external Sunshine; port **48010** conflicts if two instances; Moonlight `/launch` coupling; hard to ship in Mac app bundle. |
| **Cause** | Out-of-process Sunshine + forked Moonlight repos + TLS/control-plane complexity. |
| **Fix** | Replaced with in-app **Playnite** stack: `PlayniteStreamControlServer`, ScreenCaptureKit + VideoToolbox, companion `PlayniteHostClient` / `PlayniteVideoActivity`. Removed Sunshine bootstrap scripts and vendor clones (`df1f254`). |
| **Commit** | `df1f254` (*no more sunshine or moonlight*) |

---

## Streaming — video (Android)

### BJ-020 — Black screen / decoder not configured (H.264 Annex-B)
| | |
|---|---|
| **When** | Jun 3, 2026 (`df1f254` native video path; hardened in follow-up work) |
| **Symptom** | TCP connected but no picture; logs showed `decoder=false` until keyframe/SPS/PPS handled. |
| **Cause** | Mac sends length-prefixed `PNV1` Annex-B; MediaCodec needs SPS/PPS (avcC or in-band) before slice NALs. |
| **Fix** | `PlayniteVideoActivity` Annex-B parse, avcC bootstrap, keyframe gating, `c2.android.avc.decoder` path; Mac encoder keyframe on connect. Verified ~900+ frames rendered in session logs. |
| **Commit** | `df1f254`, ongoing in `41487e8` / `PlayniteVideoActivity.kt` |

---

## Streaming — touch & keyboard (Mac + Android)

### BJ-030 — Touch Y axis inverted on Mac
| | |
|---|---|
| **When** | Jun 3, 2026 (`cbd1ca8` *no more inverted mouse input*) |
| **Symptom** | Finger up on phone moved Mac cursor down (or vice versa). |
| **Cause** | Normalized phone Y mapped with `frame.maxY - ny * height` (flipped). |
| **Fix** | Use `frame.minY + ny * height` in `PlayniteRemoteInputPlayback`. Removed obsolete companion “mouse emulation” toggle. |
| **Commit** | `cbd1ca8` |

### BJ-031 — Command+Q (and letters) sent wrong keys to Mac
| | |
|---|---|
| **When** | Jun 3, 2026 (`ae82eac` *shortcut fix*) |
| **Symptom** | **Close app** shortcut and chords didn’t quit the foreground app; wrong characters or no effect. |
| **Cause** | `PlayniteKeyboardPlayback` mapped Windows VK with `vk - 0x41` (e.g. Q → keycode 16 instead of **12**); Command/Option posted as separate key down/up events instead of `CGEvent.flags`. |
| **Fix** | US ANSI `windowsVKToMacKeyCode` table (Carbon `kVK_ANSI_*`); modifiers only update `heldModifierFlags`; letter keys posted with correct `CGKeyCode`. |
| **Commit** | `ae82eac` |

### BJ-032 — Shortcuts stopped working after leaving video with Back
| | |
|---|---|
| **When** | Jun 3, 2026 (`ae82eac`, `f7c4936`) |
| **Symptom** | Notification or home **Shortcuts** / **Close app** did nothing after Back left `PlayniteVideoActivity`. |
| **Cause** | `PlayniteKeyboardSender` lived on the activity and was cleared on destroy. |
| **Fix** | Session-scoped `PlayniteStreamSession.keyboardSender()` for the whole stream; activity uses shared sender. |
| **Commit** | `f7c4936`, `ae82eac` |

### BJ-033 — Mac Command/Option missing from chord picker
| | |
|---|---|
| **When** | Jun 3, 2026 (`f7c4936` *controller mapping*) |
| **Symptom** | Could not map gamepad buttons to Mac Command/Option chords. |
| **Cause** | Moonlight key list / Mac playback didn’t treat modifier VKs correctly. |
| **Fix** | Added Option/Command (left/right) to picker; `PlayniteKeyboardPlayback` modifier flag path (completed in `ae82eac`). |
| **Commit** | `f7c4936`, `ae82eac` |

---

## Streaming — audio

### BJ-040 — No audio on phone / multi-second latency
| | |
|---|---|
| **When** | Jun 3, 2026 (`41487e8` *streaming and audio work*) |
| **Symptom** | Video worked; phone silent or audio heavily delayed. |
| **Cause** | UDP-only or blocked reader; oversized `AudioTrack` buffer; planar ScreenCaptureKit audio not interleaved correctly on Mac. |
| **Fix** | Mac: stereo interleave in `PlayniteDisplayCapture`; **`PNA1`** over **TCP 28769** (primary). Android: `PlayniteAudioReceiver` network + playback threads, ~150 ms buffer, `PERFORMANCE_MODE_LOW_LATENCY`. |
| **Commit** | `41487e8` |

### BJ-041 — Mac speakers still audible while “streaming” to phone
| | |
|---|---|
| **When** | Jun 3, 2026 (`41487e8`; behavior refined in uncommitted host lifecycle work) |
| **Symptom** | Mac continued playing audio locally when the Mac app was open, even when user expected phone-only playback. |
| **Cause** | Output not muted during stream; early host startup started capture/listeners whenever Streaming UI opened. |
| **Fix** | `PlayniteLocalOutputMute` during active stream; restore on stop. **In progress:** `ensureReady()` only starts HTTP pairing control—capture/transport start on companion `stream/start` (see BJ-050). |
| **Commit** | `41487e8` (mute); host lifecycle split **in progress** (working tree) |

---

## Companion — pairing & UI

### BJ-050 — Mac capture/stream ran whenever Streaming tab opened
| | |
|---|---|
| **When** | Jun 3, 2026 (**in progress**, working tree) |
| **Symptom** | Opening Mac Game Library → Streaming muted Mac and felt like “stream always on” without companion starting a session. |
| **Cause** | `PlayniteStreamHostManager.ensureReady()` started video/audio/input listeners and implied active streaming. |
| **Fix** | `ensureReady()` starts **HTTP 28765 only**; `beginVideoStream` on `POST /playnite/v1/stream/start`; `endVideoStream` on `stream/stop`; UI copy distinguishes pairing host vs active stream. |
| **Commit** | *Not committed yet* |

### BJ-051 — No way to cancel pairing wait on phone
| | |
|---|---|
| **When** | Jun 3, 2026 (`ae82eac`) |
| **Symptom** | Pair button stayed disabled while polling; user had to wait for Mac deny/timeout. |
| **Cause** | No companion cancel path; only Mac could deny. |
| **Fix** | Outlined **Cancel** on host row; `PairingCancellation` + `POST /playnite/v1/pair/cancel`; Mac `cancelPending(deviceID:)`. |
| **Commit** | `ae82eac` |

### BJ-052 — Host action buttons wrong style (filled vs outlined)
| | |
|---|---|
| **When** | Jun 3, 2026 (`ae82eac`) |
| **Symptom** | Add IP / Pair / Cancel didn’t match desired outlined appearance preset. |
| **Fix** | `OutlinedButton` theme from `CompanionAppearanceSettings` primary text color; chips outlined in mapping/shortcut editors. |
| **Commit** | `ae82eac` |

---

## Companion — stream notification (Android)

### BJ-060 — Samsung notification showed title only (no Stop/Controller/Shortcuts)
| | |
|---|---|
| **When** | Jun 3, 2026 (`b4933a8`, `ae82eac`) |
| **Symptom** | Ongoing stream notification collapsed to a single line on Samsung/One UI. |
| **Cause** | `DecoratedCustomViewStyle` + low-importance channel; OEM ignores custom RemoteViews layout. |
| **Fix** | Channel `playnite_stream_session_v2` (HIGH); custom `playnite_stream_notification.xml`; **no** `DecoratedCustomViewStyle`; duplicate `NotificationCompat.addAction` fallback buttons. |
| **Commit** | `b4933a8`, `ae82eac` |

### BJ-061 — App crashed when tapping notification Shortcuts
| | |
|---|---|
| **When** | Jun 3, 2026 (`ae82eac`) |
| **Symptom** | Process died after **Shortcuts** action; SecurityException in log. |
| **Cause** | `NotificationShadeUtils` broadcast `Intent.ACTION_CLOSE_SYSTEM_DIALOGS`, blocked on modern Android. |
| **Fix** | Removed broadcast; reflection-only `StatusBarManager.collapsePanels()` wrapped in try/catch; collapse is best-effort after action. |
| **Commit** | `ae82eac` |

### BJ-062 — Notification **Stop** didn’t allow starting a new stream
| | |
|---|---|
| **When** | Jun 3, 2026 (reported after `ae82eac`; fix **in progress**) |
| **Symptom** | Notification **Stop** OK, but Session tab still showed blue **Streaming** (or 2nd **Start** flashed *Starting* then *Stream stopped*; 3rd **Start** hit `TimeoutException after 0:00:12` on Mac `stream/start`). |
| **Cause** | (1) **300ms delayed `onStreamStoppedExternally`** fired after a new Start. (2) Resume `getStreamSession` during start reset UI. (3) Mac start/stop HTTP overlapped while capture still tearing down. (4) Prior `deactivate()` callback re-entered `stopAll`. (5) `_refreshStreamSessionState` cleared *Stream running* / *Starting* but not success label **Streaming**; Flutter stop notify removed from `stopAll`. |
| **Fix** | Remove delayed stop notify; ignore external stop while `_startingStream`; skip session refresh during start; companion calls `stream/stop` + status poll + 25s timeout/5 retries before start; Mac `enqueueStreamOperation` + cancel `captureTask`; `_isLiveStreamSessionStatus` clears **Streaming** when native inactive; **pull model:** `pendingExternalStopLogPath` on `getStreamSession`; resume refresh offers log; `_startStream` trusts native `hostStreamActive`. **Jun 2026:** notification **Stop** removed — use Session tab **Stop** only (notification path could not reliably sync Flutter / second **Start**). |
| **Commit** | *Not committed yet* |

### BJ-063 — Second stream: `ECONNREFUSED` on port 28766
| | |
|---|---|
| **When** | Jun 3, 2026 (logs + **in progress** fix) |
| **Symptom** | After stop, new session immediately failed connect to `192.168.1.14:28766`. |
| **Cause** | (1) `NWListener.start()` returned before `.ready`. (2) Fast Session Stop posted Mac `stream/stop` in the background; a late stop could kill the next stream after `stream/start`. (3) Stale TCP listener if `stopListener` had not finished. |
| **Fix** | `PlayniteNWListenerAwait`; deferred native connect result; `macStopGeneration` cancels stale Android background stops on new start; Mac restarts listener if still bound; preemptive `endVideoStream` when listener active. |
| **Commit** | *In progress* |

---

## Companion — session lifecycle

### BJ-070 — `hostStreamActive` stuck after failed connect
| | |
|---|---|
| **When** | Jun 3, 2026 (**in progress**) |
| **Symptom** | Connect failed but app behaved as if stream still active; **Start** disabled. |
| **Cause** | `PlayniteVideoActivity` called `finish()` on connect error without clearing `PlayniteStreamSession` or stopping Mac. |
| **Fix** | `handleConnectFailure()` → `PlayniteStreamStopper.stopAll`; `launchStreamActivity` returns `false` to Flutter when connect fails (no immediate `result.success(true)`). |
| **Commit** | *In progress (with BJ-063)* |

---

## Open / known issues

| ID | Issue | Notes |
|----|--------|--------|
| — | Some OEMs still collapse custom notification layout | `addAction` fallback present; may need in-app stream control panel. |
| — | iOS native video/audio receiver stub | Android is reference client. |
| — | `stream/start` can take >8s if Mac capture is slow | Mitigated by transport-first HTTP + 30s Dart timeout (**in progress**). |

---

## How to add entries

1. Assign the next **BJ-###** id.
2. Include **symptom**, **cause**, **fix**, and **commit** (or *in progress*).
3. Add a line to `source control log.md` when the fix ships in a release.
