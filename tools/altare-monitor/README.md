# NCA Source Monitor

Start with Node.js 22 or newer and `npm start`. The server binds to `0.0.0.0` using Altare's `PORT` variable. Local default is 3000.

## Altare GitHub app

| Field | Value |
| --- | --- |
| App name | `nca-source-monitor` |
| Repository | `nyeinchanaung75299-eng/football-stream-app` |
| Branch | `altare-monitor` |
| Root directory | `tools/altare-monitor` |
| Runtime | Node.js |
| Start command | `npm start` |
| Health-check path | `/health` |

The app checks the public Live 2 and Channels catalogues, the public source feed and GitHub repository-tree metadata on startup and every five minutes. Channels reports the count and warns if the list is empty. A feed timestamp or provider refresh age of 30 minutes enters warning status. Open `/` for a dashboard or `/status` for a machine-readable response. Altare should check `/health` for process liveness. The upstream status endpoint deliberately returns HTTP 503 during warnings or failures.

The service uses public HTTPS endpoints and needs no secrets. Its checks do not measure video playback or Myanmar carrier connectivity.
