# Streaming quickstart (Playnite Mac + companion)

Playnite Mac **starts Sunshine for you** — no browser, no manual Sunshine credentials. See [`streaming-bundled-host.md`](streaming-bundled-host.md) for staging the binary.

## 1. Stage Sunshine (once per machine)

```bash
./Scripts/stage-sunshine-for-mac-app.sh --install
```

(Sunshine lives on the **LizardByte** tap — not `brew install sunshine` from core Homebrew alone.)

Rebuild **MacGameLibrary** in Xcode.

## 2. Run Playnite Mac

1. Open **Streaming** — wait until the host shows **Running and reachable**.
2. Copy **LAN IP** for the companion app.

## 3. Run the companion app

```bash
cd companion_app
flutter pub get
flutter run   # iOS or Android on same Wi‑Fi
```

1. **Settings** → Mac LAN IP → **Save & discover**.
2. **Hosts** → **Discover**.
3. **Pairing** → **Start pairing** (note the 4-digit PIN).
4. On Mac **Streaming** → **Start pairing** → same PIN → **Submit PIN to Sunshine**.

## Ports

| Port | Use |
|------|-----|
| 47989 | Moonlight HTTP (`/pair`, `/serverinfo`) |
| 47984 | Moonlight HTTPS |
| 47990 | Sunshine control plane + `/api/pin` |

## Troubleshooting

- **Host unavailable**: Run `stage-sunshine-for-mac-app.sh` or `brew install sunshine`, then **Restart streaming host**.
- **Mac not reachable from phone**: Firewall, wrong IP, different Wi‑Fi.
- **PIN submit fails**: Start pairing on the **phone first**, then submit on Mac within ~10 minutes.
- **Video**: Session tab is still a stub; pairing is the supported test today.
