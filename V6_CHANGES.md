# V6 player + admin link management

## Viewer
- Native player is edge-to-edge fullscreen on Android 12.
- Back arrow added at top-left.
- Quality / resolution selector added at top-right.
- When a match has multiple native links (480p/720p/1080p etc.), switch inside the player.
- HLS (.m3u8) supported.
- DASH (.mpd) supported.
- Authorized ClearKey supported.
- Direct / progressive URLs supported.
- FLV (.flv) URLs are accepted using Auto/FLV mode and Media3 progressive detection.
- MP4 direct links supported.
- Referer and Origin headers preserved.
- WebView links still supported.

## Admin
- Stream type choices now include Auto/Direct, HLS, DASH, FLV and MP4.
- Existing links for the selected match are shown in the same screen.
- Every link has Edit, Delete and Active/Inactive controls.
- Wrong links can be fixed without deleting the match.

## Existing Supabase project
Run `supabase/upgrade_stream_links_v6.sql` once before using FLV/Auto/MP4 types.
