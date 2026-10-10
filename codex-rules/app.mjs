import { newDraft, restoreDraft, ruleText, skillText, buildExport, installationPrompt } from './core.mjs';

const $ = id => document.getElementById(id);
let snapshot, draft, storageKey, result, activeTab = 'rules';
const cards = new Map();
const notify = text => { $('notice').textContent = text; };
// Restore the displayed snapshot when Back/Forward brings this document back from BFCache.
window.addEventListener('pageshow', () => {
  if (snapshot) $('version').value = snapshot.version;
});
function confirmChange(message) {
  const dialog = $('confirm-dialog');
  $('confirm-message').textContent = message;
  dialog.returnValue = 'cancel';
  return new Promise(resolve => {
    dialog.addEventListener('close', () => resolve(dialog.returnValue === 'accept'), { once: true });
    dialog.showModal();
  });
}
function element(tag, text, className) {
  const node = document.createElement(tag);
  if (text !== undefined) node.textContent = text;
  if (className) node.className = className;
  return node;
}
function save() {
  try { localStorage.setItem(storageKey, JSON.stringify(draft)); $('save-state').textContent = '草稿已保存在此浏览器'; }
  catch { $('save-state').textContent = '无法保存草稿；关闭前请导出'; }
}
function refresh() {
  result = buildExport(snapshot, draft);
  for (const [key, card] of cards) {
    const [kind, id] = key.split(':');
    const chosen = kind === 'rules' ? !!draft.rules[id]?.selected : result.resolved.selected.has(id);
    card.check.checked = chosen;
    card.root.classList.toggle('selected', chosen);
    card.check.disabled = kind === 'skills' && chosen && !draft.skills[id]?.selected;
    const modified = kind === 'rules' ? ruleText(draft, card.item) !== card.item.text : skillText(draft, card.item) !== card.item.body;
    card.badge.textContent = (modified ? '已修改' : '') + (card.check.disabled ? ' · 关联技能，自动包含' : '');
    if (kind === 'rules') card.label.textContent = ruleText(draft, card.item);
  }
  $('rule-count').textContent = result.count;
  $('skill-count').textContent = result.skills.length;
  const automatic = snapshot.skills.filter(skill => result.resolved.selected.has(skill.id) && !draft.skills[skill.id]?.selected);
  $('dependency-status').textContent = automatic.length ? '自动包含依赖：' + automatic.map(skill => skill.title).join('、') + '。可在 Skills 中查看并编辑。' : '';
  $('export-errors').textContent = result.errors.join('\n');
  const disabled = (!result.count && !result.skills.length) || result.errors.length > 0;
  $('copy').disabled = $('download').disabled = disabled;
  const prompt = installationPrompt(result.bundle);
  const bytes = new TextEncoder().encode(prompt).length;
  $('export-size').textContent = `完整安装材料约 ${(bytes / 1024).toFixed(1)} KiB` + (bytes > 25000 ? ' · 建议下载文件交给 Codex' : '');
  const mode = $('preview-mode').value;
  $('preview').textContent = mode === 'agents' ? result.agents || '选中规则后，在这里查看生成的 AGENTS.md。' : mode === 'files' ? result.skills.map(skill => skill.files.map(file => `${skill.id}/${file.path}`).join('\n')).join('\n\n') || '尚未选择 Skills。' : prompt;
}
function makeCard(kind, item) {
  const isRule = kind === 'rules';
  const getText = () => isRule ? ruleText(draft, item) : skillText(draft, item);
  const original = isRule ? item.text : item.body;
  const root = element('article', undefined, isRule ? 'rule' : 'skill');
  const top = element('div', undefined, isRule ? 'rule-top' : 'skill-top');
  const check = element('input'); check.type = 'checkbox'; check.id = `${kind}-${item.id}`;
  const label = element('label'); label.htmlFor = check.id;
  if (isRule) label.textContent = getText();
  else { label.append(element('strong', item.title), element('span', item.id, 'skill-id')); }
  top.append(check, label); root.append(top);
  if (!isRule) root.append(element('p', item.description));
  const actions = element('div', undefined, 'actions');
  const badge = element('span', '', 'badge');
  const edit = element('button', isRule ? '编辑规则' : '编辑正文'); edit.type = 'button'; edit.setAttribute('aria-expanded', 'false');
  const reset = element('button', '恢复原文'); reset.type = 'button';
  actions.append(badge, edit, reset); root.append(actions);
  const editor = element('div', undefined, 'editor'); editor.hidden = true; editor.id = `${check.id}-editor`; edit.setAttribute('aria-controls', editor.id);
  const editorLabel = element('label', isRule ? '规则内容' : 'SKILL.md 正文 · 元数据与附带文件保持原样');
  const textarea = element('textarea'); textarea.value = getText(); textarea.id = `${check.id}-text`; editorLabel.htmlFor = textarea.id;
  editor.append(editorLabel, textarea); root.append(editor);
  function update(selected, text) { draft[kind][item.id] = { selected, text }; save(); refresh(); }
  check.addEventListener('change', () => update(check.checked, getText()));
  textarea.addEventListener('input', () => update(!!draft[kind][item.id]?.selected, textarea.value));
  edit.addEventListener('click', () => { editor.hidden = !editor.hidden; edit.setAttribute('aria-expanded', String(!editor.hidden)); if (!editor.hidden) textarea.focus(); });
  reset.addEventListener('click', async () => {
    if (getText() !== original && !await confirmChange('恢复这项内容的发布原文？你的编辑将被清除。')) return;
    textarea.value = original; update(!!draft[kind][item.id]?.selected, original);
  });
  if (!isRule) {
    const details = element('details', undefined, 'attachments');
    details.append(element('summary', `元数据与附带文件（${item.files.length}）`));
    details.append(element('pre', item.frontmatter));
    for (const file of item.files) {
      const attachment = element('details'); attachment.append(element('summary', file.path), element('pre', file.content)); details.append(attachment);
    }
    root.append(details);
  }
  cards.set(`${kind}:${item.id}`, { root, item, check, label, badge, textarea });
  return root;
}
function render() {
  cards.clear(); $('rules-panel').replaceChildren(); $('skills-panel').replaceChildren();
  for (const group of snapshot.groups) {
    const section = element('section', undefined, 'group');
    const heading = element('div', undefined, 'group-heading'); heading.append(element('h2', group.title));
    for (const [text, selected] of [['整组全选', true], ['整组取消', false]]) {
      const button = element('button', text); button.type = 'button'; button.setAttribute('aria-label', `${group.title}：${text}`);
      button.addEventListener('click', () => { for (const rule of group.rules) draft.rules[rule.id] = { selected, text: ruleText(draft, rule) }; save(); refresh(); }); heading.append(button);
    }
    section.append(heading, ...group.rules.map(rule => makeCard('rules', rule))); $('rules-panel').append(section);
  }
  $('skills-panel').append(...snapshot.skills.map(skill => makeCard('skills', skill)));
  refresh(); filter();
}
function filter() {
  const query = $('search').value.trim().toLowerCase(); let visible = 0;
  for (const [key, card] of cards) {
    const kind = key.split(':')[0];
    const text = kind === 'rules' ? ruleText(draft, card.item) : `${card.item.id} ${card.item.title} ${card.item.description} ${skillText(draft, card.item)}`;
    card.root.hidden = !text.toLowerCase().includes(query);
    if (kind === activeTab && !card.root.hidden) visible++;
  }
  for (const group of $('rules-panel').children) group.hidden = ![...group.querySelectorAll('article')].some(card => !card.hidden);
  $('empty-search').hidden = visible > 0;
}
function tab(kind) {
  activeTab = kind;
  for (const name of ['rules', 'skills']) { $(name + '-panel').hidden = kind !== name; $(name + '-tab').setAttribute('aria-selected', String(name === kind)); $(name + '-tab').tabIndex = kind === name ? 0 : -1; }
  filter();
}
for (const kind of ['rules', 'skills']) {
  $(kind + '-tab').addEventListener('click', () => tab(kind));
  $(kind + '-tab').addEventListener('keydown', event => { if (['ArrowLeft', 'ArrowRight'].includes(event.key)) { event.preventDefault(); const next = kind === 'rules' ? 'skills' : 'rules'; tab(next); $(next + '-tab').focus(); } });
}
$('search').addEventListener('input', filter);
$('preview-mode').addEventListener('change', refresh);
$('clear').addEventListener('click', async () => {
  if (!await confirmChange('清空这个发布版本的全部选择和编辑？其他版本的草稿不受影响。')) return;
  draft = newDraft(snapshot); save(); render(); notify('当前版本的草稿已清空。');
});
$('copy').addEventListener('click', async () => {
  const text = installationPrompt(result.bundle);
  try {
    if (!navigator.clipboard?.writeText) throw new Error('Clipboard unavailable');
    await navigator.clipboard.writeText(text); notify('安装提示词已复制。粘贴给 Codex，先查看建议和 diff，再确认安装。');
  } catch {
    $('preview-mode').value = 'prompt'; refresh();
    const range = document.createRange(); range.selectNodeContents($('preview')); const selection = window.getSelection(); selection.removeAllRanges(); selection.addRange(range);
    notify('浏览器未允许自动复制。完整提示词已选中，请按 Ctrl+C（Mac 使用 ⌘C），或下载材料。');
  }
});
$('download').addEventListener('click', () => {
  const blob = new Blob([installationPrompt(result.bundle)], { type: 'text/plain;charset=utf-8' });
  const url = URL.createObjectURL(blob); const a = element('a'); a.href = url; a.download = `xoderony-codex-${snapshot.version}.txt`;
  document.body.append(a); a.click(); a.remove(); setTimeout(() => URL.revokeObjectURL(url), 1000);
  notify('安装材料已生成。将文件交给 Codex，并让它按文件中的流程分析，确认 diff 后安装。');
});

