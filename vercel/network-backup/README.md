# NCA network backup

Production URL: https://nca25-live-relay.vercel.app

The production project is `nca25/nca25-live-relay`. This directory is the
reviewable source copy. Deploy with Node.js 24 using the included configuration.
Git auto-deployment requires the new Vercel account's GitHub Login Connection;
until that is connected, publish the reviewed files with the Vercel API.
No service-role key, playback secret, or OAuth credential belongs in this project.

The proxy forwards only fixed public API/source routes, authenticated Admin
functions, and Supabase Auth/Data/Storage endpoints to the existing Cloudflare
Worker. JWTs, publishable keys, methods, request bodies, and REST count headers
are preserved. Original Supabase authentication, Admin checks, and RLS remain
the authority. Request URLs, passwords, JWTs, stream keys, and response bodies
are never logged. Protected manifest/media URLs stay on the Vercel origin.

`/service-health` checks public service reachability from Vercel. It does not
verify Google Drive accounts, PostHog event delivery, or ChatGPT plugin OAuth.
Google Drive is not configured as an integration in the NCA application.

Metadata requests are bounded; media streams keep running after headers arrive.
Hobby function duration and transfer quotas still apply. Continuous FLV has a
300-second function connection ceiling; HLS/DASH use separate short requests.
Supabase WebSocket Realtime is not relayed by this HTTP proxy. Viewer metadata
continues to refresh by polling when the selected backend is Vercel.

ATOM mobile data with VPN off verified health, matches, stream API, DASH manifest
(HTTP 200) and a media sample (HTTP 206) on 2026-10-08 before app integration.

Viewer events resolve links through this relay only after a user requests them.
Protected video uses one Vercel URL per real line, including manifest children;
no alias copies appear in the line chooser. Channels use their normal route by
default and can opt into the relay for a single play attempt through the channel
menu. Catalogs, logos and EPG retain their independent metadata transport.
The relay uses its own `NCA-Relay/1.0` User-Agent for upstream requests instead of
forwarding client fingerprints that Browser Integrity Check rejects.
