# Admin detector, guide clock and relay usage

Release targets: Admin 2.5.24 and Viewer 9.8.13.

- Remove the CI reference to the retired LiveXTV test; no retired provider is restored.
- Native CricHD quick selection requires a bounded 2xx complete live HLS playlist check, current-document video association, one candidate and a three-second quiet period after page completion. Finite/ad/ambiguous/unassociated URLs remain manual candidates. Playlist validity is not decoded-video or content-identity proof. No cookies, Authorization or DRM keys are copied. Redirects and response size are bounded; no media segments are downloaded by the verifier.
- URL edits, navigation, clear/reload and disposal cancel selection/verification and invalidate old results. Web URL editing is disabled while scanning and late results are generation/address checked.
- TV Schedule and My Channels update cached time labels at programme/minute boundaries without network polling. Hidden tabs and background apps stop the local timer.
- Guide matching indexes timestamps, normalizes only the requested kickoff window and memoizes results on each guide snapshot. Schedule cards build lazily. Existing replay, sport, alias and match-window rules are retained.
- Viewer link reads and Admin explicit source reads/scans use a recent verified Cloudflare route or one shared, bounded public health probe before selecting a route. Failed primary reads use Vercel sequentially. Empty successful results remain authoritative and no provider/browser scan is speculatively raced. Public Admin catalogues/guides prefer the independent metadata gateway even when authentication needs Vercel.
- Protected video keeps the existing Cloudflare-first, failure-only Vercel policy; normal Channels still require explicit opt-in to Vercel. Website CDN entry and installed-package/signing continuity remain intact.

## Local verification

Viewer suite: 137 tests. Admin full suite: 180 tests before the final header-preservation regression test; that additional test also passes in the rerun detector suite (181 expected in CI). Shared Web player and native source-session checks pass. The previously broken performance command now passes with the two remaining source test files. Analyze has existing informational deprecations only. CI verifies the exact release commit again before publication.

Synthetic guide benchmark (same process/device, same 180 channels, 17,280 programmes and 36 match queries; exact output equality checked):

{
  "baselineWarmMedianMs": 45.262,
  "samples": [
    {
      "beforeMs": 85.433,
      "indexedColdMs": 90.099
    },
    {
      "beforeMs": 80.45,
      "indexedColdMs": 82.296
    },
    {
      "beforeMs": 96.227,
      "indexedColdMs": 88.37
    },
    {
      "beforeMs": 100.115,
      "indexedColdMs": 86.677
    },
    {
      "beforeMs": 74.151,
      "indexedColdMs": 76.562
    }
  ],
  "baselineMedianMs": 85.433,
  "indexedColdMedianMs": 86.677,
  "channels": 180,
  "programmes": 17280,
  "matchQueries": 36,
  "baselineBatchMs": 140.093,
  "indexedColdBatchMs": 112.28,
  "indexedWarmMedianMs": 3.377,
  "sameResults": true
}

Cold median is approximately unchanged; repeated matching improves. These figures are not whole-screen, device-network or aggregate billing measurements. Physical phone verification and private Admin production mutations are not claimed from unit tests.
