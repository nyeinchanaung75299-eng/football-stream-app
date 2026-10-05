# NCA iPhone / MPD investigation — before implementation

> Update (6 October 2026): the Cloudflare gateway now has a protected
> non-DRM DASH/MPD rewrite path for manifest BaseURL/SegmentTemplate media.
> The original findings below describe the earlier state at commit
> `f809294`. Keyed/ClearKey DASH remains intentionally excluded from the
> public Viewer unless a separately authorized compatible delivery path exists.

Audited repository `nyeinchanaung75299-eng/football-stream-app` at `f8092942036af709796222a672e0a05c79292629` on 5 October 2026. This report was written before editing the iOS/player code. Git history, current player/backend source, deployed Worker version and read-only Supabase metadata were inspected. Raw upstream URLs, request headers, keys and playback tokens were not exported.

## Confirmed causes and limits of the evidence

1. **Current protected delivery excludes MPD and keyed streams on every platform.** `cloudflare/public-api/src/index.js`, `protectedClientLinks()` excludes `dash`, `mpd`, URLs containing `.mpd`, and rows containing `key_id`/`key_data`. `advertisedLinkCount()` and migration `20261005150000_exclude_unrewritten_dash_from_public_counts.sql` apply matching exclusions. This is an intentional security boundary: HLS child URLs are rewritten through the protected proxy, but DASH BaseURL/SegmentTemplate resources are not. HomePage resolves only protected API links. There is no Android/iOS conditional in this filter. Therefore the reported working Android MPD is from a different installed version or entry path; current source alone does not establish that the same MPD is delivered to the current Android and iPhone Viewer.
2. **Native iOS has no player handler.** The IO implementation calls Android's `football_stream/native_player` MethodChannel. Android supplies MainActivity/Media3 handlers; no corresponding iOS handler exists in the complete fetched history. A separately generated native iOS app would encounter a missing plugin handler. This affects native iOS playback generally, and is distinct from Safari format support.
3. **Browser handling has reproducible bugs.** With extensionless protected URLs, declared aliases `mpd` and `m3u8` are returned unchanged by `sourceType()`, while engine branches require `dash` and `hls`. Running the actual function confirms that the alias lines miss the intended Shaka/native-HLS branch. All `video.play()` rejections are swallowed; there is no bounded startup timeout. Error events and rejected Shaka loads can schedule duplicate fallbacks, and the delayed fallback does not recheck the playback token. These bugs can leave playback stalled or interrupt a later selection.
4. **No HLS backup exists for the two current active DASH events.** Read-only aggregate metadata found two active, unexpired MPD rows, both with ClearKey fields, and zero clear DASH rows. Romania vs Sweden (`2e4bb919-d6e8-424a-8551-8d235ed94d1b`) and France vs Belgium (`95e1efa8-7ada-4146-bf0d-370dcdd8210c`) each have one DASH row and zero eligible, unexpired, non-DRM HLS/MP4 backups. Client fallback cannot select a source that does not exist.

The precise failing manifest's HTTP status, codec, encryption profile and segment decode result remain **unverified**. The user has not supplied an affected line label, iOS version or installed Android version. The synchronous database HTTP extension is not installed; only asynchronous `pg_net` is installed. No diagnostic extension/function, asynchronous network write or secret read was added. It would be incorrect to claim a proven codec/CORS/DRM failure for a particular stream from these metadata checks.

## Actual players and platform differences

| Surface | Engine and source path |
| --- | --- |
| Android APK | `native_player_io.dart` → MethodChannel → `android_patch/MainActivity.kt` → `NativePlayerActivity.kt`. Media3 ExoPlayer with explicit DASH/HLS MIME types; FrameworkMediaDrm ClearKey when supplied. |
| iPhone/iPad Safari web Viewer | `native_player_web.dart` → `web/index.html`. Native HTML video for HLS when supported; pinned Shaka **5.2.12** for DASH/HLS adaptive playback; mpegts.js **1.7.3** for supported FLV. No dash.js or hls.js. |
| Native iOS before this fix | Same IO MethodChannel as Android, without an iOS handler. Retained `PlayerPage` WebView code is not a native iOS streaming engine. |

Safari's native `<video src="…mpd">` is not a DASH manifest player. Modern WebKit ManagedMediaSource can enable Shaka DASH playback, subject to actual codec, encryption and device support. iPhone gained MMS in Safari 17.1; older iOS must use compatible native HLS. MMS presence alone is not proof that a particular stream can play. [WebKit Safari 17.1](https://webkit.org/blog/14735/webkit-features-in-safari-17-1/), [Shaka v5.2.12 platform matrix](https://github.com/shaka-project/shaka-player/blob/v5.2.12/README.md), [Apple HLS](https://developer.apple.com/documentation/http-live-streaming).

