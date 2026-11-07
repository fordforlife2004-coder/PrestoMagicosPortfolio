'use strict';
// The dispatch board: open calls (by priority, then oldest), the selected call's details, notes and
// units, and every unit on duty. It updates live from the server's pushes without touching what you
// are typing, and call ages tick along on their own.

(() => {
  const { h } = CAD;

  // What the board shows, kept while you move between pages.
  const view = { selected: null, filter: 'all', service: '', query: '', showClosed: false, closed: [] };

  const priorityOf = (level) => CAD.cfg('priorities', level, 'level') || { label: `P${level}`, color: '#64748b' };
  const codeOf = (code) => CAD.cfg('callCodes', code, 'code');
  const unitById = (id) => CAD.state.units.find((u) => u.id === id) || null;
  const myUnit = () => (CAD.state.me && CAD.state.me.unit) || null;
  const allCalls = () => CAD.state.calls.concat(view.showClosed ? view.closed : []);
  // A call you just closed stays open on screen even when closed calls aren't listed.
  const callById = (id) => CAD.state.calls.concat(view.closed).find((c) => c.id === id) || null;
  const deptColor = (key) => { const d = CAD.cfg('departments', key); return d ? d.color : '#64748b'; };
  const deptShort = (key) => { const d = CAD.cfg('departments', key); return d ? d.short : key; };
  const statusOf = (key) => (key === 'panic' ? { label: 'PANIC', code: '', color: '#ef4444' } : CAD.cfg('statuses', key));
  const canManage = () => CAD.can('dispatch.manage');
  const onCall = (call) => { const u = myUnit(); return Boolean(u && CAD.list(call.units).includes(u.id)); };
  const canWork = (call) => canManage() || onCall(call);

  const unitChip = (id) => {
    const u = unitById(id);
    if (!u) return h('span', { class: 'dispatch-chip is-gone' }, `#${id}`);
    return h('span', { class: `dispatch-chip ${u.status === 'panic' ? 'is-panic' : ''}`, style: { '--c': deptColor(u.department) } }, u.callsign);
  };

  const statusBadge = (key) => {
    const st = statusOf(key);
    return CAD.badge(st ? `${st.code ? `${st.code} ` : ''}${st.label}` : key, st && st.color);
  };

  // ------------------------------------------------------------------ the call list

  const matches = (call) => {
    if (view.filter === 'mine' && !onCall(call)) return false;
    if (view.filter === 'pending' && call.status !== 'pending') return false;
    if (view.service && call.service !== view.service && call.service !== 'all') return false;
    const q = view.query.trim().toLowerCase();
    if (!q) return true;
    const units = CAD.list(call.units).map((id) => (unitById(id) || {}).callsign || '').join(' ');
    return [`#${call.id}`, call.code, call.title, call.description, call.location && call.location.street, units]
      .some((text) => String(text || '').toLowerCase().includes(q));
  };

  const callCard = (call) => {
    const p = priorityOf(call.priority);
    const svc = CAD.cfg('services', call.service);
    return h('button', {
      type: 'button', class: `dispatch-call ${view.selected === call.id ? 'is-selected' : ''} ${call.status === 'closed' ? 'is-closed' : ''}
        ${call.source === 'panic' && call.status !== 'closed' ? 'is-panic' : ''}`.replace(/\s+/g, ' '),
      style: { '--p': p.color }, onClick: () => select(call.id),
    },
    h('div', { class: 'dispatch-call-top' },
      h('span', { class: 'mono' }, CAD.fmt.call(call.id)),
      h('span', { class: 'dispatch-code' }, call.code),
      h('span', { class: 'spacer' }),
      call.status === 'pending' ? CAD.badge('Pending', '#f59e0b') : null,
      call.status === 'closed' ? CAD.badge('Closed', '#64748b') : null,
      h('span', { class: 'dispatch-age', 'data-since': call.createdAt }, CAD.fmt.ago(call.createdAt))),
    h('div', { class: 'dispatch-call-title' }, call.title),
    h('div', { class: 'dispatch-call-where' }, CAD.icon('map', 13), (call.location && call.location.street) || 'No location given'),
    h('div', { class: 'dispatch-call-foot' },
      CAD.badge(p.label, p.color),
      svc ? h('span', { class: 'dispatch-service' }, svc.label) : null,
      h('span', { class: 'spacer' }),
      CAD.list(call.units).map(unitChip)));
  };

  // ------------------------------------------------------------------ the selected call

  let refs = {}; // the parts of the board that update live

  const noteRow = (n) => h('li', { class: `dispatch-note ${n.system ? 'is-system' : ''}` },
    h('div', { class: 'dispatch-note-head' }, h('b', null, n.by || ''), h('span', null, CAD.fmt.time(n.at))),
    h('div', { class: 'dispatch-note-text selectable' }, n.text));

  const renderNotes = (call) => {
    const list = refs.notes;
    if (!list) return;
    const atBottom = list.scrollHeight - list.scrollTop - list.clientHeight < 40;
    list.replaceChildren(...CAD.list(call.notes).map(noteRow));
    if (atBottom) list.scrollTop = list.scrollHeight;
  };

  const renderCallUnits = (call) => {
    if (!refs.units) return;
    const ids = CAD.list(call.units);
    const rows = ids.map((id) => {
      const u = unitById(id);
      const mine = myUnit() && myUnit().id === id;
      return h('li', { class: 'dispatch-unit-row' },
        h('span', { class: 'dispatch-star', title: call.primary === id ? 'Primary unit' : '' }, call.primary === id ? '★' : ''),
        unitChip(id),
        h('span', { class: 'muted' }, u ? u.name : 'Off duty'),
        h('span', { class: 'spacer' }),
        u ? statusBadge(u.status) : null,
        call.status !== 'closed' && (mine || canManage())
          ? CAD.button(mine ? 'Leave' : 'Detach', CAD.run(async () => {
            CAD.push('call', await CAD.rpc('call.detach', { id: call.id, unit: mine ? undefined : id }));
          }), { small: true, kind: 'ghost' })
          : null);
    });
    const parts = [rows.length ? h('ul', { class: 'dispatch-unit-list' }, rows) : CAD.empty('No units on this call yet.')];
    if (canManage() && call.status !== 'closed') {
      const free = CAD.state.units.filter((u) => !ids.includes(u.id));
      if (free.length) {
        const pick = CAD.select(free.map((u) => ({
          value: u.id, label: `${u.callsign} (${deptShort(u.department)}) — ${(statusOf(u.status) || {}).label || u.status}${u.callId ? ` on #${u.callId}` : ''}`,
        })), free[0].id);
        parts.push(h('div', { class: 'row dispatch-assign' }, pick, CAD.button('Attach', CAD.run(async () => {
          CAD.push('call', await CAD.rpc('call.attach', { id: call.id, unit: Number(pick.value) }));
        }), { icon: 'link' })));
      }
    }
    refs.units.replaceChildren(...parts);
  };

  const closeCall = (call) => {
    const disposition = CAD.select(CAD.list(CAD.state.config.dispositions), CAD.list(CAD.state.config.dispositions)[0]);
    CAD.modal({
      title: `Close ${CAD.fmt.call(call.id)}`,
      body: h('div', { class: 'form' }, CAD.field('How did it end?', disposition),
        h('p', { class: 'muted' }, 'Every unit on the call is taken off it.')),
      actions: [{ label: 'Cancel' }, {
        label: 'Close call', kind: 'primary',
        onClick: async () => CAD.push('call', await CAD.rpc('call.close', { id: call.id, disposition: disposition.value })),
      }],
    });
  };

  const renderActions = (call) => {
    if (!refs.actions) return;
    const unit = myUnit();
    const buttons = [];
    if (call.status !== 'closed') {
      if (unit && !onCall(call)) {
        buttons.push(CAD.button('Attach me', CAD.run(async () => CAD.push('call', await CAD.rpc('call.attach', { id: call.id }))),
          { kind: 'primary', icon: 'link' }));
      }
      if (unit && onCall(call)) {
        buttons.push(CAD.button('Leave call', CAD.run(async () => CAD.push('call', await CAD.rpc('call.detach', { id: call.id }))),
          { icon: 'back' }));
      }
    }
    if (call.location && call.location.x !== undefined && call.location.x !== null) {
      buttons.push(CAD.button('Set GPS', () => {
        CAD.post('waypoint', { x: call.location.x, y: call.location.y });
        if (!CAD.inGame) CAD.toast('In game, this sets your GPS to the call.', 'info');
      }, { icon: 'map' }));
    }
    if (CAD.can('reports.write')) buttons.push(CAD.button('Write report', () => CAD.go('reports', { new: true, callId: call.id }), { icon: 'report' }));
    if (call.status !== 'closed' && (canManage() || (unit && call.primary === unit.id))) {
      buttons.push(CAD.button('Close call', () => closeCall(call), { kind: 'danger', icon: 'check' }));
    }
    if (call.status === 'closed' && canManage()) {
      buttons.push(CAD.button('Reopen', CAD.run(async () => CAD.push('call', await CAD.rpc('call.reopen', { id: call.id }))), { icon: 'back' }));
    }
    refs.actions.replaceChildren(...buttons);
  };

  const renderHead = (call) => {
    if (!refs.head) return;
    const p = priorityOf(call.priority);
    const code = codeOf(call.code);
    refs.head.replaceChildren(
      h('div', { class: 'row' },
        CAD.badge(p.label, p.color, 'badge-lg'),
        h('span', { class: 'mono dispatch-detail-id' }, CAD.fmt.call(call.id)),
        h('span', { class: 'dispatch-code' }, call.code),
        code ? h('span', { class: 'muted' }, code.label) : null,
        h('span', { class: 'spacer' }),
        call.status === 'closed' ? CAD.badge(`Closed: ${call.disposition || ''}`, '#64748b')
          : CAD.badge(call.status === 'pending' ? 'Pending' : 'Active', call.status === 'pending' ? '#f59e0b' : '#22c55e')),
      h('h2', { class: 'dispatch-detail-title' }, call.title),
      h('div', { class: 'dispatch-detail-meta' },
        h('span', null, `Opened ${CAD.fmt.dateTime(call.createdAt)} (${CAD.fmt.ago(call.createdAt)} ago)`),
        h('span', null, `Source: ${call.source}`),
        call.caller ? h('span', null, `Caller: ${call.caller.name || 'Unknown'}`) : null));
  };

  // The edit form is built once per call, so live updates never wipe what you are typing.
  const editForm = (call) => {
    const codes = CAD.list(CAD.state.config.callCodes).map((c) => ({ value: c.code, label: `${c.code} — ${c.label}` }));
    const f = {
      title: CAD.input({ value: call.title, maxlength: 80 }),
      code: CAD.select(codes, call.code),
      priority: CAD.select(CAD.list(CAD.state.config.priorities).map((p) => ({ value: p.level, label: p.label })), call.priority),
      service: CAD.select(CAD.options('services'), call.service),
      description: CAD.textarea({ value: call.description || '', maxlength: 2000, rows: 3 }),
    };
    refs.form = f;
    const save = CAD.run(async () => {
      const updated = await CAD.rpc('call.update', {
        id: call.id, title: f.title.value, code: f.code.value, priority: Number(f.priority.value), service: f.service.value,
        description: f.description.value,
      });
      CAD.push('call', updated);
      CAD.toast('Call updated.', 'success');
    });
    return h('div', { class: 'form' },
      h('div', { class: 'form-grid' },
        h('div', { class: 'wide' }, CAD.field('Title', f.title)),
        CAD.field('Type', f.code), CAD.field('Priority', f.priority), CAD.field('For', f.service)),
      CAD.field('Details', f.description),
      h('div', { class: 'row' }, h('span', { class: 'spacer' }), CAD.button('Save changes', save, { kind: 'primary', small: true })));
  };

  // Fills fields that changed elsewhere, unless you're typing in them.
  const syncForm = (call) => {
    const f = refs.form;
    if (!f) return;
    const set = (input, value) => { if (document.activeElement !== input && String(input.value) !== String(value ?? '')) input.value = value ?? ''; };
    set(f.title, call.title);
    set(f.code, call.code);
    set(f.priority, call.priority);
    set(f.service, call.service);
    set(f.description, call.description);
  };

  const readOnly = (call) => h('dl', { class: 'facts' },
    h('dt', null, 'For'), h('dd', null, (CAD.cfg('services', call.service) || {}).label || call.service),
    h('dt', null, 'Details'), h('dd', { class: 'selectable dispatch-pre' }, call.description || '—'));

  const renderDetail = () => {
    const pane = refs.detail;
    if (!pane) return;
    const call = callById(view.selected);
    if (!call) {
      refs.head = refs.actions = refs.units = refs.notes = refs.form = null;
      pane.replaceChildren(h('div', { class: 'dispatch-pick' }, CAD.icon('dispatch', 34),
        h('p', null, 'Pick a call to see its details, units and notes.'),
        CAD.can('calls.create') ? CAD.button('New call', newCall, { kind: 'primary', icon: 'plus' }) : null));
      return;
    }
    refs.head = h('div', { class: 'dispatch-detail-head' });
    refs.actions = h('div', { class: 'row dispatch-actions' });
    refs.units = h('div');
    refs.notes = h('ol', { class: 'dispatch-notes scroll' });
    refs.form = null;
    const note = CAD.input({ placeholder: 'Add a note and press Enter', maxlength: 500 });
    const send = CAD.run(async () => {
      const text = note.value.trim();
      if (!text) return;
      note.disabled = true;
      try {
        CAD.push('call', await CAD.rpc('call.note', { id: call.id, text }));
        note.value = '';
      } finally {
        note.disabled = false;
        note.focus();
      }
    });
    note.addEventListener('keydown', (e) => { if (e.key === 'Enter') send(); });
    const where = call.location
      ? h('div', { class: 'dispatch-where' }, CAD.icon('map', 15), h('span', { class: 'selectable' }, call.location.street || 'Map position only'),
        call.location.x !== undefined && call.location.x !== null
          ? h('span', { class: 'mono muted' }, `${Math.round(call.location.x)}, ${Math.round(call.location.y)}`) : null)
      : h('div', { class: 'dispatch-where muted' }, CAD.icon('map', 15), 'No location given');
    const editable = call.status !== 'closed' && canWork(call);
    pane.replaceChildren(
      h('section', { class: 'card dispatch-detail-card' }, refs.head, where, refs.actions),
      h('section', { class: 'card' }, h('div', { class: 'card-head' }, h('h2', null, editable ? 'Call details' : 'Details')),
        editable ? editForm(call) : readOnly(call)),
      h('section', { class: 'card' }, h('div', { class: 'card-head' }, h('h2', null, 'Units on the call')), refs.units),
      h('section', { class: 'card dispatch-notes-card' }, h('div', { class: 'card-head' }, h('h2', null, 'Notes')), refs.notes,
        call.status !== 'closed' && canWork(call) ? h('div', { class: 'row dispatch-note-add' }, note, CAD.button('Add', send, { small: true })) : null));
    renderHead(call);
    renderActions(call);
    renderCallUnits(call);
    renderNotes(call);
    refs.notes.scrollTop = refs.notes.scrollHeight;
  };

  // Updates the open call in place after a push.
  const updateDetail = () => {
    const call = callById(view.selected);
    if (!call || !refs.head) return renderDetail();
    // Someone else's edit made the form appear or go: draw it all again.
    const editable = call.status !== 'closed' && canWork(call);
    if (editable !== Boolean(refs.form)) return renderDetail();
    renderHead(call);
    renderActions(call);
    renderCallUnits(call);
    renderNotes(call);
    syncForm(call);
    return undefined;
  };

  // ------------------------------------------------------------------ units

  const unitCard = (u) => {
    const call = u.callId ? CAD.state.calls.find((c) => c.id === u.callId) : null;
    const selected = callById(view.selected);
    const controls = [];
    if (canManage() && u.id !== (myUnit() || {}).id) {
      const pick = CAD.select(CAD.options('statuses', 'label'), u.status === 'panic' ? '' : u.status, { 'aria-label': `Status of ${u.callsign}` });
      if (u.status === 'panic') pick.prepend(h('option', { value: '', selected: true }, 'PANIC'));
      pick.addEventListener('change', CAD.run(async () => { await CAD.rpc('unit.status', { status: pick.value, unit: u.id }); }));
      controls.push(pick);
    }
    if (canManage() && selected && selected.status !== 'closed' && !CAD.list(selected.units).includes(u.id)) {
      controls.push(CAD.button(`To ${CAD.fmt.call(selected.id)}`, CAD.run(async () => {
        CAD.push('call', await CAD.rpc('call.attach', { id: selected.id, unit: u.id }));
      }), { small: true, icon: 'link' }));
    }
    return h('li', { class: `dispatch-unit ${u.status === 'panic' ? 'is-panic' : ''}` },
      h('div', { class: 'row' },
        h('span', { class: 'unit-dept', style: { '--c': deptColor(u.department) } }, deptShort(u.department)),
        h('b', { class: 'mono' }, u.callsign),
        h('span', { class: 'spacer' }),
        statusBadge(u.status)),
      h('div', { class: 'dispatch-unit-sub' },
        h('span', null, u.name),
        h('span', { class: 'dispatch-age', 'data-since': u.since }, CAD.fmt.ago(u.since))),
      u.location && u.location.street ? h('div', { class: 'dispatch-unit-sub muted' }, CAD.icon('map', 12), u.location.street) : null,
      call ? h('button', { type: 'button', class: 'dispatch-unit-call', onClick: () => select(call.id) },
        `${CAD.fmt.call(call.id)} ${call.code} ${call.title}`) : null,
      controls.length ? h('div', { class: 'row dispatch-unit-controls' }, controls) : null);
  };

  const renderUnits = () => {
    if (!refs.unitList) return;
    const order = (u) => (u.status === 'panic' ? -1 : CAD.list(CAD.state.config.statuses).findIndex((s) => s.key === u.status));
    const units = [...CAD.state.units].sort((a, b) => (order(a) - order(b)) || a.callsign.localeCompare(b.callsign));
    const available = units.filter((u) => u.status === 'available').length;
    refs.unitCount.textContent = `${units.length} on duty, ${available} available`;
    refs.unitList.replaceChildren(...(units.length ? units.map(unitCard) : [CAD.empty('Nobody is on duty.')]));
  };

  // ------------------------------------------------------------------ the whole board

  const renderList = () => {
    if (!refs.callList) return;
    const calls = allCalls().filter(matches);
    const open = CAD.state.calls.length;
    refs.callCount.textContent = `${open} open${view.showClosed ? `, ${view.closed.length} closed` : ''}`;
    refs.callList.replaceChildren(...(calls.length ? calls.map(callCard)
      : [CAD.empty(view.query || view.filter !== 'all' || view.service ? 'No calls match.' : 'No open calls. Quiet shift.')]));
  };

  const select = (id) => {
    view.selected = id;
    renderList();
    renderDetail();
    renderUnits();
  };

  const loadClosed = CAD.run(async () => {
    const list = CAD.list(await CAD.rpc('call.list', { closed: true }));
    view.closed = list.filter((c) => c.status === 'closed');
    renderList();
  });

  // The new call form.
  const newCall = () => {
    const codes = CAD.list(CAD.state.config.callCodes);
    const code = CAD.select(codes.map((c) => ({ value: c.code, label: `${c.code} — ${c.label}` })), codes[0] && codes[0].code);
    const title = CAD.input({ maxlength: 80, placeholder: codes[0] ? codes[0].label : '' });
    const priority = CAD.select(CAD.list(CAD.state.config.priorities).map((p) => ({ value: p.level, label: p.label })), codes[0] && codes[0].priority);
    const service = CAD.select(CAD.options('services'), codes[0] && codes[0].service);
    const description = CAD.textarea({ maxlength: 2000, rows: 3, placeholder: 'What is happening, who is involved, any danger' });
    const onDuty = Boolean(myUnit());
    const useMine = h('input', { type: 'checkbox', checked: onDuty && myUnit().role !== 'dispatch' });
    const street = CAD.input({ maxlength: 80, placeholder: 'e.g. Grove St / Forum Dr, Davis' });
    const syncStreet = () => { street.disabled = useMine.checked; };
    useMine.addEventListener('change', syncStreet);
    syncStreet();
    code.addEventListener('change', () => {
      const c = codes.find((x) => x.code === code.value);
      if (!c) return;
      title.placeholder = c.label;
      priority.value = c.priority;
      service.value = c.service;
    });
    CAD.modal({
      title: 'New call',
      wide: true,
      body: h('div', { class: 'form' },
        h('div', { class: 'form-grid' },
          CAD.field('Type', code), CAD.field('Title', title, 'Leave empty to use the type'),
          CAD.field('Priority', priority), CAD.field('For', service),
          h('div', { class: 'wide' }, CAD.field('Details', description)),
          h('div', { class: 'wide' }, CAD.field('Where', street)),
          onDuty ? h('label', { class: 'check wide' }, useMine, 'Use my location') : null)),
      actions: [{ label: 'Cancel' }, {
        label: 'Create call', kind: 'primary',
        onClick: async () => {
          const call = await CAD.rpc('call.create', {
            code: code.value, title: title.value, priority: Number(priority.value), service: service.value, description: description.value,
            useMyLocation: onDuty && useMine.checked, location: useMine.checked ? undefined : { street: street.value },
          });
          CAD.push('call', call);
          CAD.toast(`Call ${CAD.fmt.call(call.id)} created.`, 'success');
          select(call.id);
        },
      }],
    });
  };

  // Call and unit ages tick along without redrawing anything else.
  let ticker = null;
  const startTicker = (root) => {
    clearInterval(ticker);
    ticker = setInterval(() => {
      if (!root.isConnected) { clearInterval(ticker); return; }
      CAD.$$('.dispatch-age', root).forEach((el) => { el.textContent = CAD.fmt.ago(Number(el.dataset.since)); });
    }, 15000);
  };

  CAD.page('dispatch', {
    title: 'Dispatch',
    icon: 'dispatch',
    ability: 'dispatch.view',
    order: 10,
    render(root, params) {
      if (params && params.id) view.selected = Number(params.id);
      const filters = h('div', { class: 'dispatch-filters', role: 'group', 'aria-label': 'Show' },
        [['all', 'All'], ['mine', 'Mine'], ['pending', 'Pending']].map(([key, label]) => h('button', {
          type: 'button', class: `dispatch-filter ${view.filter === key ? 'is-active' : ''}`,
          onClick: (e) => {
            view.filter = key;
            CAD.$$('.dispatch-filter', root).forEach((b) => b.classList.toggle('is-active', b === e.currentTarget));
            renderList();
          },
        }, label)));
      const service = CAD.select([{ value: '', label: 'All services' }, ...CAD.options('services')], view.service);
      service.addEventListener('change', () => { view.service = service.value; renderList(); });
      const search = CAD.input({ placeholder: 'Search calls', value: view.query });
      search.addEventListener('input', CAD.debounce(() => { view.query = search.value; renderList(); }, 150));
      const closed = h('input', { type: 'checkbox', checked: view.showClosed });
      closed.addEventListener('change', () => {
        view.showClosed = closed.checked;
        if (view.showClosed) loadClosed(); else renderList();
      });

      refs = {
        callList: h('div', { class: 'dispatch-calls scroll' }),
        callCount: h('span', { class: 'muted' }),
        detail: h('div', { class: 'dispatch-detail scroll' }),
        unitList: h('ul', { class: 'dispatch-units scroll' }),
        unitCount: h('span', { class: 'muted' }),
      };
      root.append(
        h('div', { class: 'page-head dispatch-head' },
          h('h1', null, 'Dispatch'),
          filters, service,
          h('div', { class: 'search-box' }, CAD.icon('search', 16), search),
          h('label', { class: 'check' }, closed, 'Closed calls'),
          h('span', { class: 'spacer' }),
          CAD.can('calls.create') ? CAD.button('New call', newCall, { kind: 'primary', icon: 'plus' }) : null),
        h('div', { class: 'dispatch-board' },
          h('section', { class: 'dispatch-col' }, h('div', { class: 'dispatch-col-head' }, h('h2', null, 'Calls'), refs.callCount), refs.callList),
          h('section', { class: 'dispatch-col dispatch-col-detail' }, refs.detail),
          h('section', { class: 'dispatch-col' }, h('div', { class: 'dispatch-col-head' }, h('h2', null, 'Units'), refs.unitCount), refs.unitList)));
      renderList();
      renderDetail();
      renderUnits();
      if (view.showClosed) loadClosed();
      startTicker(root);
    },
    onPush(kind, data) {
      if (kind === 'call' && data && data.status === 'closed') {
        view.closed = [data, ...view.closed.filter((c) => c.id !== data.id)].slice(0, 50);
      } else if (kind === 'call' && data) {
        view.closed = view.closed.filter((c) => c.id !== data.id);
      }
      if (kind === 'call' || kind === 'units' || kind === 'me') {
        renderList();
        updateDetail();
        renderUnits();
      }
    },
  });
})();
