# V7.6 Web playback + Soco polish

Web player:
- Fixed a JavaScript regression where hideControls/revealControls were referenced but missing.
- That regression could open a black player screen before loadSource() ran.
- Added native Safari HLS playback path for iPhone/iPad.
- Added clearer browser playback error text.
- Existing Android Media3 behavior is unchanged.

Soco:
- Web source is now constrained to a tablet-sized centered surface instead of stretching edge-to-edge on desktop.
- Android source is clipped into a cleaner rounded surface.
- External-source content itself is not modified or copied.

Important:
A static GitHub Pages site cannot bypass a source's geo-blocking, DNS restrictions, CORS, or protected Referer/Origin requirements. Those cases require a permitted server-side relay/proxy or a source that is browser-accessible.
