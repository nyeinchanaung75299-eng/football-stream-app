# NCA six-priority update — Admin 2.5.28 / Viewer 9.8.17

## Data ownership and flow

GitHub committed exports → **Stream Hub** (`source_id=darkbyte`, unchanged) → **Repository Matches** (`source_id=repository`) → **Pick Big Matches / Live 2**. Repository synchronization reads the committed Hub event snapshot; it does not perform a second GitHub crawl. Admin Combat Sports reads the same Hub event snapshot without triggering source synchronization. Imported operator lines retain their existing ownership and deletion protections.

## Implemented changes

1. Pick Big Matches accepts metadata-only fixtures, deduplicates repeated imports, supports adding lines later, and supports explicit reimport after permanent deletion. Empty fixtures retain the existing Viewer NOT READY state.
2. Admin and Viewer Highlights use DasFootball's public offset-based catalog and search. Infinite scrolling deduplicates IDs and ends at the published last page. Article/video resolution is lazy. The public read-only `public-highlights` endpoint and `/highlights` Worker route whitelist metadata and native playback fields, without forwarding Admin credentials. Previously saved Highlights remain separately accessible. This is a video catalog, not a live fixture feed.
3. DarkByte Channels is displayed as Stream Hub. Existing source IDs are preserved. All eight registered GitHub repositories share the Hub sync, with per-origin revisions, bounded file reads, and last-good catalogs when one source is unavailable. Repo metadata publication isolates individual repository failures. Catalog reads are paginated rather than truncated by PostgREST's default row limit. New GitHub IDs are accepted by the existing details/import actions. Atomic catalog commits have a bounded service-only 45-second RPC budget, skip unchanged stream JSON writes, and reconcile presence by incoming IDs.
4. Repository Matches derives from Hub and freezes failed origins. The public Live 2 metadata uses the same present catalog as Admin, without a contradictory second expiry filter. Manual stream lines are preserved. Snapshot commits publish partial/unavailable status honestly.
5. Admin Tools has Combat Sports below Repository Matches: UFC, other MMA, Boxing and ONE Championship, category/status filters, search, pagination, source names, View Lines, copy and optional preview. Unknown clocks/status remain Unknown. Published ONE disciplines remain separate. A native URL or reachable playlist never implies verified video playback. Combat is not added to Viewer.
6. CricHD has separate Football and Combat controls, UFC/MMA/Boxing/ONE category filters, public schedule discovery and published numbered watch links connected to the existing detector. Football and combat metadata caches are separate. No change is made to Cloudflare verification, persistent browser sessions or detector wait behavior.

## Validation and limits

- Local Node tests cover each source format, checksum verification, failures, safe merging, Hub-only request scopes, public Highlights security and paging, CricHD metadata/watch-link routing, and the existing football detector contracts.
- Disposable PostgreSQL 17 replays the complete schema/migrations and security, import, deletion/reimport, snapshot, partial-origin, manual-line and Live 2 parity tests.
- Flutter tests cover source navigation, HL pagination and existing playback, new provider filters, Combat details, and switching CricHD football/combat/categories. Analyze has no errors/warnings; existing Flutter Material migration notices remain informational.
- The public DasFootball catalog and a publisher-linked public native MP4 were checked over HTTP. HTTP reachability is not a device playback test.
- CricHD currently publishes a UFC section with **no events**. No separate MMA/Boxing/ONE section was published at inspection. Tests use explicit fixtures; a live combat event's end-to-end detector/playback remains to be tested when the publisher provides one.
- Viewer CricHD is deliberately not implemented. Public schedule access does not establish per-viewer playback: Admin Cloudflare cookies are device-specific, player pages can require verification, and signed media URLs may expire or depend on request headers/IP. The existing working Admin detector remains the fallback.
- Physical Android device QA is not performed in this execution environment. Installation/rotation/full playback and the next available CricHD event must be checked on devices before calling those flows verified.

Both APKs need an update for their UI/client changes. Backend-only sync repairs also benefit installed older clients. NCA signing identity and main/feed branch roles are preserved; no white-label or license-manager changes are part of this scope.
