import { accessSync } from 'node:fs';
import { createServer } from 'node:http';
import { fileURLToPath } from 'node:url';
import handler from 'serve-handler';

const assets = fileURLToPath(new URL('./public', import.meta.url));
accessSync(new URL('./public/index.html', import.meta.url));

const server = createServer(async (request, response) => {
  if (request.method !== 'GET' && request.method !== 'HEAD') {
    response.writeHead(405, { Allow: 'GET, HEAD' }).end();
    return;
  }
  const path = request.url.split('?', 1)[0];
  if (path === '/health') {
    response.writeHead(200, {
      'Cache-Control': 'no-store',
      'Content-Type': 'application/json; charset=utf-8',
    }).end('{"ok":true}');
    return;
  }
  response.setHeader('Cache-Control', path === '/' ||
    path === '/index.html' || path === '/flutter_bootstrap.js' ||
    path === '/version.json' || path === '/flutter_service_worker.js' ?
    'no-cache' : 'public, max-age=300');
  if (path === '/') request.url = '/index.html';
  try {
    await handler(request, response, {
      public: assets,
      cleanUrls: false,
      directoryListing: false,
      symlinks: false,
    });
  } catch {
    if (response.headersSent) response.destroy();
    else response.writeHead(500).end();
  }
});
server.listen(Number(process.env.PORT ?? 3000), '0.0.0.0');
