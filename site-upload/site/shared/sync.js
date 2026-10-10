(() => {
  'use strict';
  const page = document.documentElement.dataset.syncPage;
  const controls = [...document.querySelectorAll('[data-sync]')];
  const status = document.querySelector('[data-sync-status]');
  const pending = new Map();
  let connected = false, sending = false, applying = false, timer, source, reconnectTimer;
  let current = null, generation = 0, inFlight = null;
  const label = text => { if (status) status.textContent = text; };
  const lock = locked => controls.forEach(control => { control.disabled = locked; });
  const render = () => {
    if (!current) return;
    applying = true;
    try {
      for (const control of controls) {
        const key = control.dataset.sync;
        if (pending.has(key) || inFlight === key) continue;
        const value = current.values[key];
        if (value === undefined) throw new Error('Missing field: ' + key);
        if (control.type === 'checkbox') control.checked = value;
        else control.value = value;
        control.dispatchEvent(new Event('input', { bubbles: true }));
        control.dispatchEvent(new Event('change', { bubbles: true }));
      }
    } finally { applying = false; }
  };
  const accept = snapshot => {
    if (!current || snapshot.revision >= current.revision) { current = snapshot; render(); }
  };
  const disconnected = text => {
    connected = false;
    lock(true);
    label(text);
  };
  async function flush() {
    if (sending || !connected) return;
    sending = true;
    const session = generation;
    try {
      while (pending.size && connected && session === generation) {
        const [key, value] = pending.entries().next().value;
        pending.delete(key);
        inFlight = key;
        label('正在同步…');
        const response = await fetch('/api/state/' + encodeURIComponent(page), {
          method: 'PATCH', headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ key, value }), signal: AbortSignal.timeout(10000)
        });
        if (!response.ok) throw new Error('Save failed: ' + response.status);
        const snapshot = await response.json();
        if (session !== generation) return;
        inFlight = null;
        accept(snapshot);
      }
      if (connected && session === generation) label('已连接 · 修改已保存，所有访客共享');
    } catch (error) {
      if (session !== generation) return;
      console.error('Shared state update failed.', error);
      generation++;
      pending.clear();
      source.close();
      disconnected('保存未确认 · 暂停编辑，正在重新连接；请核对最近修改');
      reconnectTimer = setTimeout(connect, 2000);
    } finally {
      sending = false;
      inFlight = null;
      if (connected && pending.size) void flush();
    }
  }
  function connect() {
    clearTimeout(reconnectTimer);
    current = null;
    source = new EventSource('/api/events/' + encodeURIComponent(page));
    source.onmessage = event => {
      try {
        const first = !connected;
        accept(JSON.parse(event.data));
        connected = true;
        lock(false);
        if (first) label('已连接 · 已读取保存状态，请核对最近修改');
        else if (!pending.size && !sending) label('已连接 · 修改已保存，所有访客共享');
      } catch (error) {
        console.error('Shared state snapshot failed.', error);
        source.close();
        disconnected('同步配置不匹配 · 请联系网页维护者');
      }
    };
    source.onerror = () => {
      generation++;
      pending.clear();
      inFlight = null;
      current = null;
      disconnected('连接已断开 · 暂停编辑，正在重连；请核对最近修改');
    };
  }
  for (const control of controls) {
    control.addEventListener(control.type === 'checkbox' || control.tagName === 'SELECT' ? 'change' : 'input', () => {
      if (applying || !connected) return;
      pending.set(control.dataset.sync, control.type === 'checkbox' ? control.checked : control.value);
      label('修改待同步…');
      clearTimeout(timer);
      timer = setTimeout(flush, control.type === 'checkbox' || control.tagName === 'SELECT' ? 0 : 350);
    });
  }
  window.addEventListener('beforeunload', event => {
    if (pending.size || sending) { event.preventDefault(); event.returnValue = ''; }
  });
  lock(true);
  label('正在连接共享状态…');
  if (location.protocol === 'file:') label('请从本地网站入口打开此页，直接打开文件无法同步');
  else connect();
})();
