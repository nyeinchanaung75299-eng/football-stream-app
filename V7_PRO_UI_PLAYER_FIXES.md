# V7 Pro - UI and player fixes

- Viewer top “Live Football / X live / X active” banner removed.
- Viewer shows only selected featured matches.
- “Watch Live / Choose a server” intermediate screen is bypassed for native streams.
- WATCH opens the highest-priority healthy server directly.
- Native player automatically tries backup servers when the current server fails.
- Server switch lives inside the fullscreen player instead of a separate cluttered page.
- Quality selector lives inside the fullscreen player and reads variants from one adaptive HLS/DASH manifest.
- Player errors stay on the player screen instead of intentionally closing the activity.
- Admin “Live Match Manager” hero removed; dashboard is a compact 4-item control center.
- Fixture-picker errors are shortened to a useful API setup message.
- football-fixtures checks API_FOOTBALL_KEY plus APISPORTS_KEY/API_SPORTS_KEY aliases.
