# V7.3 Web Viewer

The Viewer now builds for Android and Web from the same Flutter source.

Web playback:
- HLS (.m3u8): Shaka Player
- DASH (.mpd): Shaka Player
- DASH ClearKey: keyID/keyData
- FLV (.flv): mpegts.js when supported by the browser
- MP4/direct: browser video playback
- Multiple lines: line picker plus in-player server switcher
- Adaptive HLS/DASH: Auto plus available manual qualities
- Fullscreen and Fit/Fill controls

Expected GitHub Pages URL:
https://nyeinchanaung75299-eng.github.io/football-stream-app/

If Pages is unavailable for the repository/account, the workflow still produces the Football-Viewer-V7.3-Web artifact.

Browser limitation:
Chrome cannot freely spoof protected Referer or Origin headers. A source that requires those headers may work in Android but fail in Chrome unless the provider allows browser CORS/referrer access or an authorized proxy is used.
