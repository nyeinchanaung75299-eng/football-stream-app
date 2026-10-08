# Isolated Vercel network-route test

[Deploy this test to Vercel](https://vercel.com/new/clone?repository-url=https%3A%2F%2Fgithub.com%2Fnyeinchanaung75299-eng%2Ffootball-stream-app%2Ftree%2Ftest-atom-vercel-route%2Fnetwork-tests%2Fvercel-backup&repository-name=nca-network-backup-test&project-name=nca-network-backup-test)

Select your own Vercel Team, leave the provided defaults, and deploy. Once it
is Ready, open the production project's `/network-check.html` on ATOM with VPN
off and copy the result back to the existing conversation.

Prepared for `nyeinchanaung75299-eng/football-stream-app`, following the ATOM
VPN-off result of 2026-10-08. All six Cloudflare routes timed out; GitHub was
reachable. This candidate has not been deployed or tested on ATOM.

Deploy as a separate Vercel project named `nca-network-backup-test` under the
user's intended team. No environment secrets, build step, or dependencies are
needed. Use Node.js 24 and expose the test deployment publicly so a phone can
test it without Vercel login. Existing APK and website playback are independent
of this project.

Only the existing public health, matches, stream configuration, and encrypted
`/p/` playback routes are forwarded. GET/HEAD/OPTIONS are supported. Request
headers containing cookies or authorization are never forwarded. Range headers
and streamed media responses are preserved. JSON, HLS, and DASH protected URLs
are rewritten to the test deployment origin, keeping subsequent media requests
on the tested host. The original Cloudflare Worker validates the encrypted
playback tokens; no keys are copied from its environment.

Verify `/health`, `/matches`, and `/backend-health` first, then the stream API,
manifest, and a small media range. Test from ATOM with VPN off before adding
any route to the application. This establishes route reachability, not
continuous playback or production video-hosting suitability. Vercel transfer
quotas and function durations still apply, and continuous FLV needs separate
consideration.

`/network-check.html` provides the same phone test and copyable report as the
GitHub diagnostic page, targeting this deployment and the GitHub mirror.

Deployment is currently blocked by the connected Vercel account's Team access
returning HTTP 403. Grant the connection access to the intended Team/Project
before deployment; do not paste authentication tokens in chat.
