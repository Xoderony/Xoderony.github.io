import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';

// 只发布经过人工检查的个人技能；不遍历插件、系统技能或其他 Codex 配置。
export const skills = {
  'code-review': ['代码审查', '检查缺陷、项目约定与预期行为。'],
  'codebase-design': ['代码结构设计', '梳理模块接口与依赖边界。'],
  'csharp-concurrency-patterns': ['C# 并发模式', '明确同步、排队、调度与生命周期。'],
  'delegated-work': ['委派工作', '按明确边界委派探索、修改与验证，保留主 Agent 的决策和核验责任。'],
  'diagnosing-bugs': ['故障诊断', '从证据出发定位问题与回归原因。'],
  'domain-modeling': ['领域建模', '整理领域术语、上下文和架构决策。'],
  'failure-lessons': ['故障经验', '记录可复现、可复用的已验证经验。'],
  'grill-me': ['设计访谈', '通过追问澄清方案，依赖 grilling。'],
  'grill-with-docs': ['访谈与文档', '访谈时整理领域文档，带关联技能。'],
  'grilling': ['访谈方法', '围绕关键取舍逐步推进设计讨论。'],
  'interactive-discussion': ['交互式讨论', '通过内嵌页面展示讨论选项并收集反馈。'],
  'modern-csharp-coding-standards': ['C# 编码约定', '编写、修改和审查 C# 时的个人偏好、API、异步及失败处理。'],
  'stride-development': ['Stride 开发', 'Stride 游戏脚本、资产、物理与渲染。']
};
export const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
export const defaultSource = () => path.resolve(process.env.CODEX_HOME || path.join(os.homedir(), '.codex'));

// Check every ancestor so junctions cannot bypass traversal checks.
export async function rejectLinks(location) {
  const absolute = path.resolve(location);
  let current = path.parse(absolute).root;
  for (const part of absolute.slice(current.length).split(path.sep).filter(Boolean)) {
    current = path.join(current, part);
    const info = await fs.lstat(current);
    if (info.isSymbolicLink()) throw new Error(`Links cannot be published: ${current}`);
  }
}

export async function buildSnapshot(version, source = defaultSource()) {
if (!/^[a-z0-9][a-z0-9-]{0,63}$/.test(version)) throw new Error('Invalid snapshot version.');
source = path.resolve(source);
await rejectLinks(path.join(source, 'AGENTS.md'));
await rejectLinks(path.join(source, 'skills'));
const unregistered = [];
for (const item of await fs.readdir(path.join(source, 'skills'), { withFileTypes: true })) {
  if (item.name === '.system') continue;
  if ((item.isDirectory() || item.isSymbolicLink()) && !Object.hasOwn(skills, item.name)) unregistered.push(item.name);
}
if (unregistered.length) throw new Error(`Unregistered personal skills; review and register in scripts/publish-codex-rules.mjs first: ${unregistered.sort().join(', ')}`);
const globalText = (await fs.readFile(path.join(source, 'AGENTS.md'), 'utf8')).replace(/\r\n/g, '\n');
const groups = [];
let group;
for (const line of globalText.split('\n')) {
  if (line.startsWith('## ')) { group = { id: `group-${groups.length + 1}`, title: line.slice(3), rules: [] }; groups.push(group); }
  else if (line.startsWith('- ') && group) {
    const text = line.slice(2);
    group.rules.push({ id: createHash('sha256').update(text).digest('hex').slice(0, 16), text });
  } else if (line.trim() && !line.startsWith('# ')) throw new Error('Unsupported global rule layout; review the parser before publishing.');
}
const exported = [];
for (const [id, [title, description]] of Object.entries(skills)) {
  const files = [];
  async function visit(directory, relative = '') {
    for (const item of await fs.readdir(directory, { withFileTypes: true })) {
      if (item.isSymbolicLink()) throw new Error(`Links cannot be published: ${id}/${relative}/${item.name}`);
      if (item.isDirectory() && item.name === '__pycache__') continue;
      const name = path.posix.join(relative, item.name);
      if (item.isDirectory()) await visit(path.join(directory, item.name), name);
      else {
        if (!item.isFile()) throw new Error(`Not a regular file: ${id}/${name}`);
        if (!/\.(md|yaml|yml|sh|ps1|json|txt|py|html)$/.test(name)) throw new Error(`Review unsupported attachment: ${id}/${name}`);
        const content = await fs.readFile(path.join(directory, item.name), 'utf8');
        if (content.includes('\uFFFD') || content.includes('\0')) throw new Error(`Not UTF-8 text: ${id}/${name}`);
        files.push({ path: name, content });
      }
    }
  }
  const skillRoot = path.join(source, 'skills', id);
  try { await rejectLinks(skillRoot); } catch (error) { throw new Error(`Cannot read allowlisted skill ${id}: ${error.message}`); }
  await visit(skillRoot);
  files.sort((a, b) => a.path.localeCompare(b.path));
  const main = files.find(file => file.path === 'SKILL.md');
  const match = main?.content.match(/^(---\r?\n[\s\S]*?\r?\n---\r?\n)([\s\S]*)$/);
  if (!match) throw new Error(`Missing front matter: ${id}`);
  exported.push({ id, title, description, frontmatter: match[1], body: match[2], files: files.filter(file => file !== main) });
}
return { schemaVersion: 1, version, groups, skills: exported };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const snapshot = await buildSnapshot(process.argv[2] || '', process.argv[3] || defaultSource());
  const target = path.join(projectRoot, 'site', 'codex-rules', 'releases');
  await rejectLinks(target);
  await fs.writeFile(path.join(target, `${snapshot.version}.json`), JSON.stringify(snapshot, null, 2) + '\n', { flag: 'wx' });
  console.log(`Created ${snapshot.version}: ${snapshot.groups.reduce((n, item) => n + item.rules.length, 0)} rules, ${snapshot.skills.length} skills. Review before adding to catalog.json.`);
}
