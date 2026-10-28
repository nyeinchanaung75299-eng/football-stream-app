// A bounded relay for the channel image host that is unreachable on some
// mobile networks. Keep this independent from the authenticated media proxy.
export async function GET(request) {
  const headers = {
    'Access-Control-Allow-Origin': '*',
    'X-Content-Type-Options': 'nosniff',
  };
  const url = new URL(request.url).searchParams.get('url');
  let source;
  try { source = new URL(url); } catch (_) {
    return new Response('Invalid image URL', { status: 400, headers });
  }
  const fotmob = source.hostname === 'images.fotmob.com' &&
    /^\/image_resources\/logo\/[a-zA-Z0-9/_-]+\.(png|jpg|jpeg|webp)$/.test(source.pathname);
  const wikimedia = source.hostname === 'thumb.wikimedia.org' &&
    /^\/wikipedia\/commons\/thumb\/[a-zA-Z0-9/_%().-]+\.png$/.test(source.pathname);
  if (source.protocol !== 'https:' || source.port || source.username || source.password ||
      source.search || !(fotmob || wikimedia)) {
    return new Response('Unsupported image host', { status: 400, headers });
  }
  try {
    const response = await fetch(source, {
      redirect: 'error',
      signal: AbortSignal.timeout(7000),
      headers: { Accept: 'image/png,image/jpeg,image/webp' },
    });
    const type = (response.headers.get('Content-Type') || '').split(';')[0].trim().toLowerCase();
    if (!response.ok || !['image/png', 'image/jpeg', 'image/webp'].includes(type)) {
      await response.body?.cancel();
      return new Response('Image unavailable', { status: 502, headers });
    }
    if (Number(response.headers.get('Content-Length') || 0) > 256 * 1024) {
      await response.body?.cancel();
      return new Response('Image too large', { status: 502, headers });
    }
    const reader = response.body.getReader();
    const chunks = [];
    let size = 0;
    try {
      while (true) {
        const part = await reader.read();
        if (part.done) break;
        size += part.value.byteLength;
        if (size > 256 * 1024) return new Response('Image too large', { status: 502, headers });
        chunks.push(part.value);
      }
    } finally { await reader.cancel().catch(() => {}); }
    const body = new Uint8Array(size);
    let offset = 0;
    for (const chunk of chunks) { body.set(chunk, offset); offset += chunk.byteLength; }
    return new Response(body, { status: 200, headers: {
      ...headers, 'Content-Type': type, 'Cache-Control': 'public, max-age=86400',
    } });
  } catch (_) {
    return new Response('Image unavailable', { status: 502, headers });
  }
}
