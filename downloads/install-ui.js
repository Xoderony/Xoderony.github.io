(() => {
  'use strict';
  const command = document.getElementById('install-command');
  const button = document.getElementById('copy-install');
  const feedback = document.getElementById('copy-feedback');
  if (!command || !button || !feedback) return;
  button.addEventListener('click', async () => {
    try {
      if (!navigator.clipboard?.writeText) throw new Error('Clipboard unavailable');
      await navigator.clipboard.writeText(command.value);
      feedback.textContent = '已复制。请在 PowerShell 中粘贴，审阅后运行。';
    } catch {
      command.focus();
      command.select();
      feedback.textContent = '命令已选中，请按 Ctrl+C 复制。';
    }
  });
})();
