# Metadata (ScreenScraper) setup

The app now loads covers and title normalization from **ScreenScraper API v2**. Local folder cover detection still runs first, and ScreenScraper is used as remote fallback when credentials are configured.

## What you need

ScreenScraper credentials from [Web API v2](https://www.screenscraper.fr/webapi2.php):

- `devid` (developer id) - required
- `devpassword` (developer password) - required
- `ssid` (ScreenScraper user id) - optional
- `sspassword` (ScreenScraper user password) - optional

## How it works in this app

- Background metadata jobs process games missing a cover.
- The app first tries local file-based cover discovery around the game path.
- If no local match is found and credentials are configured, it calls `jeuRecherche.php` with `output=json`.
- The best matching result is used to set title + cover.

## Storage

Credentials are stored in **UserDefaults** via `MetadataCredentials`:

- `Metadata.ScreenScraper.DevID`
- `Metadata.ScreenScraper.DevPassword`
- `Metadata.ScreenScraper.UserID`
- `Metadata.ScreenScraper.UserPassword`

For production hardening, move these secrets to Keychain.

## Notes

- ScreenScraper API usage and limits depend on account/developer privileges.
- Some endpoints are documented as mutable/beta; field formats can evolve.
- If no covers appear, verify credentials first, then check API/network access.
