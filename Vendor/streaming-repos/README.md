# Streaming: Apollo + Moonlight (forks, PIN pairing, in-app HTTP)

This folder is where **your forks** of [Apollo](https://github.com/ClassicOldSong/Apollo) and [Moonlight iOS](https://github.com/moonlight-stream/moonlight-ios) live locally. The Mac app does **not** embed them as submodules by default; run the clone script (or add submodules yourself) after you create forks on GitHub.

## Why forks?

- **Apollo** (Sunshine fork): host on the Mac—encode and expose the Moonlight protocol.
- **Moonlight iOS**: client on the phone.

You will adjust both so **control-plane HTTPS** (the same APIs the web UI uses) is reached only from **native code**—`URLSession` / `WKWebView` inside the Mac app and iOS app—**not Safari**. Pairing uses a **PIN** the Mac shows and the phone enters (same idea as Sunshine/Moonlight pairing today).

## 1. Create forks on GitHub

Fork these into your account (GitHub UI or `gh repo fork`):

- https://github.com/ClassicOldSong/Apollo
- https://github.com/moonlight-stream/moonlight-ios

Point `git remote origin` at **your** forks so changes push to you.

## 2. Clone into this repo

From the repo root:

```bash
chmod +x Scripts/clone-streaming-forks.sh
./Scripts/clone-streaming-forks.sh
```

To clone **your** forks instead of upstream:

```bash
export APOLLO_GIT_URL=https://github.com/<you>/Apollo.git
export MOONLIGHT_GIT_URL=https://github.com/<you>/moonlight-ios.git
./Scripts/clone-streaming-forks.sh
```

Clones land in `Vendor/streaming-repos/Apollo` and `Vendor/streaming-repos/moonlight-ios` (gitignored).

## 3. What to change (high level)

### Apollo (host)

- Keep the **HTTPS server** on localhost (default web UI port is in the Sunshine/Apollo docs—see `ControlPlanePorts` in Swift).
- Ensure **pairing PIN** endpoints remain usable without opening Safari: the Mac app will call them via `InAppControlPlaneClient` (TLS with the host’s self-signed cert—pin trust in Keychain or a custom `URLSessionDelegate`).
- Optionally **disable or hide** the “open in browser” onboarding path for retail builds; advanced settings can stay behind an in-app WebView if needed.

### Moonlight iOS (client)

- Replace any flow that sends users to **Safari** for PC setup with:
  - **PIN entry** + **`URLSession`/`WKWebView`** against `https://<mac-local-ip>:<port>` for the same routes the desktop web UI uses, **or**
  - Native forms that call the same REST endpoints Moonlight already uses internally after pairing.
- The PIN **pairing channel** matches what the Mac app displays in **Streaming**.

## 4. Mac app integration

Swift types live under `Sources/MacGameLibrary/Streaming/`: ports, PIN models, and `StreamingControlPlaneClient` (stub `URLSession` you wire to real endpoints as you align with Apollo’s API).

## References

- [Sunshine](https://github.com/LizardByte/Sunshine) (upstream of Apollo)
- [Apollo](https://github.com/ClassicOldSong/Apollo)
- [Moonlight iOS](https://github.com/moonlight-stream/moonlight-ios)
