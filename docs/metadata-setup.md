# Metadata (IGDB) setup

The app loads **covers and titles** from **IGDB** using the same kind of stack as **Playnite’s IGDB metadata** (Twitch Developer app + IGDB API v4). Scraping runs **in the background** after you add credentials: there is no separate scraper service to install.

## What you need to do

### 1. Create a Twitch Developer application

1. Open the [Twitch Developer Console](https://dev.twitch.tv/console/apps).
2. **Register** an application (any name you like).
3. Note the **Client ID**.
4. Generate or reveal the **Client Secret** (keep it private).

You do **not** need users to log in with Twitch in the app. The app uses the **client credentials** OAuth flow (machine-to-machine) described in the [IGDB API documentation](https://api-docs.igdb.com).

### 2. Enable IGDB API access

In the Twitch Developer portal, ensure your application can access **IGDB** (the console lets you link products; follow Twitch’s current steps for “IGDB” / API access). If IGDB requests fail with auth errors, revisit this step.

### 3. Enter credentials in Mac Game Library

1. Run the Mac app.
2. Open the **Library** tab.
3. In the toolbar, click the **Metadata (IGDB)** button (angled photo / rectangle icon).
4. Paste **Client ID** and **Client Secret**, then **Save**.

Credentials are stored in **User Defaults** on this Mac (`MetadataCredentials` in the codebase). For stronger security later, consider moving secrets to the Keychain.

### 4. Confirm background behavior

After saving:

- A **background loop** starts (if it was not already running) and periodically processes games **without a cover**.
- **Scan Paths** and closing the metadata sheet trigger an **extra pass** so new imports are picked up quickly.

Details:

- Titles are derived from the **ROM file name** (stem), with light cleanup (parentheses / bracket tags removed) before searching IGDB.
- Failed or empty lookups are **throttled** (see `metadataLastFetchAt` on `LibraryGame`) so the API is not hammered.

### 5. Optional: environment / automation

For development, you can also rely on whatever mechanism you use to inject secrets; the shipping UI path is the in-app sheet above.

## Troubleshooting

| Issue | What to check |
|--------|----------------|
| No covers ever appear | Client ID/Secret correct; IGDB enabled for the Twitch app; network allowed (firewall/VPN). |
| Covers for wrong games | IGDB search is title-based; rename the file or improve `RomTitleNormalizer` / add platform filters later. |
| Images do not load in the grid | IGDB often returns `//images.igdb.com/...` URLs; the app normalizes them to `https`. If a tile stays blank, check the URL in SwiftData (Stored Data inspector) or Console. |
| Rate limits | The fetcher spaces requests (~450ms between games, ~45s between batches). Heavy libraries fill over time. |

## References

- [IGDB API documentation](https://api-docs.igdb.com)
- [Twitch OAuth client credentials](https://dev.twitch.tv/docs/authentication/getting-tokens-oauth/#client-credentials-grant-flow) (used to obtain a bearer token for IGDB)
- Playnite metadata extensions overview: [Metadata plugins](https://api.playnite.link/docs/tutorials/extensions/metadataPlugins.html)
