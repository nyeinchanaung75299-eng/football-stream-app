# Admin 2.5.26 / Viewer 9.8.15

1. Channel metadata edits preserve disabled lines, independent Origin and prior health. Only changed playback fields invalidate probe results. Untouched lines send IDs only.
2. Channel + lines save in one SECURITY INVOKER/RLS transaction. Missing/deleted lines reject a stale edit; only explicitly removed IDs can be deleted. No delete/recreate backup path.
3. Viewer channel LIVE/NEXT and programme filters update at local programme boundaries, at most once a minute otherwise. Clock pauses in background; resume reuses the guide cache. No boundary API polling.
4. Corrected public Referer/Origin revalidates HLS, including a correction arriving during an old request. Stale checks cannot replace corrected results. Bounded to 8 candidates / 3 attempts each.
5. Same-document history updates preserve document readiness, clear old candidates and rescan. Real document navigation still invalidates old callbacks.
6. Native CricHD discovery starts in the on-device browser session with a Finding links screen. Verified playlists return to existing Copy/ADD quality cards. Source browser is available immediately and prompted after 10 seconds if verification/Play is needed. No verification bypass or credential export; no new server browser polling. Closing another route cannot be triggered by delayed discovery completion.
7. Highlights expose quality/link cards with Copy and ADD to the separate Highlights table. Repeat ADD of the same source line updates it; saved highlights can be deleted. Viewer Live toolbar opens published Highlights on demand. Only actual source formats/labels are shown; no invented resolution. Native playback forwards the public source headers, including User-Agent. Browser playback remains subject to browser CORS/header restrictions.
8. Copy all acknowledges success in its share sheet; preview/export do not send messages.
9. Both updaters offer Install, Save APK through Android's document picker, and Share APK. Every action follows SHA-256 verification. Manual check also offers Save/Share for the current release. No storage/photo permission was added.

Database migrations are additive and were rehearsed in a disposable PostgreSQL database, including forced second-line failure, missing line, disabled/health preservation, non-admin denial and anonymous execute denial. Production migrations preserve existing channel/line/highlight counts.

Repository team names, current stream/source choices and user-accepted match-deletion behavior are preserved. CricHD source verification and native file-picker/share interaction still need a phone check; cloud/widget tests cannot prove these device-specific flows. Public playlist reachability is not decoded video proof.
