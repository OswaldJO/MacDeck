# Bundled Sunshine host (Playnite Mac)

Playnite Mac **manages Sunshine for you**:

- Isolated config under `~/Library/Application Support/MacGameLibrary/sunshine/`
- Auto-generated control-plane credentials (no web UI setup)
- Starts Sunshine when you open the **Streaming** tab
- PIN pairing with the companion app (unchanged flow)

## One-time: provide a Sunshine binary

Playnite does not compile Sunshine inside Xcode by default. Stage a binary once:

```bash
chmod +x Scripts/stage-sunshine-for-mac-app.sh
./Scripts/stage-sunshine-for-mac-app.sh --install
```

`--install` adds the **LizardByte** Homebrew tap and installs Sunshine (it is **not** in default `brew`). Then the script copies `sunshine` into `MacGameLibraryApp/Resources/Sunshine/`.

Manual install:

```bash
brew tap LizardByte/homebrew
brew install lizardbyte/homebrew/sunshine
./Scripts/stage-sunshine-for-mac-app.sh
```

Then rebuild **MacGameLibrary** in Xcode.

If you skip staging, Playnite still looks for:

- `/opt/homebrew/bin/sunshine`
- `/Applications/Sunshine.app/Contents/MacOS/sunshine`

## Test pairing (no browser)

1. Open **Streaming** on the Mac — wait for **Running and reachable**.
2. Note **LAN IP** → companion **Settings**.
3. Companion **Pairing** → **Start pairing** (PIN on phone).
4. Mac **Start pairing** → enter PIN → **Submit PIN to Sunshine**.

See also [`streaming-quickstart.md`](streaming-quickstart.md).

## Config location

| File | Purpose |
|------|---------|
| `playnite-sunshine.conf` | Ports, credentials file name |
| `sunshine_state.json` | Web API login (managed by Playnite) |
| `credentials/` | TLS certs for Moonlight (created by Sunshine) |

To reset: quit Playnite, delete the `sunshine` folder under Application Support, reopen **Streaming**.
