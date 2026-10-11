'use strict';
const token = location.hash.slice(1) || sessionStorage.getItem('pactick-manager-token') || '';
if (token) sessionStorage.setItem('pactick-manager-token', token);
history.replaceState(null, '', location.pathname);
const $ = s => document.querySelector(s);
let busy = false;
let status;
function feedback(message, error = false) {
  $('#feedback').hidden = false;
  $('#feedback').classList.toggle('error', error);
  $('#feedback-title').textContent = error ? '操作失败' : '操作结果';
  $('#feedback-body').textContent = message;
}
async function api(path, body) {
  const response = await fetch(path, {method: body ? 'POST' : 'GET', headers: {'X-Pactick-Manager-Token': token, ...(body ? {'Content-Type': 'application/json'} : {})}, ...(body ? {body: JSON.stringify(body)} : {})});
  const result = await response.json();
  if (!response.ok || !result.ok) throw Error(result.message || '操作失败');
  return result;
}
async function refresh() {
  try {
    const reply = await api('/api/status');
    if (reply.data.busy) { $('#status').textContent = '正在执行操作'; return; }
    status = reply.data;
    $('#status').textContent = status.ready ? '服务已就绪' : '服务未就绪';
    $('#status').classList.toggle('ready', status.ready);
    $('#mode-label').textContent = status.mode === 'docker' ? 'Docker' : '本机程序';
    $('#address-label').textContent = status.http_address;
    $('#database-label').textContent = status.initialized ? '已初始化' : '待初始化';
    $('#data-label').textContent = '配置与备份目录：' + status.data_directory;
    const form = $('#settings-form');
    if (!form.contains(document.activeElement)) {
      form.elements.mode.value = status.mode;
      const [host, port] = status.http_address.split(':');
      form.elements.bind.value = host;
      form.elements.port.value = port;
      form.elements.database_url.placeholder = status.database_configured ? '已保存；留空保留现有连接地址' : 'postgres://user:password@127.0.0.1:5432/pactick';
      settingsVisibility();
    }
  } catch (e) { $('#status').textContent = '管理连接失效'; feedback(e.message, true); }
}
async function operate(fn) {
  if (busy) return;
  busy = true;
  document.querySelectorAll('button').forEach(b => b.disabled = true);
  feedback('正在执行，请等待操作完成…');
  try { await fn(); } catch (e) { feedback(e.message, true); }
  finally { busy = false; document.querySelectorAll('button').forEach(b => b.disabled = false); await refresh(); }
}
document.querySelectorAll('nav button').forEach(button => button.addEventListener('click', () => {
  document.querySelectorAll('.page').forEach(p => p.hidden = p.id !== button.dataset.page);
  document.querySelectorAll('nav button').forEach(b => b.classList.toggle('selected', b === button));
  $('#page-title').textContent = button.textContent;
  $('#feedback').hidden = true;
}));
$('.brand').addEventListener('click', e => { e.preventDefault(); $('nav button[data-page="overview"]').click(); });
document.querySelectorAll('[data-action]').forEach(button => button.addEventListener('click', () => {
  if (button.dataset.action === 'migrate' && !confirm('已保存可恢复的数据库备份？迁移会停止 API 并修改数据库结构，程序不会自动回滚。')) return;
  operate(async () => { const result = await api('/api/action', {action: button.dataset.action}); feedback(result.message); });
}));
$('#refresh').addEventListener('click', refresh);
$('#dismiss-feedback').addEventListener('click', () => $('#feedback').hidden = true);
function settingsVisibility() {
  const form = $('#settings-form');
  const native = form.elements.mode.value === 'native';
  $('#native-settings').hidden = !native;
  $('#network-note').hidden = form.elements.bind.value !== '0.0.0.0';
  $('#dependency-note').textContent = native ? '需要已运行的 PostgreSQL。服务端程序随发行包提供；关闭管理程序会停止由它启动的本机 API。' : 'Docker 模式需要 Docker Engine/Desktop 与 Compose v2，首次部署需联网下载容器镜像。';
}
$('#settings-form').addEventListener('change', settingsVisibility);
$('#settings-form').addEventListener('submit', e => {e.preventDefault(); operate(async () => {
  const form = e.target;
  const result = await api('/api/settings', {mode: form.elements.mode.value, http_address: form.elements.bind.value + ':' + form.elements.port.value, database_url: form.elements.database_url.value});
  form.elements.database_url.value = '';
  feedback(result.message);
});});
$('#account-form').addEventListener('submit', e => {e.preventDefault(); operate(async () => {
  $('#created-account').hidden = true;
  const form = e.target;
  const result = await api('/api/accounts', {email: form.elements.email.value, display_name: form.elements.display_name.value, time_zone: form.elements.time_zone.value, password: form.elements.password.value, locale: 'zh-CN'});
  form.elements.password.value = '';
  $('#created-email').textContent = result.data.user.email;
  $('#generated-password').value = result.data.generated_password || '';
  $('#password-label').hidden = !result.data.generated_password;
  $('#created-account').hidden = false;
  feedback('账户创建成功，可以在安卓客户端登录。');
});});
$('#clear-credential').addEventListener('click', () => {$('#generated-password').value = ''; $('#created-email').textContent = ''; $('#created-account').hidden = true;});
refresh();
setInterval(() => {if (!busy) refresh();}, 15000);
