import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const project = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
await fs.mkdir(path.join(project, 'work'), { recursive: true });
const root = await fs.mkdtemp(path.join(project, 'work', 'qa-'));
await fs.cp(path.join(project, 'site'), path.join(root, 'site'), { recursive: true });
const config = JSON.parse(await fs.readFile(path.join(project, 'pages.json'), 'utf8'));
config['shared-form'] = { title: 'Shared form', path: '/shared-form/', order: 0, fields: { recordId: 'text', done: 'boolean', title: 'text', reference: 'text' } };
await fs.mkdir(path.join(root, 'site', 'shared-form'));
await fs.writeFile(path.join(root, 'site', 'shared-form', 'index.html'), `<!doctype html>
<html data-sync-page="shared-form"><body>
<input data-sync="recordId" disabled>
<input type="checkbox" data-sync="done" disabled>
<input data-sync="title" disabled>
<input data-sync="reference" disabled>
<p data-sync-status role="status" aria-live="polite"></p>
<script src="/shared/sync.js"></script>
</body></html>`);
config['other-page'] = { title: 'Other <page>', path: '/other-page/', order: -1, fields: { title: 'text' } };
await fs.mkdir(path.join(root, 'site', 'other-page'));
await fs.writeFile(path.join(root, 'site', 'other-page', 'index.html'), '<html data-sync-page="other-page"><input data-sync="title"></html>');
await fs.writeFile(path.join(root, 'pages.json'), JSON.stringify(config));
const base = 'http://127.0.0.1:18081';
const assembly = process.env.WEBSHARE_APP || path.join(project, 'app', 'WebShare.dll');
let server;
let serverOutput = '';
async function start() {
  server = spawn('dotnet', [assembly], { env: { ...process.env, WEBSHARE_ROOT: root, WEBSHARE_PORT: '18081' }, stdio: ['ignore', 'pipe', 'pipe'] });
  await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('Server startup timeout')), 15000);
    let output = '';
    server.stdout.on('data', data => { output += data; serverOutput += data; if (output.includes('Now listening on:')) { clearTimeout(timer); resolve(); } });
    server.stderr.on('data', data => { output += data; serverOutput += data; });
    server.once('exit', code => { clearTimeout(timer); reject(new Error(`Server exited ${code}: ${output}`)); });
  });
}
async function stop() { const exit = once(server, 'exit'); server.kill(); await exit; }
async function checkConfig() {
  const process = spawn('dotnet', [assembly, '--check'], { env: { ...globalThis.process.env, WEBSHARE_ROOT: root }, stdio: ['ignore', 'pipe', 'pipe'] });
  let output = '';
  process.stdout.on('data', data => { output += data; });
  process.stderr.on('data', data => { output += data; });
  const [code] = await once(process, 'exit');
  return { code, output };
}
async function state(page = 'shared-form') { return (await fetch(base + '/api/state/' + page)).json(); }
async function change(key, value, page = 'shared-form', headers = {}) {
  return fetch(base + '/api/state/' + page, { method: 'PATCH', headers: { 'Content-Type': 'application/json', ...headers }, body: JSON.stringify({ key, value }) });
}
async function subscribe() {
  const controller = new AbortController();
  const response = await fetch(base + '/api/events/shared-form', { signal: controller.signal });
  assert.equal(response.status, 200);
  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let text = '';
  return { close: () => controller.abort(), async next() {
    const timer = setTimeout(() => controller.abort(), 4000);
    try {
      while (true) {
        const boundary = text.indexOf('\n\n');
        if (boundary >= 0) {
          const event = text.slice(0, boundary); text = text.slice(boundary + 2);
          if (event.startsWith('data: ')) return JSON.parse(event.slice(6));
          continue;
        }
        const chunk = await reader.read();
        if (chunk.done) throw new Error('Unexpected stream end');
        text += decoder.decode(chunk.value, { stream: true });
      }
    } finally { clearTimeout(timer); }
  } };
}
try {
  assert.equal((await checkConfig()).code, 0);
  config['other-page'].fields.title = 'unsupported';
  await fs.writeFile(path.join(root, 'pages.json'), JSON.stringify(config));
  const invalid = await checkConfig();
  assert.notEqual(invalid.code, 0);
  assert.match(invalid.output, /other-page.*title/);
  config['other-page'].fields.title = 'text';
  await fs.writeFile(path.join(root, 'pages.json'), JSON.stringify(config));
  await start();
  const home = await (await fetch(base + '/')).text();
  assert.ok(home.includes('Other &lt;page&gt;'));
  assert.ok(home.includes('Shared form'));
  assert.ok(home.indexOf('Other &lt;page&gt;') < home.indexOf('Shared form'));
  assert.equal(await (await fetch(base + '/index.html')).text(), home);
  assert.deepEqual(await (await fetch(base + '/api/health')).json(), { status: 'ready', pages: Object.keys(config).length, sharedPages: Object.values(config).filter(page => Object.keys(page.fields || {}).length).length });
  const pages = await (await fetch(base + '/api/pages')).json();
  assert.equal(pages[0].id, 'other-page');
  assert.equal(pages.find(page => page.id === 'downloads').shared, false);
  assert.equal((await fetch(base + '/api/state/downloads')).status, 404);
  assert.equal((await fetch(base + '/codex-rules/')).status, 200);
  const rulesModule = await fetch(base + '/codex-rules/app.mjs');
  assert.equal(rulesModule.status, 200);
  assert.match(rulesModule.headers.get('content-type'), /javascript/);
  assert.equal((await fetch(base + '/api/state/codex-rules')).status, 404);
  const asset = await fetch(base + '/shared/sync.js');
  assert.equal(asset.headers.get('cache-control'), 'no-cache');
  assert.equal((await fetch(base + '/shared/sync.js', { headers: { 'If-None-Match': asset.headers.get('etag') } })).status, 304);
  assert.equal((await fetch(base + '/api/state/shared-form')).headers.get('cache-control'), 'no-store');
  const html = await (await fetch(base + '/shared-form/')).text();
  assert.equal((html.match(/data-sync="/g) || []).length, Object.keys(config['shared-form'].fields).length);
  assert.ok(html.includes('/shared/sync.js'));
  for (const route of ['/data/shared-form.json', '/pages.json', '/src/Program.cs', '/missing.html']) assert.equal((await fetch(base + route)).status, 404);
  const a = await subscribe(), b = await subscribe();
  assert.equal((await a.next()).revision, 0); await b.next();
  const id = '18446744073709551615';
  assert.equal((await change('recordId', id)).status, 200);
  assert.equal((await a.next()).values.recordId, id);
  assert.equal((await b.next()).values.recordId, id);
  const updates = await Promise.all([change('done', true), change('title', 'Example record'), change('reference', '12345678-abcd-abcd-abcd-123456789abc')]);
  assert.ok(updates.every(response => response.ok));
  const saved = await state();
  assert.equal(saved.values.done, true); assert.equal(saved.values.title, 'Example record'); assert.equal(saved.values.recordId, id);
  assert.equal(saved.values.reference, '12345678-abcd-abcd-abcd-123456789abc');
  assert.equal((await change('recordId', 'other', 'other-page')).status, 400);
  assert.equal((await state('other-page')).values.title, '');
  assert.equal((await change('missing', 'x')).status, 400);
  assert.equal((await change('done', 'true')).status, 400);
  assert.equal((await change('recordId', 'x'.repeat(1025))).status, 400);
  assert.equal((await change('recordId', 'x', 'shared-form', { Origin: 'https://unrelated.example' })).status, 403);
  await fs.mkdir(path.join(root, 'data', 'shared-form.json.tmp'));
  assert.equal((await change('recordId', 'must-not-save')).status, 500);
  assert.deepEqual(await state(), saved);
  await fs.rmdir(path.join(root, 'data', 'shared-form.json.tmp'));
  a.close(); b.close();
  await stop(); await start();
  assert.deepEqual(await state(), saved);
  const reconnect = await subscribe();
  assert.deepEqual(await reconnect.next(), saved); reconnect.close();
  console.log('PASS: catalog navigation, configuration diagnostics, health, conditional caching, shared form fixture, two subscribers, concurrent field updates, page isolation, validation, failed-write behavior, restart persistence, reconnect snapshot.');
} catch (error) {
  console.error(serverOutput);
  throw error;
} finally {
  if (server && server.exitCode === null) await stop();
  await fs.rm(root, { recursive: true, force: true });
}
