import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import { updateRules } from '../scripts/update-codex-rules.mjs';
import { projectRoot } from '../scripts/publish-codex-rules.mjs';

const root = await fs.mkdtemp(path.join(projectRoot, '.codex-rules-test-'));
const source = path.join(root, 'source');
const base = path.join(root, 'site', 'codex-rules');
const releases = path.join(base, 'releases');
const catalogPath = path.join(base, 'catalog.json');
const date = new Date(2031, 3, 5, 12);
const update = () => updateRules({ root, source, date });
const readCatalog = () => fs.readFile(catalogPath, 'utf8');
const clean = async () => assert.deepEqual((await fs.readdir(root)).filter(name => name.startsWith('.codex-rules-')), []);

try {
  const liveCatalog = JSON.parse(await fs.readFile(path.join(projectRoot, 'site/codex-rules/catalog.json'), 'utf8'));
  const snapshot = JSON.parse(await fs.readFile(path.join(projectRoot, 'site/codex-rules/releases', `${liveCatalog.current}.json`), 'utf8'));
  await fs.mkdir(releases, { recursive: true });
  await fs.mkdir(source);
  const rules = '# Rules\n\n' + snapshot.groups.map(group => `## ${group.title}\n\n${group.rules.map(rule => '- ' + rule.text).join('\n')}\n`).join('\n');
  await fs.writeFile(path.join(source, 'AGENTS.md'), rules);
  for (const skill of snapshot.skills) {
    for (const file of [{ path: 'SKILL.md', content: skill.frontmatter + skill.body }, ...skill.files]) {
      const destination = path.join(source, 'skills', skill.id, file.path);
      await fs.mkdir(path.dirname(destination), { recursive: true });
      await fs.writeFile(destination, file.content);
    }
  }
  await fs.mkdir(path.join(source, 'skills/.system/ignored'), { recursive: true });
  await fs.writeFile(path.join(source, 'skills/.system/ignored/secret.bin'), 'not published');
  await fs.writeFile(path.join(releases, `${snapshot.version}.json`), JSON.stringify(snapshot));
  await fs.writeFile(catalogPath, JSON.stringify({ current: snapshot.version, versions: [snapshot.version] }));
  const original = await readCatalog();
  assert.deepEqual(await update(), { changed: false, version: snapshot.version });
  assert.equal(await readCatalog(), original);
  await clean();
  const change = rules.replace(snapshot.groups[0].rules[0].text, 'Test publishing changed rule.');
  await fs.writeFile(path.join(source, 'AGENTS.md'), change);
  assert.deepEqual(await update(), { changed: true, version: '2031-04-05-v1' });
  const first = await fs.readFile(path.join(releases, '2031-04-05-v1.json'), 'utf8');
  assert.ok(first.includes('Test publishing changed rule.'));
  assert.ok(!first.includes('not published'));
  assert.equal(JSON.parse(await readCatalog()).current, '2031-04-05-v1');
  assert.equal((await update()).changed, false);
  // An unregistered immutable file also reserves its version number.
  await fs.writeFile(path.join(releases, '2031-04-05-v2.json'), '{"reserved":true}');
  await fs.writeFile(path.join(source, 'AGENTS.md'), change.replace('changed rule', 'second change'));
  assert.deepEqual(await update(), { changed: true, version: '2031-04-05-v3' });
  assert.equal(await fs.readFile(path.join(releases, '2031-04-05-v1.json'), 'utf8'), first);
  await clean();
  const unchangedCatalog = await readCatalog();
  const unchangedFiles = await fs.readdir(releases);
  async function fails(pattern) {
    await assert.rejects(update(), pattern);
    assert.equal(await readCatalog(), unchangedCatalog);
    assert.deepEqual(await fs.readdir(releases), unchangedFiles);
    await clean();
  }
  await fs.mkdir(path.join(source, 'skills/new-personal-skill'));
  await fails(/Unregistered personal skills.*new-personal-skill/);
  await fs.rmdir(path.join(source, 'skills/new-personal-skill'));
  const skillRoot = path.join(source, 'skills/code-review');
  await fs.rename(skillRoot, path.join(source, 'saved-skill'));
  await fails(/Cannot read allowlisted skill code-review/);
  await fs.symlink(path.join(source, 'saved-skill'), skillRoot, 'junction');
  await fails(/Links cannot be published/);
  await fs.unlink(skillRoot);
  await fs.rename(path.join(source, 'saved-skill'), skillRoot);
  const mainPath = path.join(source, 'skills/grill-with-docs/SKILL.md');
  const main = await fs.readFile(mainPath, 'utf8');
  await fs.writeFile(mainPath, main + '\n[missing](../not-published/SKILL.md)');
  await fails(/not-published/);
  await fs.writeFile(mainPath, main);
  await fs.writeFile(path.join(source, 'AGENTS.md'), 'unsupported content');
  await fails(/Unsupported global rule layout/);
  await fs.writeFile(path.join(root, '.codex-rules-update.lock'), 'another process');
  await assert.rejects(update(), /Another update holds/);
  assert.equal(await fs.readFile(path.join(root, '.codex-rules-update.lock'), 'utf8'), 'another process');
  assert.equal(await readCatalog(), unchangedCatalog);
  await fs.unlink(path.join(root, '.codex-rules-update.lock'));
  await clean();
  console.log('PASS isolated publisher: no-op, publish, immutable history, daily numbering, unregistered/missing skills, junction rejection, validation failure, lock and cleanup.');
} finally {
  await fs.rm(root, { recursive: true, force: true });
}
