import { isIP } from 'node:net';

const publicHeaders = {
  'Access-Control-Allow-Origin': '*',
  'X-Content-Type-Options': 'nosniff',
};
const reply = (message, status) => new Response(message, { status, headers: publicHeaders });
const legacyHosts = new Set(['images.fotmob.com', 'thumb.wikimedia.org']);
const maxImageBytes = 1024 * 1024;

export function imageSource(value) {
  let url;
  try { url = new URL(value); } catch (_) { return null; }
  if (url.protocol !== 'https:' || url.port || url.username || url.password ||
      isIP(url.hostname) || !url.hostname.includes('.') ||
      /(?:^|\.)(?:localhost|local|internal|test|invalid)$/.test(url.hostname)) return null;
  return url;
}

async function savedChannelImage(request, id) {
  const response = await fetch('https://football-public-api.nyeinchanaung75299-eng.workers.dev/channels', {
    signal: AbortSignal.timeout(7500),
    headers: { Accept: 'application/json' },
  });
  if (!response.ok) throw new Error('Channel catalog unavailable');
  const catalog = await response.json();
  const row = catalog.channels?.find(item => item.id === id);
  if (!row?.image_url) return null;
  let value = row.image_url;
  // Old rows use the first, host-limited relay URL. Unwrap only that URL.
  const legacy = new URL(value);
  if (legacy.origin === 'https://nca-network-backup-test.vercel.app' &&
      legacy.pathname === '/api/channel-logo' && legacy.searchParams.has('url')) {
    const original = imageSource(legacy.searchParams.get('url'));
    if (!original || !legacyHosts.has(original.hostname)) return null;
    value = original.href;
  }
  return imageSource(value);
}

export function imageType(data) {
  if (data.length >= 8 && data.subarray(0, 8).equals(Buffer.from('89504e470d0a1a0a', 'hex'))) return 'image/png';
  if (data.length >= 3 && data.subarray(0, 3).equals(Buffer.from('ffd8ff', 'hex'))) return 'image/jpeg';
  if (data.length >= 12 && data.toString('ascii', 0, 4) === 'RIFF' &&
      data.toString('ascii', 8, 12) === 'WEBP') return 'image/webp';
  return null;
}

async function downloadImage(source) {
  const upstream = await fetch(source, {
    redirect: 'error',
    signal: AbortSignal.timeout(7500),
    headers: { Accept: 'image/png,image/jpeg,image/webp' },
  });
  if (!upstream.ok || Number(upstream.headers.get('Content-Length') || 0) > maxImageBytes) {
    await upstream.body?.cancel();
    throw new Error('Image unavailable');
  }
  const reader = upstream.body.getReader();
  const parts = [];
  let size = 0;
  try {
    for (;;) {
      const part = await reader.read();
      if (part.done) break;
      size += part.value.byteLength;
      if (size > maxImageBytes) throw new Error('Image too large');
      parts.push(part.value);
    }
  } finally { await reader.cancel().catch(() => {}); }
  const body = Buffer.concat(parts.map(part => Buffer.from(part)), size);
  const type = imageType(body);
  if (!type) throw new Error('Invalid image');
  return new Response(body, { status: 200, headers: {
    ...publicHeaders,
    'Content-Type': type,
    'Cache-Control': 'public, max-age=3600',
  } });
}

export async function GET(request) {
  const query = new URL(request.url).searchParams;
  const id = query.get('id');
  try {
    let source;
    if (id && /^[0-9a-fA-F-]{36}$/.test(id)) {
      source = await savedChannelImage(request, id);
    } else if (!id && query.has('url')) {
      // Keep previously published URLs working without an open URL proxy.
      source = imageSource(query.get('url'));
      if (source && !legacyHosts.has(source.hostname)) source = null;
    }
    if (!source) return reply('Channel image unavailable', 404);
    return await downloadImage(source);
  } catch (error) {
    console.error('Channel image unavailable', { category: error?.code || error?.name || 'Error' });
    return reply('Channel image unavailable', 502);
  }
}