try {
  const catalogResponse = await fetch('./catalog.json'); if (!catalogResponse.ok) throw new Error('版本清单加载失败');
  const catalog = await catalogResponse.json();
  const version = new URL(location.href).searchParams.get('v') || catalog.current;
  if (!catalog.versions.includes(version) || !/^[a-z0-9-]+$/.test(version)) throw new Error('找不到指定的发布版本');
  for (const id of catalog.versions) { const option = element('option', id + (id === catalog.current ? ' · 当前' : '')); option.value = id; $('version').append(option); }
  $('version').value = version; $('version').disabled = false;
  $('version').addEventListener('change', () => { const url = new URL(location.href); url.searchParams.set('v', $('version').value); location.href = url.href; });
  const response = await fetch(`./releases/${version}.json`); if (!response.ok) throw new Error('规则快照加载失败');
  snapshot = await response.json(); if (snapshot.version !== version || snapshot.schemaVersion !== 1) throw new Error('规则快照格式不兼容');
  storageKey = `xoderony:codex-rules:${version}`;
  try { draft = restoreDraft(snapshot, localStorage.getItem(storageKey)); $('save-state').textContent = '草稿仅保存在此浏览器'; }
  catch { draft = newDraft(snapshot); $('save-state').textContent = '草稿未能恢复'; notify('无法读取此版本草稿。已显示原始内容；旧草稿暂未覆盖。'); }
  $('rule-total').textContent = snapshot.groups.reduce((n, group) => n + group.rules.length, 0); $('skill-total').textContent = snapshot.skills.length;
  render(); $('workspace').hidden = false; $('clear').disabled = false;
} catch (error) { $('save-state').textContent = '加载失败'; notify(`${error.message}。请刷新重试或联系维护者。`); }
