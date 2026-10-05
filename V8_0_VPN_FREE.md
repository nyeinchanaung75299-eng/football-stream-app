# V8.0 VPN-Free architecture

This release does not bypass VPN, ISP, geo, DNS, DRM, or host access controls.

It improves direct-connect reliability:
- HLS (.m3u8) is preferred before DASH/direct/FLV when health is equal.
- Android Media3 already falls back to the next configured line when playback fails.
- Web now also automatically tries the next configured line after a real playback failure.
- Viewer has a VPN-Free Diagnostics screen from the network-check icon.
- Diagnostics test Supabase, Soco, and a small sample of active stream hosts.
- Stream probes only read an initial response chunk; they do not relay or download video.

Interpretation:
- Supabase FAIL: change the API/backend endpoint or network route.
- Soco FAIL: third-party source is unavailable on that network.
- Stream host FAIL: add an authorized globally reachable HLS/CDN backup.
- Web warning can be browser CORS even when the same host is reachable in Android.

Recommended production setup:
1. Keep Supabase for data/realtime.
2. Make HLS/HTTPS the primary video format.
3. Configure at least two authorized stream/CDN origins for important matches.
4. Keep DASH/FLV as backups when needed.
5. Do not use Edge Functions as a full video relay.
