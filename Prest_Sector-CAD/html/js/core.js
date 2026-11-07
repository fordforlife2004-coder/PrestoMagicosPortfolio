'use strict';
// The tablet's core: talking to the game, the page list, the top bar (your unit and its status),
// pop-ups, messages and small helpers every page uses. Pages register themselves with CAD.page().
// Text from players is only ever put on screen as text (never as HTML).

(() => {
  const inGame = typeof window.GetParentResourceName === 'function';
  const resource = inGame ? window.GetParentResourceName() : 'Prest_Sector-CAD';

  const CAD = window.CAD = {
    inGame,
    // me: who you are (roles, abilities, your unit). config: the lists from config.lua.
    // units and calls: the live dispatch board, kept up to date by pushes from the server.
    state: { me: null, config: null, units: [], calls: [], page: null, params: null, open: false },
    pages: {},
    mock: { handlers: {}, state: {}, on(action, fn) { this.handlers[action] = fn; } },
  };

  // ------------------------------------------------------------------ building the screen

  const SVG = 'http://www.w3.org/2000/svg';

  // h('div', { class: 'card', onClick: fn, style: { color: 'red' }, 'data-id': 3 }, 'text', child, [more])
  CAD.h = (tag, attrs, ...children) => {
    const node = document.createElement(tag);
    for (const [key, value] of Object.entries(attrs || {})) {
      if (value === null || value === undefined || value === false) continue;
      if (key === 'class') node.className = value;
      else if (key === 'style' && typeof value === 'object') {
        // Custom properties (--c) need setProperty; the rest can be set directly.
        for (const [prop, v] of Object.entries(value)) {
          if (prop.startsWith('--')) node.style.setProperty(prop, v); else node.style[prop] = v;
        }
      }
      else if (key.startsWith('on') && typeof value === 'function') node.addEventListener(key.slice(2).toLowerCase(), value);
      else if (key === 'value') node.value = value;
      else if (key === 'checked' || key === 'disabled' || key === 'hidden' || key === 'selected') node[key] = Boolean(value);
      else node.setAttribute(key, value === true ? '' : String(value));
    }
    const add = (child) => {
      if (child === null || child === undefined || child === false) return;
      if (Array.isArray(child)) child.forEach(add);
      else node.append(child instanceof Node ? child : document.createTextNode(String(child)));
    };
    children.forEach(add);
    return node;
  };
  const { h } = CAD;

  CAD.$ = (selector, root = document) => root.querySelector(selector);
  CAD.$$ = (selector, root = document) => [...root.querySelectorAll(selector)];

  // A few line icons, drawn from fixed paths (24 x 24).
  const ICONS = {
    dispatch: 'M3 12h4l3-8 4 16 3-8h4',
    people: 'M16 11a4 4 0 1 0-8 0 4 4 0 0 0 8 0zM4 21c1-4 4.5-6 8-6s7 2 8 6',
    car: 'M5 16l1.5-5.5A2 2 0 0 1 8.4 9h7.2a2 2 0 0 1 1.9 1.5L19 16M4 16h16v3H4zM7 19v1M17 19v1',
    gun: 'M3 9h15l2 2-2 1H11l-1 3H7l1-3H3z',
    report: 'M7 3h7l5 5v13H7zM14 3v5h5M10 13h6M10 17h6',
    warrant: 'M12 3l8 4v5c0 5-3.5 8-8 9-4.5-1-8-4-8-9V7z',
    bolo: 'M12 4a8 8 0 1 0 0 16 8 8 0 0 0 0-16zM12 9v4M12 16h.01',
    book: 'M5 4h11a3 3 0 0 1 3 3v13H8a3 3 0 0 1-3-3zM5 17a3 3 0 0 1 3-3h11',
    civilian: 'M12 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8zM6 21v-2a6 6 0 0 1 12 0v2',
    close: 'M6 6l12 12M18 6L6 18',
    plus: 'M12 5v14M5 12h14',
    search: 'M11 4a7 7 0 1 0 0 14 7 7 0 0 0 0-14zM20 20l-4-4',
    map: 'M12 21s-7-6.2-7-11a7 7 0 0 1 14 0c0 4.8-7 11-7 11zM12 8a2 2 0 1 0 0 4 2 2 0 0 0 0-4z',
    note: 'M5 4h14v12l-4 4H5zM15 20v-4h4',
    panic: 'M12 3l9 16H3zM12 10v4M12 17h.01',
    power: 'M12 3v8M7 6a7 7 0 1 0 10 0',
    edit: 'M4 20h4L19 9l-4-4L4 16zM14 6l4 4',
    trash: 'M5 7h14M10 11v6M14 11v6M7 7l1 13h8l1-13M9 7V4h6v3',
    check: 'M5 13l4 4L19 7',
    back: 'M15 6l-6 6 6 6',
    link: 'M10 14a4 4 0 0 0 6 0l3-3a4 4 0 0 0-6-6l-1 1M14 10a4 4 0 0 0-6 0l-3 3a4 4 0 0 0 6 6l1-1',
  };
  CAD.icon = (name, size = 18) => {
    const svg = document.createElementNS(SVG, 'svg');
    svg.setAttribute('viewBox', '0 0 24 24');
    svg.setAttribute('width', size);
    svg.setAttribute('height', size);
    svg.setAttribute('class', 'icon');
    svg.setAttribute('aria-hidden', 'true');
    const path = document.createElementNS(SVG, 'path');
    path.setAttribute('d', ICONS[name] || ICONS.note);
    svg.append(path);
    return svg;
  };

  // ------------------------------------------------------------------ talking to the game

  // Posts to the game's client script (NUI callback). Outside the game it does nothing.
  CAD.post = async (name, data) => {
    if (!inGame) return null;
    try {
      const res = await fetch(`https://${resource}/${name}`, {
        method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' }, body: JSON.stringify(data || {}),
      });
      return await res.json();
    } catch {
      return null;
    }
  };

  const clone = (value) => (value === undefined ? undefined : JSON.parse(JSON.stringify(value)));

  // A list from the server. Lua sends an empty list as {} sometimes, so anything that isn't an array
  // is treated as one (or as empty).
  CAD.list = (value) => {
    if (Array.isArray(value)) return value;
    if (value && typeof value === 'object') return Object.values(value);
    return [];
  };
  const sleep = (ms) => new Promise((resolve) => { setTimeout(resolve, ms); });

  // Asks the server for something. Resolves with the result, or rejects with a message for the user.
  CAD.rpc = async (action, payload) => {
    if (!inGame) {
      const fn = CAD.mock.handlers[action];
      if (!fn) throw new Error(`The preview can't do "${action}" yet.`);
      await sleep(80);
      return clone(fn(clone(payload || {}), CAD.mock.state));
    }
    const res = await CAD.post('rpc', { action, payload: payload || {} });
    if (!res) throw new Error("The CAD didn't answer. Try again.");
    if (!res.ok) throw new Error(res.error || 'Something went wrong.');
    return res.result;
  };

  // Wraps an action so a failure shows as a message instead of being lost.
  CAD.run = (fn) => async (...args) => {
    try {
      return await fn(...args);
    } catch (e) {
      CAD.toast(e.message || String(e), 'error');
      return undefined;
    }
  };

  // ------------------------------------------------------------------ live updates

  const listeners = {};
  CAD.on = (kind, fn) => { (listeners[kind] = listeners[kind] || []).push(fn); };

  // Applies a push from the server, then tells the open page and anyone listening.
  CAD.push = (kind, data) => {
    const s = CAD.state;
    if (kind === 'units') s.units = CAD.list(data);
    else if (kind === 'call' && data) {
      s.calls = s.calls.filter((c) => c.id !== data.id);
      if (data.status !== 'closed') s.calls.push(data);
      sortCalls();
    } else if (kind === 'me' && data) {
      // Keep the callsign and department you last signed on with, for next time.
      s.me = { lastCallsign: s.me && s.me.lastCallsign, lastDepartment: s.me && s.me.lastDepartment, ...data };
      renderChrome();
    } else if (kind === 'notify' && data) {
      CAD.toast(data.text, data.tone || 'info');
    } else if (kind === 'plate' && data) {
      // The in-game plate reader: the plate and everything that came back with it.
      const alerts = CAD.list(data.alerts).map((a) => a.text);
      CAD.toast(`Plate ${data.plate}: ${alerts.length ? alerts.join(' ') : 'nothing to report.'}`,
        CAD.list(data.alerts).some((a) => a.tone === 'error') ? 'error' : 'warning', 9000);
    } else if (kind === 'alert' && data && data.call) {
      const c = data.call;
      const what = data.kind === 'panic' ? 'PANIC' : data.kind === 'attached' ? 'You were put on' : 'New call';
      CAD.toast(`${what} ${CAD.fmt.call(c.id)} ${c.code} ${c.title}${c.location && c.location.street ? ` — ${c.location.street}` : ''}`,
        data.kind === 'panic' ? 'error' : 'warning', 8000);
    }
    const page = CAD.pages[s.page];
    if (s.open && page && page.onPush) {
      try { page.onPush(kind, data); } catch (e) { console.error(e); }
    }
    (listeners[kind] || []).forEach((fn) => { try { fn(data); } catch (e) { console.error(e); } });
  };

  const sortCalls = () => {
    CAD.state.calls.sort((a, b) => (a.priority - b.priority) || (a.createdAt - b.createdAt));
  };

  window.addEventListener('message', (event) => {
    const m = event.data || {};
    if (m.type === 'open') CAD.open(m.page);
    else if (m.type === 'close') hide();
    else if (m.type === 'push') CAD.push(m.kind, m.data);
  });

  // ------------------------------------------------------------------ who you are

  CAD.can = (ability) => {
    if (!ability) return true;
    if (typeof ability === 'function') return Boolean(ability(CAD.state.me));
    const me = CAD.state.me;
    return Boolean(me && me.abilities && me.abilities[ability]);
  };
  CAD.onDuty = () => Boolean(CAD.state.me && CAD.state.me.unit);

  // An item from one of config.lua's lists, e.g. CAD.cfg('statuses', 'available').
  CAD.cfg = (list, key, field = 'key') => {
    const items = (CAD.state.config && CAD.state.config[list]) || [];
    return items.find((item) => item[field] === key) || null;
  };

  // ------------------------------------------------------------------ formatting

  const pad = (n) => String(n).padStart(2, '0');
  const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  const PREFIX = { person: 'P', vehicle: 'V', weapon: 'W', report: 'R', warrant: 'WR', bolo: 'B' };
  CAD.fmt = {
    time: (sec) => { if (!sec) return ''; const d = new Date(sec * 1000); return `${pad(d.getHours())}:${pad(d.getMinutes())}`; },
    date: (sec) => { if (!sec) return ''; const d = new Date(sec * 1000); return `${MONTHS[d.getMonth()]} ${d.getDate()}, ${d.getFullYear()}`; },
    dateTime: (sec) => (sec ? `${CAD.fmt.date(sec)} ${CAD.fmt.time(sec)}` : ''),
    // "45s", "12m", "3h", "2d" since a time
    ago: (sec) => {
      if (!sec) return '';
      const s = Math.max(0, Math.floor(Date.now() / 1000 - sec));
      if (s < 60) return `${s}s`;
      if (s < 3600) return `${Math.floor(s / 60)}m`;
      if (s < 86400) return `${Math.floor(s / 3600)}h`;
      return `${Math.floor(s / 86400)}d`;
    },
    money: (n) => `$${Math.round(Number(n) || 0).toLocaleString('en-US')}`,
    months: (n) => `${n} month${n === 1 ? '' : 's'}`,
    call: (id) => `#${id}`,
    id: (kind, id) => `${PREFIX[kind] || '?'}-${id}`,
    name: (p) => (p ? `${p.first || ''} ${p.last || ''}`.trim() : ''),
    // 'YYYY-MM-DD' -> age in years
    age: (dob) => {
      const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(dob || '');
      if (!m) return null;
      const now = new Date();
      let age = now.getFullYear() - Number(m[1]);
      if (now.getMonth() + 1 < Number(m[2]) || (now.getMonth() + 1 === Number(m[2]) && now.getDate() < Number(m[3]))) age -= 1;
      return age;
    },
  };

  // ------------------------------------------------------------------ small building blocks

  // A coloured label. color is a CSS colour from config.lua.
  CAD.badge = (text, color, extra = '') => h('span', { class: `badge ${extra}`.trim(), style: color ? { '--c': color } : null }, text);
  // The badge for an item in a config list, e.g. CAD.stateBadge('licenseStates', 'suspended').
  CAD.stateBadge = (list, key) => {
    const item = CAD.cfg(list, key);
    return CAD.badge(item ? item.label : key || '—', item && item.color);
  };
  CAD.empty = (text) => h('div', { class: 'empty' }, text);
  CAD.loading = () => h('div', { class: 'loading' }, h('span', { class: 'spinner' }), 'Loading…');

  CAD.button = (label, onClick, opts = {}) => h('button', {
    type: 'button', class: `btn ${opts.kind ? `btn-${opts.kind}` : ''} ${opts.small ? 'btn-small' : ''}`.trim(),
    onClick, disabled: opts.disabled, title: opts.title,
  }, opts.icon ? CAD.icon(opts.icon, opts.small ? 14 : 16) : null, label);

  // A labelled form field around any control. hint is a small note under it.
  CAD.field = (label, control, hint) => h('label', { class: 'field' }, h('span', { class: 'field-label' }, label), control,
    hint ? h('span', { class: 'field-hint' }, hint) : null);
  CAD.input = (attrs = {}) => h('input', { class: 'input', type: 'text', autocomplete: 'off', spellcheck: 'false', ...attrs });
  CAD.textarea = (attrs = {}) => h('textarea', { class: 'input textarea', spellcheck: 'true', ...attrs });
  // options: [{ value, label }] or ['a', 'b']
  CAD.select = (options, value, attrs = {}) => h('select', { class: 'input select', ...attrs },
    options.map((o) => {
      const v = typeof o === 'object' ? o.value : o;
      const l = typeof o === 'object' ? o.label : o;
      return h('option', { value: v, selected: String(v) === String(value) }, l);
    }));
  CAD.options = (list, labelField = 'label', valueField = 'key') => ((CAD.state.config && CAD.state.config[list]) || [])
    .map((item) => ({ value: item[valueField], label: item[labelField] }));

  // A table: columns = [{ label, render(row) -> node|string, class }], onClick(row) optional.
  CAD.table = (columns, rows, onClick) => h('table', { class: `table ${onClick ? 'table-click' : ''}` },
    h('thead', null, h('tr', null, columns.map((c) => h('th', { class: c.class }, c.label)))),
    h('tbody', null, rows.map((row) => h('tr', { onClick: onClick ? () => onClick(row) : null },
      columns.map((c) => h('td', { class: c.class }, c.render(row)))))));

  // Tabs: [{ key, label, render() -> node }]. Returns the element.
  CAD.tabs = (tabs, active) => {
    const body = h('div', { class: 'tab-body' });
    const bar = h('div', { class: 'tabs', role: 'tablist' });
    const show = (key) => {
      CAD.$$('.tab', bar).forEach((b) => b.classList.toggle('is-active', b.dataset.key === key));
      const tab = tabs.find((t) => t.key === key) || tabs[0];
      body.replaceChildren(tab.render());
    };
    tabs.forEach((t) => bar.append(h('button', { type: 'button', class: 'tab', 'data-key': t.key, role: 'tab', onClick: () => show(t.key) },
      t.label, t.count !== undefined ? h('span', { class: 'tab-count' }, String(t.count)) : null)));
    const node = h('div', { class: 'tabbed' }, bar, body);
    show(active || (tabs[0] && tabs[0].key));
    return node;
  };

  CAD.debounce = (fn, ms) => {
    let timer = null;
    return (...args) => { clearTimeout(timer); timer = setTimeout(() => fn(...args), ms); };
  };

  // ------------------------------------------------------------------ messages and pop-ups

  CAD.toast = (text, tone = 'info', ms = 4500) => {
    const node = h('div', { class: `toast toast-${tone}`, role: tone === 'error' ? 'alert' : 'status' }, text);
    CAD.$('#toasts').append(node);
    setTimeout(() => node.classList.add('is-leaving'), ms);
    setTimeout(() => node.remove(), ms + 300);
  };

  // modal({ title, body, wide, actions: [{ label, kind: 'primary'|'danger', onClick }] }).
  // onClick may be async; returning false keeps it open. An error shows as a message and keeps it open.
  CAD.modal = ({ title, body, wide = false, actions = [{ label: 'Close' }] }) => {
    const root = CAD.$('#modals');
    let closed = false;
    const close = () => {
      if (closed) return;
      closed = true;
      overlay.remove();
    };
    const buttons = actions.map((a) => {
      const btn = CAD.button(a.label, async () => {
        if (!a.onClick) return close();
        btn.disabled = true;
        try {
          const keep = await a.onClick();
          if (keep !== false) close();
        } catch (e) {
          CAD.toast(e.message || String(e), 'error');
        } finally {
          btn.disabled = false;
        }
        return undefined;
      }, { kind: a.kind });
      return btn;
    });
    const overlay = h('div', { class: 'overlay', onMousedown: (e) => { if (e.target === overlay) close(); } },
      h('div', { class: `modal ${wide ? 'modal-wide' : ''}`, role: 'dialog', 'aria-modal': 'true', 'aria-label': title },
        h('div', { class: 'modal-head' }, h('h2', null, title),
          h('button', { type: 'button', class: 'icon-btn', 'aria-label': 'Close', onClick: close }, CAD.icon('close'))),
        h('div', { class: 'modal-body' }, body),
        h('div', { class: 'modal-foot' }, buttons)));
    root.append(overlay);
    const first = CAD.$('input, select, textarea', overlay);
    if (first) setTimeout(() => first.focus(), 0);
    return { close, root: overlay };
  };

  // A yes/no question. Resolves true when confirmed.
  CAD.confirm = (title, text, label = 'Yes', kind = 'danger') => new Promise((resolve) => {
    let answered = false;
    const m = CAD.modal({
      title, body: h('p', null, text),
      actions: [
        { label: 'Cancel', onClick: () => { answered = true; resolve(false); } },
        { label, kind, onClick: () => { answered = true; resolve(true); } },
      ],
    });
    // Closed with the X or by clicking outside counts as no.
    const watch = setInterval(() => { if (!m.root.isConnected) { clearInterval(watch); if (!answered) resolve(false); } }, 200);
  });

  // ------------------------------------------------------------------ pages

  // CAD.page('people', { title, icon, ability, order, render(root, params), onPush(kind, data) })
  CAD.page = (name, page) => { CAD.pages[name] = { order: 50, ...page, name }; };

  const visiblePages = () => Object.values(CAD.pages).filter((p) => !p.hidden && CAD.can(p.ability)).sort((a, b) => a.order - b.order);

  // Where the tablet opens: the board for units and dispatch, people for judges, your own records
  // for civilians.
  const firstPage = () => {
    const pages = visiblePages();
    const pick = (name) => pages.find((p) => p.name === name);
    return (pick('dispatch') || pick('people') || pick('civilian') || pages[0] || {}).name;
  };

  // Shows a page. params are passed to its render(), e.g. CAD.go('people', { id: 12 }).
  CAD.go = async (name, params = null) => {
    const page = CAD.pages[name] && CAD.can(CAD.pages[name].ability) ? CAD.pages[name] : CAD.pages[firstPage()];
    if (!page) return;
    CAD.state.page = page.name;
    CAD.state.params = params;
    renderNav();
    const content = CAD.$('#content');
    const root = h('div', { class: `page page-${page.name}` });
    content.replaceChildren(root);
    content.scrollTop = 0;
    try {
      await page.render(root, params || {});
    } catch (e) {
      console.error(e);
      root.replaceChildren(CAD.empty(e.message || 'This page could not be shown.'));
    }
  };

  // Draws the current page again (after a change).
  CAD.refresh = () => CAD.go(CAD.state.page, CAD.state.params);

  const renderNav = () => {
    const nav = CAD.$('#nav');
    nav.replaceChildren(...visiblePages().map((p) => h('button', {
      type: 'button', class: `nav-item ${CAD.state.page === p.name ? 'is-active' : ''}`, onClick: () => CAD.go(p.name),
    }, CAD.icon(p.icon || 'note'), h('span', null, p.title))));
  };

  // ------------------------------------------------------------------ the top bar: your unit

  const signOn = () => {
    const me = CAD.state.me;
    const callsign = CAD.input({ placeholder: 'e.g. 1-ADAM-12', maxlength: 12, value: me.lastCallsign || '' });
    const depts = me.departments.map((key) => {
      const d = CAD.cfg('departments', key);
      return { value: key, label: d ? `${d.short} — ${d.label}` : key };
    });
    const dept = CAD.select(depts, me.lastDepartment || (depts[0] && depts[0].value));
    CAD.modal({
      title: 'Sign on duty',
      body: h('div', { class: 'form' }, CAD.field('Callsign', callsign, 'Letters, numbers, spaces and dashes; up to 12'),
        CAD.field('Department', dept)),
      actions: [
        { label: 'Cancel' },
        {
          label: 'Sign on', kind: 'primary',
          onClick: async () => {
            const me2 = await CAD.rpc('unit.signOn', { callsign: callsign.value.trim(), department: dept.value });
            me2.lastCallsign = callsign.value.trim();
            me2.lastDepartment = dept.value;
            CAD.push('me', me2);
            CAD.toast(`On duty as ${me2.unit.callsign}.`, 'success');
            CAD.refresh();
          },
        },
      ],
    });
  };

  const signOff = CAD.run(async () => {
    if (!(await CAD.confirm('Sign off duty?', 'You leave any call you are on, and stop getting calls.', 'Sign off', 'primary'))) return;
    CAD.push('me', await CAD.rpc('unit.signOff'));
    CAD.toast('Off duty.', 'info');
    CAD.refresh();
  });

  const setStatus = (key) => CAD.run(async () => {
    const unit = await CAD.rpc('unit.status', { status: key });
    CAD.push('me', { ...CAD.state.me, unit });
  });

  const panic = CAD.run(async () => {
    if (!(await CAD.confirm('Press the panic button?', 'Every unit is told you need help, at your location.', 'PANIC', 'danger'))) return;
    if (CAD.inGame) await CAD.post('panic', {});
    else CAD.toast('In game, this sends a panic alert at your location.', 'warning');
  });

  let clockTimer = null;
  const renderChrome = () => {
    const s = CAD.state;
    const me = s.me;
    if (!me) return;
    const top = CAD.$('#top');
    const unit = me.unit;
    const parts = [];
    if (unit) {
      const dept = CAD.cfg('departments', unit.department);
      const status = unit.status === 'panic' ? { label: 'PANIC', code: '', color: '#ef4444' } : CAD.cfg('statuses', unit.status);
      parts.push(h('div', { class: 'unit-card' },
        h('span', { class: 'unit-dept', style: { '--c': dept ? dept.color : '#64748b' } }, dept ? dept.short : unit.department),
        h('div', { class: 'unit-id' }, h('b', null, unit.callsign), h('span', null, me.name)),
        CAD.badge(status ? `${status.code ? `${status.code} ` : ''}${status.label}` : unit.status, status && status.color, 'badge-lg')));
      parts.push(h('div', { class: 'status-bar', role: 'group', 'aria-label': 'Your status' },
        (s.config.statuses || []).map((st) => h('button', {
          type: 'button', class: `status-btn ${unit.status === st.key ? 'is-active' : ''}`, style: { '--c': st.color },
          title: st.label, onClick: setStatus(st.key),
        }, h('b', null, st.code), h('span', null, st.label)))));
    } else {
      parts.push(h('div', { class: 'unit-card is-off' }, h('div', { class: 'unit-id' }, h('b', null, me.name),
        h('span', null, CAD.can('unit.signon') ? 'Off duty' : 'Civilian'))));
      if (CAD.can('unit.signon')) parts.push(CAD.button('Sign on duty', signOn, { kind: 'primary', icon: 'power' }));
    }
    parts.push(h('div', { class: 'top-spacer' }));
    if (unit) {
      parts.push(h('button', { type: 'button', class: 'panic-btn', onClick: panic, title: 'Panic button' }, CAD.icon('panic'), 'PANIC'));
      parts.push(CAD.button('Sign off', signOff, { icon: 'power', small: true }));
    }
    const clock = h('div', { class: 'clock' });
    const tick = () => { clock.textContent = CAD.fmt.time(Date.now() / 1000); };
    tick();
    clearInterval(clockTimer);
    clockTimer = setInterval(tick, 10000);
    parts.push(clock);
    parts.push(h('button', { type: 'button', class: 'icon-btn', 'aria-label': 'Close the tablet', title: 'Close (Esc)', onClick: CAD.close },
      CAD.icon('close', 20)));
    top.replaceChildren(...parts);

    const foot = CAD.$('#side-foot');
    const roles = Object.keys(me.roles || {}).filter((r) => me.roles[r]);
    foot.replaceChildren(h('div', { class: 'who' }, h('b', null, me.name), h('span', null, roles.length ? roles.join(', ') : 'civilian')));
    renderNav();
  };

  // ------------------------------------------------------------------ opening and closing

  const tablet = () => CAD.$('#tablet');
  const hide = () => {
    CAD.state.open = false;
    tablet().hidden = true;
    CAD.$('#modals').replaceChildren();
    if (!inGame) CAD.$('#mock-open').hidden = false;
  };

  CAD.close = () => {
    hide();
    CAD.post('close', {});
  };

  // Opens the tablet: loads who you are, the dispatch board if you can see it, then the page.
  CAD.open = CAD.run(async (page) => {
    CAD.state.open = true;
    tablet().hidden = false;
    CAD.$('#mock-open').hidden = true;
    const keep = CAD.state.me || {};
    const session = await CAD.rpc('session');
    session.me.lastCallsign = keep.lastCallsign;
    session.me.lastDepartment = keep.lastDepartment;
    CAD.state.me = session.me;
    CAD.state.config = session.config;
    renderChrome();
    if (CAD.can('dispatch.view')) {
      // The board failing to load shouldn't keep you out of the rest of the tablet.
      try {
        const [units, calls] = await Promise.all([CAD.rpc('unit.list'), CAD.rpc('call.list', {})]);
        CAD.state.units = CAD.list(units);
        CAD.state.calls = CAD.list(calls).filter((c) => c.status !== 'closed');
        sortCalls();
      } catch (e) {
        CAD.toast(e.message || String(e), 'error');
      }
    }
    await CAD.go(page || CAD.state.page || firstPage());
  });

  document.addEventListener('keydown', (e) => {
    if (e.key !== 'Escape' || !CAD.state.open) return;
    const overlays = CAD.$$('#modals .overlay');
    if (overlays.length) overlays[overlays.length - 1].remove();
    else CAD.close();
  });

  // In a normal browser (the preview), open straight away with made-up data.
  window.addEventListener('load', () => {
    if (inGame) return;
    document.body.classList.add('is-preview');
    CAD.$('#mock-open').addEventListener('click', () => CAD.open());
    const query = new URLSearchParams(window.location.search);
    const page = query.get('page');
    const id = Number(query.get('id'));
    CAD.open(page || undefined).then(() => { if (page && id) CAD.go(page, { id }); });
  });
})();
