import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { newDraft, restoreDraft, buildExport, installationPrompt } from '../site/codex-rules/core.mjs';

export function validateSnapshot(snapshot) {
  const version = snapshot.version;
  assert.ok(snapshot.groups.length && snapshot.groups.every(group => group.rules.length));
  assert.equal(new Set(snapshot.groups.flatMap(group => group.rules.map(rule => rule.id))).size, snapshot.groups.flatMap(group => group.rules).length);
  const draft = newDraft(snapshot);
  assert.equal(buildExport(snapshot, draft).bundle.globalRules, null);
  assert.equal(buildExport(snapshot, draft).skills.length, 0);
  const first = snapshot.groups[0].rules[0];
  const edited = 'Use English by default.\n保留用户提供的专有名词。';
  draft.rules[first.id] = { selected: true, text: edited };
  draft.skills['grill-with-docs'] = { selected: true, text: snapshot.skills.find(skill => skill.id === 'grill-with-docs').body + '\n请额外检查设计目标。\n' };
  const output = buildExport(snapshot, draft);
  assert.deepEqual(output.errors, []);
  assert.equal(output.count, 1);
  assert.deepEqual(output.skills.map(skill => skill.id).sort(), ['domain-modeling', 'grill-with-docs', 'grilling']);
  assert.match(output.agents, /Use English by default\.\n  保留/);
  assert.ok(!output.agents.includes(first.text));
  const prompt = installationPrompt(output.bundle);
  const exported = JSON.parse(prompt.slice(prompt.indexOf('\n{') + 1, prompt.lastIndexOf('\nXODERONY_EXPORT_END')).trim());
  assert.deepEqual(exported, output.bundle);
  assert.match(prompt, /展示每个受影响文件的完整 unified diff/);
  assert.match(prompt, /所有实际写入必须限定在我明确确认的最终 diff 内/);
  const main = exported.skills.find(skill => skill.id === 'grill-with-docs').files[0];
  assert.ok(main.content.includes('请额外检查设计目标'));
  const modeling = snapshot.skills.find(skill => skill.id === 'domain-modeling');
  assert.deepEqual(exported.skills.find(skill => skill.id === 'domain-modeling').files.slice(1), modeling.files);
  assert.deepEqual(restoreDraft(snapshot, JSON.stringify(draft)), draft);
  assert.throws(() => restoreDraft({ ...snapshot, version: 'next' }, JSON.stringify(draft)), /版本/);
  assert.throws(() => restoreDraft(snapshot, '{bad'), SyntaxError);
  const restored = restoreDraft(snapshot, JSON.stringify(draft));
  restored.rules[first.id].selected = false;
  assert.equal(buildExport(snapshot, restored).bundle.globalRules, null);
  restored.rules[first.id] = { selected: true, text: '' };
  assert.ok(buildExport(snapshot, restored).errors.some(message => message.includes('为空')));
  restored.skills['grill-with-docs'].text += '\n[missing](../not-published/SKILL.md)';
  assert.ok(buildExport(snapshot, restored).errors.some(message => message.includes('not-published')));
  restored.skills['grill-with-docs'].text = '[bad](../grilling/missing.md)';
  assert.ok(buildExport(snapshot, restored).errors.some(message => message.includes('grilling/missing.md')));
  restored.skills['grill-with-docs'].text = '[self](../grill-with-docs/SKILL.md)';
  assert.deepEqual(buildExport(snapshot, restored).skills.map(skill => skill.id), ['grill-with-docs']);
  const all = newDraft(snapshot);
  for (const group of snapshot.groups) for (const rule of group.rules) all.rules[rule.id] = { selected: true, text: rule.text };
  for (const skill of snapshot.skills) all.skills[skill.id] = { selected: true, text: skill.body };
  const complete = buildExport(snapshot, all);
  assert.deepEqual(complete.errors, []);
  assert.equal(complete.skills.length, snapshot.skills.length);
  for (const skill of complete.skills) {
    const source = snapshot.skills.find(item => item.id === skill.id);
    assert.equal(skill.files[0].content, source.frontmatter + source.body);
    assert.deepEqual(skill.files.slice(1), source.files);
  }
  console.log(`PASS ${version}: edited export, automatic dependencies, missing references, file preservation, empty input, version-isolated drafts and confirmation instructions.`);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const base = new URL('../site/codex-rules/', import.meta.url);
  const catalog = JSON.parse(await fs.readFile(new URL('catalog.json', base), 'utf8'));
  for (const version of catalog.versions) {
    validateSnapshot(JSON.parse(await fs.readFile(new URL(`releases/${version}.json`, base), 'utf8')));
  }
}
