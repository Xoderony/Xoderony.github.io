import fs from 'node:fs/promises';
import { constants } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { buildSnapshot, defaultSource, projectRoot, rejectLinks } from './publish-codex-rules.mjs';
import { validateSnapshot } from '../tests/codex-rules.mjs';

const serialize = value => JSON.stringify(value, null, 2) + '\n';
const content = ({ version, ...snapshot }) => JSON.stringify(snapshot);

// root/date are explicit isolation seams for the publisher's behavior tests.
export async function updateRules({ root = projectRoot, source = defaultSource(), date = new Date() } = {}) {
  root = path.resolve(root);
  const base = path.join(root, 'site', 'codex-rules');
  const releases = path.join(base, 'releases');
  const catalogPath = path.join(base, 'catalog.json');
  const lockPath = path.join(root, '.codex-rules-update.lock');
  await rejectLinks(releases);
  await rejectLinks(catalogPath);
  let lock;
  try { lock = await fs.open(lockPath, 'wx'); }
  catch (error) {
    if (error.code === 'EEXIST') throw new Error(`Another update holds ${lockPath}. If a previous window was forcibly closed, confirm no updater is running before removing this lock.`);
    throw error;
  }
  let temporary;
  let published;
  let switched = false;
  try {
    await lock.writeFile(`pid=${process.pid}\nstarted=${new Date().toISOString()}\n`);
    temporary = await fs.mkdtemp(path.join(root, '.codex-rules-stage-'));
    const originalCatalog = await fs.readFile(catalogPath, 'utf8');
    const catalog = JSON.parse(originalCatalog);
    if (!Array.isArray(catalog.versions) || !catalog.versions.includes(catalog.current) ||
        new Set(catalog.versions).size !== catalog.versions.length ||
        !catalog.versions.every(version => typeof version === 'string' && /^[a-z0-9][a-z0-9-]{0,63}$/.test(version))) {
      throw new Error('Invalid catalog; review catalog.json before updating.');
    }
    for (const version of catalog.versions) await rejectLinks(path.join(releases, `${version}.json`));
    const current = JSON.parse(await fs.readFile(path.join(releases, `${catalog.current}.json`), 'utf8'));
    const day = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
    const occupied = new Set([...catalog.versions, ...(await fs.readdir(releases)).map(name => name.replace(/\.json$/, ''))]);
    let number = Math.max(0, ...[...occupied].filter(value => value.startsWith(`${day}-v`)).map(value => Number(value.slice(day.length + 2))).filter(Number.isSafeInteger)) + 1;
    while (occupied.has(`${day}-v${number}`)) number++;
    const version = `${day}-v${number}`;
    const snapshot = await buildSnapshot(version, source);
    const stagedSnapshot = path.join(temporary, 'snapshot.json');
    await fs.writeFile(stagedSnapshot, serialize(snapshot), { flag: 'wx' });
    validateSnapshot(JSON.parse(await fs.readFile(stagedSnapshot, 'utf8')));
    if (content(snapshot) === content(current)) {
      console.log(`Unchanged: ${catalog.current}. No new snapshot created.`);
      return { changed: false, version: catalog.current };
    }
    const nextCatalog = { ...catalog, current: version, versions: [version, ...catalog.versions] };
    const stagedCatalog = path.join(temporary, 'catalog.json');
    await fs.writeFile(stagedCatalog, serialize(nextCatalog), { flag: 'wx' });
    // Detect a manual catalog change during preparation instead of overwriting it.
    if (await fs.readFile(catalogPath, 'utf8') !== originalCatalog) throw new Error('Catalog changed during update; retry after the other editor finishes.');
    const destination = path.join(releases, `${version}.json`);
    await fs.copyFile(stagedSnapshot, destination, constants.COPYFILE_EXCL);
    published = destination;
    // The staging directory is on the same volume, so readers see either catalog.
    await fs.rename(stagedCatalog, catalogPath);
    switched = true;
    console.log(`Published ${version}: ${snapshot.groups.reduce((sum, group) => sum + group.rules.length, 0)} rules, ${snapshot.skills.length} skills. Refresh /codex-rules/ to view it.`);
    return { changed: true, version };
  } finally {
    try {
      if (published && !switched) await fs.unlink(published);
    } finally {
      try { if (temporary) await fs.rm(temporary, { recursive: true, force: true }); }
      finally { await lock.close(); await fs.unlink(lockPath); }
    }
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    if (process.argv.length > 3) throw new Error('Usage: node scripts/update-codex-rules.mjs [codex-home]');
    await updateRules({ source: process.argv[2] || defaultSource() });
  } catch (error) {
    console.error(`Update failed: ${error.message}`);
    process.exitCode = 1;
  }
}