The missing `disableremoteplayback` HTML attribute is **not a demonstrated cause**: the pinned Shaka implementation sets the video property itself when using MMS without an alternate AirPlay source. [Pinned MediaSourceEngine](https://github.com/shaka-project/shaka-player/blob/v5.2.12/lib/media/media_source_engine.js#L217).

## DRM and codecs

Stored ClearKey fields do not prove a Widevine-only or FairPlay manifest. Android's platform DRM path differs from Safari EME/FairPlay. Shaka 5.2.12 contains a real WebCrypto ClearKey decryptor, including CENC/CBCS handling, so “Safari can never decrypt ClearKey” would be too broad. However its DRM initialization still checks decoding/key-system capabilities; `crypto.subtle` presence does not prove an end-to-end playable stream. Current protected API supplies neither raw MPD nor client ClearKey values. [Pinned software decryptor](https://github.com/shaka-project/shaka-player/blob/cae0ceb638a981a32263df56a011af545915afe9/lib/media/clearkey_webcrypto_decryptor.js), [Pinned DrmEngine](https://github.com/shaka-project/shaka-player/blob/cae0ceb638a981a32263df56a011af545915afe9/lib/drm/drm_engine.js#L1115).

Apple's native protected streaming path uses appropriately packaged HLS/FairPlay. A Widevine license or ClearKey field cannot simply be relabeled as FairPlay. AVC (`avc1`), HEVC (`hvc1`/`hev1`) and audio support depend on packaging, profile and device. Exact manifest codecs have not been retrieved, so no specific codec mismatch is claimed. [Apple streaming](https://developer.apple.com/streaming/), [Apple FairPlay](https://developer.apple.com/streaming/fps/), [Android Media3 supported formats](https://developer.android.com/media/media3/exoplayer/supported-formats).

## Request/proxy audit

- Worker is deployed at version `3f0c4640` (100% traffic, last deployed 15:00:47 UTC). Source and deployment metadata confirm the global DASH delivery guard.
- HLS is fetched over the HTTPS gateway, with supplied server-side Referer/Origin and forwarded Range; upstream redirects are followed. User-Agent follows the client request with a default fallback, so an upstream UA restriction remains possible but is not proven.
- HLS manifest responses use `application/vnd.apple.mpegurl`; playlists, segments and key URIs are rewritten to protected child URLs. CORS permits GET/HEAD/OPTIONS and Range, exposes Content-Length/Content-Range/Accept-Ranges, and includes no-referrer/nosniff headers. This source audit does not prove the response of a particular live child resource.
- MPD BaseURL, SegmentTemplate and `.m4s` requests are not rewritten or converted. Exact upstream MPD/segment CORS, Content-Type, redirects, HTTPS/mixed content and Referer/Origin/UA behavior remain unverified. The current API refuses to deliver these MPD rows rather than expose an unsafe raw fallback.
- Supabase stores the Admin configuration; its health function checks limited HTTP reachability. A green Admin health result is not a Safari decoder/segment/DRM test.

## Admin source handling

`admin_app/lib/screens/live_links_page.dart` detects/imports HLS, DASH, FLV and MP4, exposes DASH ClearKey configuration, and preserves header/source picker settings. Source quality import can select an actual HLS URL when the provider offers one. It does not convert MPD to HLS. The restored Highlights menu and current Pick Big Matches, Manual Match, Matches & Scores, Stream Servers and source/security features are independent of this player fix.

## Implementation scope decided from the evidence

Repair the browser alias/MIME selection, bounded startup/stall handling, autoplay feedback and token-scoped fallback. Attempt supported DASH through the existing Shaka engine; on failure choose a supplied compatible HLS backup. Add native iOS WKWebView playback using the same maintained browser player rather than invoking an absent Android channel. Keep Android Media3 source unchanged. Add meaningful asynchronous regression tests and build gates.

Do not remove the protected DASH guard or distribute keys/raw sources. For the two currently DASH-only events, an authorized HLS source or a secure server packaging pipeline is required. A clear, supported fragmented-MP4 DASH source may be repackaged to HLS without video re-encoding; incompatible codecs require transcoding, and protected sources require authorized decryption/re-encryption/license integration. A stateless Cloudflare Worker is not a media transcoder; renaming a suffix is not conversion. No paid media service or DRM licensing infrastructure is provisioned by this fix.

Real Safari/WKWebView playback still requires device testing. Android compilation/regression fixtures cannot prove iPhone decoding. Native iOS builds require macOS/Xcode. [Flutter iOS setup](https://docs.flutter.dev/platform-integration/ios/setup).

## Supplemental safe live HLS check

At 17:00:36 UTC, a current eligible HLS line for public match `97a6d3d1-765f-44d5-89db-3e35eabb019b` was requested through the primary protected gateway using both iPhone Safari and Android Chrome User-Agent strings. Both returned: stream list **200**, valid HLS manifest **200**, MIME `application/vnd.apple.mpegurl`, wildcard CORS, and all three child references protected HTTPS URLs. A first child Range request returned **206**, wildcard CORS and Content-Range with MPEG-TS-looking bytes (`application/octet-stream`). No URLs/tokens/payloads were printed or saved. This sample shows no iOS-UA block at the gateway for that HLS line; it does not test real Safari decoding or the excluded MPD events.
