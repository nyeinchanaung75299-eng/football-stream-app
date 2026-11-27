import { createServer } from 'node:http';

const intervalMs = 5 * 60_000;
const maximumAgeMinutes = 30;
const feed = 'https://raw.githubusercontent.com/nyeinchanaung75299-eng/football-stream-app/feed/public';
const live2 = 'https://nca25-live-relay.vercel.app/sources/repository/matches?limit=1&fresh=1';
const channels = 'https://nca25-live-relay.vercel.app/channels?fresh=1';
const statusFormat = new Intl.DateTimeFormat('en-GB', {
  timeZone: 'Asia/Yangon', dateStyle: 'medium', timeStyle: 'medium',
});

const report = (status, detail) => ({ status, detail });

async function getJson(url) {
  const response = await fetch(url, {
    headers: { Accept: 'application/json' },
    signal: AbortSignal.timeout(8_000),
    redirect: 'error',
  });
  if (!response.ok) {
    await response.body?.cancel().catch(() => {});
    throw new Error(`HTTP ${response.status}`);
  }
  const chunks = [];
  let size = 0;
  const reader = response.body?.getReader();
  try {
    if (!reader) throw new Error('Empty response');
    for (;;) {
      const { value, done } = await reader.read();
      if (done) break;
      size += value.length;
      if (size > 1_048_576) throw new Error('Response exceeded 1 MiB');
      chunks.push(value);
    }
    return JSON.parse(Buffer.concat(chunks).toString('utf8'));
  } finally {
    await reader?.cancel().catch(() => {});
  }
}

function ageMinutes(stamp, now) {
  const time = Date.parse(stamp);
  if (!Number.isFinite(time) || time > now + 60_000) return null;
  return Math.max(0, Math.floor((now - time) / 60_000));
}

const targets = [
  {
    id: 'live2', label: 'Live 2 API', url: () => live2,
    check(data) {
      if (data?.ok !== true || !Array.isArray(data.matches)) {
        return report('error', 'Invalid Live 2 response');
      }
      return report('ok', data.matches.length ? 'Fixture received' : 'API returned an empty fixture list');
    },
  },
  {
    id: 'channels', label: 'Channels API', url: () => channels,
    check(data) {
      if (data?.ok !== true || !Array.isArray(data.channels)) {
        return report('error', 'Invalid Channels response');
      }
      const count = data.channels.length;
      return count ? report('ok', `${count} channels listed`)
        : report('warning', 'API returned an empty channel list');
    },
  },
  {
    id: 'feed', label: 'Public source feed', url: stamp => `${feed}/source-status.json?t=${stamp}`,
    check(data, now) {
      const age = ageMinutes(data?.updated_at, now);
      if (age === null) return report('error', 'Missing or invalid feed timestamp');
      const sources = ['soco', 'yyzb', 'fawa', 'cola'];
      const stale = sources.filter(source => {
        const sourceAge = ageMinutes(data.sources?.[source]?.last_successful_update_at, now);
        return sourceAge === null || sourceAge >= maximumAgeMinutes;
      });
      const detail = `Feed updated ${age} min ago` + (stale.length ? ` · Check ${stale.join(', ')}` : '');
      return report(age >= maximumAgeMinutes || stale.length ? 'warning' : 'ok', detail);
    },
  },
  {
    id: 'tree', label: 'GitHub source metadata', url: stamp => `${feed}/repository-trees.json?t=${stamp}`,
    check(data, now) {
      const age = ageMinutes(data?.fetched_at, now);
      if (age === null || !data.repositories || Array.isArray(data.repositories)) {
        return report('error', 'Missing or invalid repository metadata');
      }
      const repos = Object.values(data.repositories);
      const ready = repos.filter(repo => typeof repo?.sha === 'string' && Array.isArray(repo.tree) && !repo.truncated).length;
      const detail = `${ready} of ${repos.length} sources available · Updated ${age} min ago`;
      return report(age >= maximumAgeMinutes || !ready || ready !== repos.length ? 'warning' : 'ok', detail);
    },
  },
];

let status = { status: 'starting', checked_at: null, checks: [] };

async function refresh() {
  const now = Date.now();
  const stamp = Math.floor(now / intervalMs);
  const checks = await Promise.all(targets.map(async target => {
    const started = performance.now();
    let result;
    try {
      const data = await getJson(target.url(stamp));
      result = target.check(data, Date.now());
    } catch (error) {
      const detail = error?.message?.match(/^HTTP \d{3}$/)?.[0] ??
        (error?.name === 'TimeoutError' ? 'Request timed out' : 'Could not read upstream');
      result = report('error', detail);
    }
    return { id: target.id, label: target.label, ...result, latency_ms: Math.round(performance.now() - started) };
  }));
  const overall = checks.some(check => check.status === 'error') ? 'error'
    : checks.some(check => check.status === 'warning') ? 'warning' : 'ok';
  status = { status: overall, checked_at: new Date().toISOString(), checks };
  console.log(JSON.stringify(status));
}

function sendJson(response, code, data) {
  response.writeHead(code, { 'Content-Type': 'application/json; charset=utf-8' });
  response.end(JSON.stringify(data));
}

function dashboard() {
  const checked = status.checked_at ? `${statusFormat.format(new Date(status.checked_at))} MMT` : 'Checking sources…';
  const items = status.checks.map(check => `
    <li><strong>${check.label}</strong> <span class="${check.status}">${check.status}</span>
    <div>${check.detail} · ${check.latency_ms} ms</div></li>`).join('');
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="refresh" content="60">
<title>NCA Source Monitor</title>
<style>
body{font:1rem/1.55 system-ui;margin:3rem auto;padding:0 1rem;max-width:42rem;background:#f5f7f6;color:#142a22}
h1{margin:0} ul{list-style:none;padding:0} li{background:white;border:1px solid #d6dfda;border-radius:8px;margin:.65rem 0;padding:1rem}
span{float:right;font-weight:700}.ok{color:#17653e}.warning{color:#805600}.error{color:#9b2525}
li div{margin-top:.3rem} a{color:#17653e}
</style>
</head>
<body>
<h1>NCA Source Monitor</h1>
<p>Last check · ${checked}</p>
<ul>${items}</ul>
<a href="/status">Status JSON</a>
</body>
</html>`;
}

const server = createServer((request, response) => {
  response.setHeader('Cache-Control', 'no-store');
  response.setHeader('X-Content-Type-Options', 'nosniff');
  if (request.method !== 'GET') {
    response.setHeader('Allow', 'GET');
    return sendJson(response, 405, { error: 'Method not allowed' });
  }
  if (request.url === '/health') return sendJson(response, 200, { ok: true });
  if (request.url === '/status') return sendJson(response, status.status === 'ok' ? 200 : 503, status);
  if (request.url !== '/') return sendJson(response, 404, { error: 'Not found' });
  response.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
  response.end(dashboard());
});

server.listen(Number(process.env.PORT ?? 3000), '0.0.0.0', () => {
  console.log(`NCA Source Monitor listening on ${server.address().port}`);
  void refresh();
  setInterval(refresh, intervalMs).unref();
});
