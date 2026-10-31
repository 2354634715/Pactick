// 页面示意仅切换说明内容，不读取或保存用户数据。
(() => {
  const tablist = document.querySelector('[role="tablist"]');
  if (!tablist) return;
  const tabs = [...tablist.querySelectorAll('[role="tab"]')];
  const activate = (selected, moveFocus = false) => {
    for (const tab of tabs) {
      const active = tab === selected;
      tab.setAttribute('aria-selected', String(active));
      tab.tabIndex = active ? 0 : -1;
      document.getElementById(tab.getAttribute('aria-controls')).hidden = !active;
    }
    if (moveFocus) selected.focus();
  };
  for (const tab of tabs) {
    tab.addEventListener('click', () => activate(tab));
    tab.addEventListener('keydown', (event) => {
      const index = tabs.indexOf(tab);
      let next;
      if (event.key === 'ArrowRight') next = (index + 1) % tabs.length;
      else if (event.key === 'ArrowLeft') next = (index + tabs.length - 1) % tabs.length;
      else if (event.key === 'Home') next = 0;
      else if (event.key === 'End') next = tabs.length - 1;
      else return;
      event.preventDefault();
      activate(tabs[next], true);
    });
  }
  tablist.hidden = false;
})();
