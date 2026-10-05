# iOS playback repair and verification

Read `IOS_PLAYBACK_AUDIT.md` for the investigation written before editing the player, including the current protected API's DASH/ClearKey exclusion and absent HLS backups. This change does not make those excluded DASH-only events playable.

## Implementation

- `user_app/web/index.html`: canonical source aliases, known manifest MIME for opaque proxy URLs, asynchronous failure/startup/stall fallback, autoplay gesture feedback and cancellation of stale playback work. An eligible selected DASH line still uses Shaka; iPhone alternatives prefer an actual supplied HLS line. No URL suffix rewriting or MPD-to-HLS conversion.
- `user_app/lib/screens/ios_player_page.dart`: native iOS WKWebView using the same HTML player, inline media configuration, local asset navigation restrictions, JSON-escaped arguments and a whitelist of non-sensitive analytics metadata. Close/back dismisses and stops playback.
- `native_player_io.dart` / `native_player_web.dart`, `screens/home_page.dart`, `screens/player_page.dart`: context-aware iOS launch; Android MethodChannel arguments and Media3 implementation remain intact.
- `user_app/pubspec.yaml`: explicit WK implementation dependency and embedded HTML asset.
- `scripts/generate_embedded_player.py`, `user_app/assets/embedded_player.html`: deterministic asset generation from the Safari player; no Flutter bootstrap or external analytics initialization in the embedded asset. Regenerate after every web player change.
- `scripts/test_web_player.mjs`: executes the real player IIFE with controlled DOM/media/timers to test asynchronous engine selection and fallback failures.
- `admin_app/lib/screens/live_links_page.dart`: shared DASH notice in Add/Edit Server explaining HLS backup and reachability-only health checks; source picker/import/save logic stays intact.
- `.github/workflows/build-apks.yml` / `deploy-web.yml`: shared-asset and player regression gates before Flutter analysis/build. APK workflow also compiles an unsigned iOS simulator Viewer on macOS to check native dependencies; this is not a distributed iOS release.

No Android Kotlin, Worker, Supabase schema/function, upstream headers, DRM keys or public-feed source changes are part of this repair.

## Automated checks

From repository root:

```sh
python3 scripts/generate_embedded_player.py --check
node scripts/test_web_player.mjs
```

Flutter CI runs the existing analyzer gate (`flutter analyze --no-fatal-infos`), any checked-in Dart tests, Android Admin/Viewer builds and web compilation. The macOS job creates the untracked iOS platform and compiles the Viewer simulator without signing. Build success verifies compilation and the mocked playback state machine; it does not verify a real codec, key system or device decode.

## Real iPhone/iPad Safari checks

1. Open the deployed web Viewer in Safari, refresh to the latest release and record iOS version, match/line label and Viewer version. Do not publish protected tokens or upstream URLs.
2. Play an authorized compatible HLS source. Confirm picture/audio, inline/fullscreen, line selection, quality menu and Back.
3. Where a safely delivered DASH source is available, on modern WebKit select it explicitly and verify Shaka manifest/init/media requests and a `playing` event. On older iOS without MSE/MMS, verify a supplied HLS backup is selected. **The current API excludes MPD, so this direct DASH test requires a controlled authorized fixture or future secure DASH delivery; adding a raw Viewer URL is not a workaround.**
4. In a controlled local fixture, make DASH fail or stall and supply an HLS alternative for the same content. Verify one automatic switch, no indefinite spinner, and no stale switch after manually selecting a line or opening another match.
5. Block autoplay: verify Tap Play retains the selected healthy line. Tap it to start. Simulate format/DRM/load errors separately; they should use a supplied alternative.
6. Remove all alternatives: verify an actionable failure message. It must not claim to have converted the MPD. The two live DASH-only matches currently have no eligible backup.
7. On macOS Safari's Develop menu, inspect the connected device privately. For each authorized manifest/init/segment request check status, MIME, CORS, final HTTPS URL, redirect result and request headers. Inspect MPD codecs, ContentProtection, BaseURL and SegmentTemplate resolution. Record sanitized error codes/metadata only; do not export raw URLs/keys/headers to telemetry or the repository.

## Native iOS WKWebView checks

On a Mac with Xcode and a connected device, create the iOS platform (`cd user_app && flutter create --platforms=ios .`), restore app bundle/signing configuration as needed, and run the Viewer. Verify the same media cases plus route dismissal, background/foreground behavior, inline playback and engine CDN reachability. The native wrapper replaces the missing Android-only MethodChannel path; it does not bypass the protected API's source eligibility.

## Android regression checks

Install the new Viewer APK and confirm existing authorized HLS playback, line/quality controls and native fullscreen. With a controlled authorized DASH fixture, confirm Media3's MPD and ClearKey behavior stays as before. Android player source and its explicit MPD/HLS MIME handling are unchanged. The current protected API's global MPD exclusion is a pre-existing delivery limitation, not an iOS-only filter introduced by this fix.

## When no HLS source exists

First obtain an authorized compatible HLS source for the same event and add it through the existing Admin source picker/manual server flow. Otherwise a media service must ingest and package the source: supported clear fMP4 can potentially be repackaged, incompatible codecs require transcoding, and encryption requires authorized DRM/decryption and HLS/FairPlay packaging as appropriate. HLS manifest rewriting in the existing Worker is not transcoding. A secure DASH proxy would separately need nested-resource rewriting and DRM handling before the current delivery guard could be removed. No such service has been deployed by this repair.
