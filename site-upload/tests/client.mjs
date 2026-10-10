import assert from 'node:assert/strict';
import vm from 'node:vm';
import fs from 'node:fs/promises';
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
class Control extends EventTarget {
  constructor(key, type) { super(); this.dataset = { sync: key }; this.type = type; this.tagName = 'INPUT'; this.value = ''; this.checked = false; this.disabled = false; }
}
const text = new Control('lobby', 'text'), check = new Control('step-01', 'checkbox');
const status = { textContent: '' }, controls = [text, check], sent = [];
let source, revision = 0, values = { lobby: '', 'step-01': false };
class Stream {
  constructor() { source = this; }
  close() {}
  push(snapshot) { this.onmessage({ data: JSON.stringify(snapshot) }); }
}
const context = { console, Event, EventSource: Stream, AbortSignal, setTimeout, clearTimeout,
  document: { documentElement: { dataset: { syncPage: 'test' } }, querySelectorAll: () => controls, querySelector: () => status },
  window: new EventTarget(), location: { protocol: 'http:' },
  fetch: async (_, request) => { const patch = JSON.parse(request.body); sent.push(patch); values[patch.key] = patch.value; return { ok: true, json: async () => ({ revision: ++revision, values: { ...values } }) }; }
};
vm.runInNewContext(await fs.readFile(new URL('../site/shared/sync.js', import.meta.url), 'utf8'), context);
assert.equal(text.disabled, true);
source.push({ revision, values }); assert.equal(text.disabled, false);
text.value = '18446744073709551615'; text.dispatchEvent(new Event('input'));
source.push({ revision: ++revision, values: { ...values, 'step-01': true } });
assert.equal(text.value, '18446744073709551615'); assert.equal(check.checked, true);
await delay(450);
assert.equal(sent[0].value, '18446744073709551615');
check.checked = true; check.dispatchEvent(new Event('change')); await delay(30);
assert.equal(sent[1].value, true);
source.onerror(); assert.equal(text.disabled, true); assert.equal(check.disabled, true);
source.push({ revision: 0, values: { lobby: 'restored', 'step-01': false } });
assert.equal(text.value, 'restored'); assert.equal(check.checked, false); assert.equal(text.disabled, false);
console.log('PASS: initial edit lock, incoming state, pending text preservation, outgoing text/checkbox, disconnect lock, reconnect reconciliation.');
