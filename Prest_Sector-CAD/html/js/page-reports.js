'use strict';
// Reports: the list with filters, reading one (people, vehicles, the call, charges and totals), and
// writing one (saved as a draft or submitted; supervisors approve).

(() => {
  const { h } = CAD;
  const R = CAD.rec;

  const typeOf = (key) => CAD.cfg('reportTypes', key) || { key, label: key };
  const view = { type: '', status: '', mine: false, query: '' };

  // ------------------------------------------------------------------ the list

  const list = (root) => {
    const types = CAD.select([{ value: '', label: 'All types' }, ...CAD.options('reportTypes')], view.type);
    const status = CAD.select([{ value: '', label: 'Any status' }, { value: 'draft', label: 'Drafts' }, { value: 'submitted', label: 'Submitted' },
      { value: 'approved', label: 'Approved' }], view.status);
    const mine = h('input', { type: 'checkbox', checked: view.mine });
    const query = CAD.input({ placeholder: 'Title, person, author or R-12', value: view.query });
    const results = h('div');
    const run = CAD.run(async () => {
      Object.assign(view, { type: types.value, status: status.value, mine: mine.checked, query: query.value });
      results.replaceChildren(CAD.loading());
      const rows = CAD.list(await CAD.rpc('report.list', { type: view.type, status: view.status, mine: view.mine, query: view.query.trim() }));
      results.replaceChildren(rows.length ? CAD.table([
        { label: 'Report', render: (r) => h('span', { class: 'mono' }, CAD.fmt.id('report', r.id)) },
        { label: 'Type', render: (r) => typeOf(r.type).label },
        { label: 'Title', render: (r) => h('b', null, r.title) },
        { label: 'People', render: (r) => CAD.list(r.personNames).join(', ') || '—' },
        { label: 'Author', render: (r) => (r.author ? `${r.author.callsign ? `${r.author.callsign} ` : ''}${r.author.name}` : '—') },
        { label: 'Status', render: (r) => R.reportStatus(r.status) },
        { label: 'Updated', render: (r) => CAD.fmt.dateTime(r.updatedAt) },
      ], rows, (r) => CAD.go('reports', { id: r.id })) : CAD.empty('No reports match.'));
    });
    [types, status, mine].forEach((el) => el.addEventListener('change', run));
    query.addEventListener('input', CAD.debounce(run, 250));
    root.append(
      h('div', { class: 'page-head' }, h('h1', null, 'Reports'),
        h('div', { class: 'search-box' }, CAD.icon('search', 16), query), types, status,
        h('label', { class: 'check' }, mine, 'Mine'),
        h('span', { class: 'spacer' }),
        CAD.can('reports.write') && CAD.list(CAD.state.me.reportTypes).length
          ? CAD.button('New report', () => CAD.go('reports', { new: true }), { kind: 'primary', icon: 'plus' }) : null),
      h('section', { class: 'card' }, results));
    run();
  };

  // ------------------------------------------------------------------ reading one

  const viewer = async (root, id) => {
    root.replaceChildren(CAD.loading());
    const r = await CAD.rpc('report.get', { id });
    const me = CAD.state.me;
    const mine = r.author && r.author.name === me.name;
    const actions = [];
    if ((mine && r.status !== 'approved') || CAD.can('reports.approve')) {
      actions.push(CAD.button('Edit', () => CAD.go('reports', { edit: r.id }), { icon: 'edit' }));
    }
    if (CAD.can('reports.approve') && r.status === 'submitted') {
      actions.push(CAD.button('Approve', CAD.run(async () => {
        await CAD.rpc('report.approve', { id: r.id });
        CAD.toast('Report approved.', 'success');
        viewer(root, id);
      }), { kind: 'primary', icon: 'check' }));
    }
    if (CAD.can('records.delete')) {
      actions.push(CAD.button('', CAD.run(async () => {
        if (!(await CAD.confirm(`Delete ${CAD.fmt.id('report', r.id)}?`, 'The report is removed for good.', 'Delete'))) return;
        await CAD.rpc('report.delete', { id: r.id });
        CAD.toast('Deleted.', 'info');
        CAD.go('reports');
      }), { kind: 'ghost', icon: 'trash', title: 'Delete' }));
    }
    const people = CAD.list(r.personsInfo);
    const vehicles = CAD.list(r.vehiclesInfo);
    root.replaceChildren(
      h('div', { class: 'page-head' }, CAD.button('Reports', () => CAD.go('reports'), { kind: 'ghost', icon: 'back', small: true }),
        h('span', { class: 'spacer' }), actions),
      h('section', { class: 'card rec-report-head' },
        h('div', { class: 'row' }, CAD.badge(typeOf(r.type).label, '#3b82f6', 'badge-lg'), R.reportStatus(r.status),
          h('span', { class: 'mono muted' }, CAD.fmt.id('report', r.id))),
        h('h1', null, r.title),
        h('div', { class: 'rec-meta' },
          h('span', null, `By ${r.author ? `${r.author.callsign ? `${r.author.callsign} ` : ''}${r.author.name}` : 'unknown'}`),
          h('span', null, `Written ${CAD.fmt.dateTime(r.createdAt)}`),
          r.updatedAt !== r.createdAt ? h('span', null, `Updated ${CAD.fmt.dateTime(r.updatedAt)}`) : null,
          r.approvedBy ? h('span', null, `Approved by ${r.approvedBy}`) : null,
          r.callId ? R.link(`Call ${CAD.fmt.call(r.callId)}`, 'dispatch', { id: r.callId }) : null)),
      h('div', { class: 'grid-2' },
        h('section', { class: 'card' }, h('div', { class: 'card-head' }, h('h2', null, 'People')),
          people.length ? h('div', { class: 'stack' }, people.map((s) => h('div', { class: 'row' }, R.personLine(s), h('span', { class: 'spacer' }),
            R.personBadges(s), R.link('Open', 'people', { id: s.id })))) : CAD.empty('Nobody named.')),
        h('section', { class: 'card' }, h('div', { class: 'card-head' }, h('h2', null, 'Vehicles')),
          vehicles.length ? h('div', { class: 'stack' }, vehicles.map((v) => h('div', { class: 'row' }, R.plate(v.plate),
            h('span', null, [v.color, v.model].filter(Boolean).join(' ')), h('span', { class: 'spacer' }), R.link('Open', 'vehicles', { id: v.id }))))
            : CAD.empty('No vehicles.'))),
      r.totals || typeOf(r.type).charges ? h('section', { class: 'card' }, h('div', { class: 'card-head' }, h('h2', null, 'Charges')), R.chargesTable(r.totals)) : null,
      h('section', { class: 'card' }, h('div', { class: 'card-head' }, h('h2', null, 'Narrative')),
        r.narrative ? h('div', { class: 'selectable rec-pre rec-narrative' }, r.narrative) : CAD.empty('No narrative written.')));
  };

  // ------------------------------------------------------------------ writing one

  const editor = async (root, params) => {
    root.replaceChildren(CAD.loading());
    const me = CAD.state.me;
    const allowed = CAD.list(me.reportTypes);
    let r = { type: params.type || allowed[0], title: '', narrative: '', persons: [], vehicles: [], callId: params.callId || null, charges: [] };
    let people = [];
    let vehicles = [];
    if (params.edit) {
      r = await CAD.rpc('report.get', { id: params.edit });
      people = CAD.list(r.personsInfo);
      vehicles = CAD.list(r.vehiclesInfo);
    } else {
      if (params.personId) people = [(await CAD.rpc('person.get', { id: params.personId })).summary];
      if (params.vehicleId) vehicles = [(await CAD.rpc('vehicle.get', { id: params.vehicleId })).vehicle];
    }
    const typeOptions = allowed.map((key) => ({ value: key, label: typeOf(key).label }));
    if (r.type && !allowed.includes(r.type)) typeOptions.push({ value: r.type, label: typeOf(r.type).label });
    const type = CAD.select(typeOptions, r.type);
    const title = CAD.input({ value: r.title, maxlength: 80, placeholder: 'e.g. Arrest of Marcus Bell for armed robbery' });
    const narrative = CAD.textarea({ value: r.narrative || '', maxlength: 8000, rows: 12,
      placeholder: 'What happened, in order: the call, what you saw, what was said, what you did.' });
    const callId = CAD.input({ type: 'number', value: r.callId || '', min: 1, placeholder: 'e.g. 1004' });
    const charges = CAD.chargesEditor(r.charges);
    const chargesCard = h('section', { class: 'card' }, h('div', { class: 'card-head' }, h('h2', null, 'Charges')), charges.node);
    const syncType = () => { chargesCard.hidden = !typeOf(type.value).charges; };
    type.addEventListener('change', syncType);
    syncType();

    const peopleList = h('div', { class: 'stack' });
    const vehicleList = h('div', { class: 'stack' });
    const drawPeople = () => peopleList.replaceChildren(...(people.length ? people.map((s, i) => h('div', { class: 'row' }, R.personLine(s),
      h('span', { class: 'spacer' }), R.personBadges(s),
      h('button', { type: 'button', class: 'icon-btn', 'aria-label': 'Remove', onClick: () => { people.splice(i, 1); drawPeople(); } }, CAD.icon('close', 16))))
      : [h('div', { class: 'muted' }, 'Nobody named yet.')]));
    const drawVehicles = () => vehicleList.replaceChildren(...(vehicles.length ? vehicles.map((v, i) => h('div', { class: 'row' }, R.plate(v.plate),
      h('span', null, [v.color, v.model].filter(Boolean).join(' ')), h('span', { class: 'spacer' }),
      h('button', { type: 'button', class: 'icon-btn', 'aria-label': 'Remove', onClick: () => { vehicles.splice(i, 1); drawVehicles(); } }, CAD.icon('close', 16))))
      : [h('div', { class: 'muted' }, 'No vehicles yet.')]));
    drawPeople();
    drawVehicles();

    const save = (status) => CAD.run(async () => {
      const saved = await CAD.rpc('report.save', { report: {
        id: r.id, type: type.value, title: title.value, narrative: narrative.value, status,
        persons: people.map((p) => p.id), vehicles: vehicles.map((v) => v.id),
        callId: callId.value ? Number(callId.value) : null,
        charges: typeOf(type.value).charges ? charges.value() : [],
      } });
      CAD.toast(status === 'submitted' ? 'Report submitted.' : 'Draft saved.', 'success');
      CAD.go('reports', { id: saved.id });
    });

    root.replaceChildren(
      h('div', { class: 'page-head' }, CAD.button('Reports', () => CAD.go('reports'), { kind: 'ghost', icon: 'back', small: true }),
        h('h1', null, r.id ? `Edit ${CAD.fmt.id('report', r.id)}` : 'New report'), h('span', { class: 'spacer' }),
        CAD.button('Save draft', save('draft')),
        r.status === 'approved' ? CAD.button('Save', save('submitted'), { kind: 'primary', icon: 'check' })
          : CAD.button('Submit', save('submitted'), { kind: 'primary', icon: 'check' })),
      h('section', { class: 'card' }, h('div', { class: 'form-grid' },
        CAD.field('Type', type), CAD.field('Call', callId, 'The call this report is for (optional)'),
        h('div', { class: 'wide' }, CAD.field('Title', title)))),
      h('div', { class: 'grid-2' },
        h('section', { class: 'card' }, h('div', { class: 'card-head' }, h('h2', null, 'People'), h('span', { class: 'spacer' }),
          CAD.button('Add person', CAD.run(async () => {
            const s = await CAD.pick.person();
            if (s && !people.some((p) => p.id === s.id)) { people.push(s); drawPeople(); }
          }), { small: true, icon: 'plus' })), peopleList),
        h('section', { class: 'card' }, h('div', { class: 'card-head' }, h('h2', null, 'Vehicles'), h('span', { class: 'spacer' }),
          CAD.button('Add vehicle', CAD.run(async () => {
            const v = await CAD.pick.vehicle();
            if (v && !vehicles.some((x) => x.id === v.id)) { vehicles.push(v); drawVehicles(); }
          }), { small: true, icon: 'plus' })), vehicleList)),
      chargesCard,
      h('section', { class: 'card' }, h('div', { class: 'card-head' }, h('h2', null, 'Narrative')), narrative));
  };

  CAD.page('reports', {
    title: 'Reports', icon: 'report', order: 40,
    ability: (me) => Boolean(me && me.abilities && (me.abilities['reports.write'] || me.abilities['records.view'])),
    render: (root, params) => {
      if (params && params.id) return viewer(root, params.id);
      if (params && (params.new || params.edit)) return editor(root, params);
      return list(root);
    },
  });
})();
