# V7.8 Web mobile player controls

- Replaced browser-native Server and Quality <select> controls with custom dark menus.
- Fixes white/blank option text seen in desktop and mobile browsers.
- Line menu works consistently on phone and PC and shows the current line.
- Quality menu uses the same custom UI and falls back to Auto-only when a browser does not expose manual tracks.
- iPhone/iPad detects unsupported FLV and ClearKey-encrypted DASH lines and opens another compatible line when available.
- iPhone fullscreen uses the native video fullscreen API when available.

Important: iPhone/iPad Safari does not support ClearKey DASH DRM the same way Chromium does. For reliable iPhone web playback, provide an HLS (.m3u8) backup line for the same match.
