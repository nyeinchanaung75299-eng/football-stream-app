import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdir, mkdtemp, readFile, rename, rm, writeFile } from 'node:fs/promises';
import { join } from 'node:path';

const { feedCommit, sourceCommit } = JSON.parse(await readFile(
  new URL('./release.json', import.meta.url), 'utf8',
));
if (![feedCommit, sourceCommit].every(value => /^[a-f0-9]{40}$/.test(value))) {
  throw new Error('Pin the feed and source to full Git commit hashes.');
}
const origin = 'https://raw.githubusercontent.com/nyeinchanaung75299-eng/football-stream-app/';
const release = `${origin}${feedCommit}/public/web-release/`;

async function download(name) {
  const response = await fetch(release + name, {
    redirect: 'error',
    signal: AbortSignal.timeout(90_000),
  });
  if (!response.ok) throw new Error(`Could not download ${name}: ${response.status}`);
  return response;
}

const manifest = await (await download('latest.json')).json();
if (manifest.source_commit !== sourceCommit ||
    !/^[a-f0-9]{64}$/.test(manifest.sha256) ||
    !Number.isSafeInteger(manifest.size_bytes) || manifest.size_bytes <= 0) {
  throw new Error('The release manifest does not match the pinned source.');
}
const bytes = Buffer.from(await (await download('nca-web-build.tar.gz')).arrayBuffer());
if (bytes.length !== manifest.size_bytes ||
    createHash('sha256').update(bytes).digest('hex') !== manifest.sha256) {
  throw new Error('The release archive failed its size or SHA-256 check.');
}
const stage = await mkdtemp('.nca-web-');
try {
  const archive = join(stage, 'release.tar.gz');
  const viewer = join(stage, 'viewer');
  await writeFile(archive, bytes);
  await mkdir(viewer);
  execFileSync('tar', ['-xzf', archive, '--exclude=./admin', '--exclude=./operator',
    '--exclude=./operator-check', '-C', viewer]);
  const index = await readFile(join(viewer, 'index.html'), 'utf8');
  if (!index.includes('<base href="/">') ||
      !index.includes(`flutter_bootstrap.js?v=${sourceCommit.slice(0, 12)}-`)) {
    throw new Error('The Viewer entry point does not match the pinned release.');
  }
  await rm('public', { recursive: true, force: true });
  await rename(viewer, 'public');
} finally {
  await rm(stage, { recursive: true, force: true });
}
console.log(`Verified Viewer Web release ${sourceCommit.slice(0, 12)}`);
