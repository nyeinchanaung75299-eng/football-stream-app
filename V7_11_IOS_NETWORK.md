# V7.11 iOS line compatibility + network messaging

Web/iOS:
- Removed hard user-agent blocking for ClearKey DASH and FLV lines.
- Every configured line remains selectable.
- The browser now attempts playback first and reports a real playback error only if it fails.
- iPhone prefers an HLS backup only when the initially selected source is FLV.
- Existing custom Line and Quality menus remain unchanged.

Networking:
- Removed the app message that specifically told users to enable a VPN.
- Startup errors now suggest checking the connection or another network.

Important:
This does not bypass ISP, geo, DNS, CORS, DRM, or stream-host restrictions.
If a particular host is inaccessible on a network without VPN, the app itself cannot make that host reachable without an authorized alternate endpoint or source.
