'use strict';
// People: search by name, date of birth or phone, and a profile with licenses, flags, vehicles,
// weapons, reports, warrants and BOLOs. Also the pieces the other record pages share: badges, the
// person and vehicle pickers, and the charges editor.

(() => {
  const { h } = CAD;

  // ------------------------------------------------------------------ shared pieces

  const R = CAD.rec = {};

  R.initials = (p) => `${(p.first || '?')[0]}${(p.last || '')[0] || ''}`.toUpperCase();
  R.avatar = (p, size = '') => h('div', { class: `rec-avatar ${size}` },
    p.mugshot ? h('img', { src: p.mugshot, alt: '', referrerpolicy: 'no-referrer', onError: (e) => e.target.remove() }) : null,
    p.mugshot ? null : R.initials(p));
  R.plate = (plate) => h('span', { class: 'plate-box' }, plate || '—');
  R.flags = (list, flags) => CAD.list(flags).map((f) => CAD.stateBadge(list, f));

  // A person's warning badges: flags, active warrants, BOLO.
  R.personBadges = (s) => h('div', { class: 'badges' },
    s.warrants > 0 ? CAD.badge(`${s.warrants} warrant${s.warrants === 1 ? '' : 's'}`, '#ef4444') : null,
    s.bolo ? CAD.badge('BOLO', '#f97316') : null,
    R.flags('personFlags', s.flags));

  R.personLine = (s) => h('div', { class: 'rec-person-line' }, R.avatar(s, 'is-small'),
    h('div', null, h('b', null, CAD.fmt.name(s)), h('div', { class: 'muted rec-small' }, [s.dob, s.gender].filter(Boolean).join(' · '))));

  // A link to a record page that also works inside a pop-up (it closes them first).
  R.link = (text, page, params) => h('button', {
    type: 'button', class: 'rec-link',
    onClick: () => { CAD.$('#modals').replaceChildren(); CAD.go(page, params); },
  }, text);

  // A search pop-up. search(query) -> list, row(item) -> node. Resolves the chosen item, or null.
  const pickModal = (title, placeholder, search, row) => new Promise((resolve) => {
    let chosen = null;
    const input = CAD.input({ placeholder });
    const results = h('div', { class: 'rec-pick-results' }, CAD.empty('Start typing to search.'));
    const run = CAD.debounce(CAD.run(async () => {
      const q = input.value.trim();
      if (!q) { results.replaceChildren(CAD.empty('Start typing to search.')); return; }
      const list = CAD.list(await search(q));
      results.replaceChildren(...(list.length ? list.map((item) => h('button', {
        type: 'button', class: 'rec-pick-row', onClick: () => { chosen = item; m.close(); },
      }, row(item))) : [CAD.empty('Nothing found.')]));
    }), 200);
    input.addEventListener('input', run);
    const m = CAD.modal({ title, body: h('div', { class: 'form' }, h('div', { class: 'search-box' }, CAD.icon('search', 16), input), results),
      actions: [{ label: 'Cancel' }] });
    const watch = setInterval(() => { if (!m.root.isConnected) { clearInterval(watch); resolve(chosen); } }, 150);
  });

  CAD.pick = {
    person: () => pickModal('Find a person', 'Name, date of birth or phone',
      (q) => CAD.rpc('person.search', { query: q }), (s) => h('div', { class: 'row' }, R.personLine(s), h('span', { class: 'spacer' }), R.personBadges(s))),
    vehicle: () => pickModal('Find a vehicle', 'Plate, model or owner',
      (q) => CAD.rpc('vehicle.search', { query: q }), (v) => h('div', { class: 'row' }, R.plate(v.plate),
        h('span', null, [v.color, v.model].filter(Boolean).join(' ')), h('span', { class: 'spacer' }), h('span', { class: 'muted' }, v.ownerName || 'No owner'))),
  };

  // The charges editor: pick charges from the penal code, set counts, see the totals.
  // Returns { node, value() } where value() is [{ code, count }].
  CAD.chargesEditor = (initial) => {
    const chosen = CAD.list(initial).map((c) => ({ code: c.code, count: c.count || 1 }));
    const all = [];
    CAD.list(CAD.state.config.penal).forEach((t) => CAD.list(t.charges).forEach((c) => all.push({ ...c, title: t.title })));
    const find = (code) => all.find((c) => c.code === code);
    const list = h('div', { class: 'rec-charges' });
    const totals = h('div', { class: 'rec-charge-totals' });
    const results = h('div', { class: 'rec-charge-results' });
    const search = CAD.input({ placeholder: 'Search the penal code to add a charge' });

    const draw = () => {
      let fine = 0;
      let jail = 0;
      list.replaceChildren(...(chosen.length ? chosen.map((c, i) => {
        const charge = find(c.code) || { name: c.code, fine: 0, jail: 0, class: '' };
        fine += charge.fine * c.count;
        jail += charge.jail * c.count;
        const count = CAD.input({ type: 'number', min: 1, max: 20, value: c.count, class: 'input rec-count', 'aria-label': 'Counts' });
        count.addEventListener('change', () => { c.count = Math.max(1, Math.min(20, Math.round(Number(count.value) || 1))); draw(); });
        return h('div', { class: 'rec-charge' },
          h('span', { class: 'mono rec-small' }, c.code),
          h('span', { class: 'rec-charge-name' }, charge.name),
          CAD.badge(charge.class, R.classColor(charge.class)),
          h('span', { class: 'spacer' }),
          h('span', { class: 'muted rec-small' }, `${CAD.fmt.money(charge.fine)} · ${charge.jail} mo`),
          count,
          h('button', { type: 'button', class: 'icon-btn', 'aria-label': 'Remove', onClick: () => { chosen.splice(i, 1); draw(); } }, CAD.icon('close', 16)));
      }) : [h('div', { class: 'muted rec-small' }, 'No charges yet.')]));
      totals.replaceChildren(h('span', null, 'Total'), h('b', null, CAD.fmt.money(fine)), h('b', null, CAD.fmt.months(jail)));
    };

    const showResults = () => {
      const q = search.value.trim().toLowerCase();
      if (!q) { results.replaceChildren(); return; }
      const hits = all.filter((c) => c.code.toLowerCase().includes(q) || c.name.toLowerCase().includes(q)).slice(0, 8);
      results.replaceChildren(...hits.map((c) => h('button', {
        type: 'button', class: 'rec-pick-row',
        onClick: () => {
          const have = chosen.find((x) => x.code === c.code);
          if (have) have.count = Math.min(20, have.count + 1); else chosen.push({ code: c.code, count: 1 });
          search.value = '';
          results.replaceChildren();
          draw();
          search.focus();
        },
      }, h('span', { class: 'mono rec-small' }, c.code), h('span', null, c.name), h('span', { class: 'spacer' }),
      CAD.badge(c.class, R.classColor(c.class)), h('span', { class: 'muted rec-small' }, `${CAD.fmt.money(c.fine)} · ${c.jail} mo`))));
    };
    search.addEventListener('input', showResults);
    draw();
    return {
      node: h('div', { class: 'rec-charge-editor' }, list, totals, h('div', { class: 'search-box' }, CAD.icon('search', 16), search), results),
      value: () => chosen.map((c) => ({ code: c.code, count: c.count })),
    };
  };

  R.classColor = (cls) => ({ felony: '#ef4444', misdemeanor: '#f59e0b', infraction: '#3b82f6' }[cls] || '#64748b');

  // A table of charges with their totals.
  R.chargesTable = (totals) => {
    if (!totals || !CAD.list(totals.items).length) return CAD.empty('No charges.');
    return h('div', null,
      CAD.table([
        { label: 'Code', render: (i) => h('span', { class: 'mono' }, i.code) },
        { label: 'Charge', render: (i) => i.name },
        { label: 'Class', render: (i) => CAD.badge(i.class, R.classColor(i.class)) },
        { label: 'Counts', class: 'num', render: (i) => String(i.count) },
        { label: 'Fine', class: 'num', render: (i) => CAD.fmt.money(i.fine) },
        { label: 'Jail', class: 'num', render: (i) => (i.jail ? CAD.fmt.months(i.jail) : '—') },
      ], CAD.list(totals.items)),
      h('div', { class: 'rec-charge-totals' }, h('span', null, 'Total'), h('b', null, CAD.fmt.money(totals.fine)), h('b', null, CAD.fmt.months(totals.jail))));
  };

  // ------------------------------------------------------------------ the person form

  R.personForm = (p, after) => {
    const isNew = !p.id;
    const cfg = CAD.state.config;
    const f = {
      first: CAD.input({ value: p.first || '', maxlength: 30 }),
      last: CAD.input({ value: p.last || '', maxlength: 30 }),
      dob: CAD.input({ type: 'date', value: p.dob || '', min: '1900-01-01' }),
      gender: CAD.select(CAD.list(cfg.genders), p.gender || CAD.list(cfg.genders)[0]),
      address: CAD.input({ value: p.address || '', maxlength: 80 }),
      phone: CAD.input({ value: p.phone || '', maxlength: 20 }),
      height: CAD.input({ value: p.height || '', maxlength: 10 }),
      mugshot: CAD.input({ value: p.mugshot || '', maxlength: 300, placeholder: 'https://… (optional)' }),
      description: CAD.textarea({ value: p.description || '', maxlength: 300, rows: 2 }),
      notes: CAD.textarea({ value: p.notes || '', maxlength: 2000, rows: 3, placeholder: 'Only officers see these' }),
    };
    const licenses = {};
    const licenseRows = CAD.list(cfg.licenses).map((l) => {
      licenses[l.key] = CAD.select(CAD.options('licenseStates'), (p.licenses || {})[l.key] || 'none');
      return CAD.field(l.label, licenses[l.key]);
    });
    const flags = {};
    const flagRows = CAD.list(cfg.personFlags).map((fl) => {
      flags[fl.key] = h('input', { type: 'checkbox', checked: CAD.list(p.flags).includes(fl.key) });
      return h('label', { class: 'check' }, flags[fl.key], fl.label);
    });
    CAD.modal({
      title: isNew ? 'New person' : `Edit ${CAD.fmt.name(p)}`,
      wide: true,
      body: h('div', { class: 'form' },
        h('div', { class: 'form-grid' },
          CAD.field('First name', f.first), CAD.field('Last name', f.last), CAD.field('Date of birth', f.dob), CAD.field('Gender', f.gender),
          CAD.field('Address', f.address), CAD.field('Phone', f.phone), CAD.field('Height', f.height), CAD.field('Photo', f.mugshot),
          h('div', { class: 'wide' }, CAD.field('Description', f.description))),
        h('h3', { class: 'rec-form-title' }, 'Licenses'), h('div', { class: 'form-grid rec-grid-4' }, licenseRows),
        h('h3', { class: 'rec-form-title' }, 'Flags'), h('div', { class: 'row rec-flag-picks' }, flagRows),
        CAD.field('Notes', f.notes)),
      actions: [{ label: 'Cancel' }, {
        label: isNew ? 'Create' : 'Save', kind: 'primary',
        onClick: async () => {
          const person = {
            id: p.id, first: f.first.value, last: f.last.value, dob: f.dob.value, gender: f.gender.value, address: f.address.value,
            phone: f.phone.value, height: f.height.value, mugshot: f.mugshot.value, description: f.description.value, notes: f.notes.value,
            licenses: {}, flags: Object.keys(flags).filter((k) => flags[k].checked),
          };
          Object.entries(licenses).forEach(([k, sel]) => { person.licenses[k] = sel.value; });
          const saved = await CAD.rpc('person.save', { person });
          CAD.toast(isNew ? 'Person added.' : 'Saved.', 'success');
          after(saved);
        },
      }],
    });
  };

  // ------------------------------------------------------------------ the profile

  const profile = async (root, id) => {
    root.replaceChildren(CAD.loading());
    const data = await CAD.rpc('person.get', { id });
    const p = data.person;
    const s = data.summary;
    const age = CAD.fmt.age(p.dob);
    const vehicles = CAD.list(data.vehicles);
    const weapons = CAD.list(data.weapons);
    const bolos = CAD.list(data.bolos);
    const reports = data.reports === undefined ? null : CAD.list(data.reports);
    const warrants = data.warrants === undefined ? null : CAD.list(data.warrants);
    const again = () => profile(root, id);

    const actions = [];
    if (CAD.can('records.edit')) actions.push(CAD.button('Edit', () => R.personForm(p, again), { icon: 'edit' }));
    if (CAD.can('reports.write')) actions.push(CAD.button('Write report', () => CAD.go('reports', { new: true, personId: p.id }), { icon: 'report' }));
    if (CAD.can('warrants.request')) actions.push(CAD.button('Request warrant', () => CAD.go('warrants', { new: true, personId: p.id }), { icon: 'warrant' }));
    if (CAD.can('bolos.edit')) actions.push(CAD.button('Add BOLO', () => CAD.go('bolos', { new: true, kind: 'person', personId: p.id }), { icon: 'bolo' }));
    if (CAD.can('records.delete')) {
      actions.push(CAD.button('', CAD.run(async () => {
        if (!(await CAD.confirm(`Delete ${CAD.fmt.name(p)}?`, 'Their vehicles and weapons stay, with no owner. Reports keep their number.', 'Delete'))) return;
        await CAD.rpc('person.delete', { id: p.id });
        CAD.toast('Deleted.', 'info');
        CAD.go('people');
      }), { kind: 'ghost', icon: 'trash', title: 'Delete' }));
    }

    const vehicleTable = () => (vehicles.length ? CAD.table([
      { label: 'Plate', render: (v) => R.plate(v.plate) },
      { label: 'Vehicle', render: (v) => [v.color, v.model].filter(Boolean).join(' ') || '—' },
      { label: 'Registration', render: (v) => CAD.stateBadge('registrationStates', v.registration) },
      { label: 'Insurance', render: (v) => CAD.stateBadge('insuranceStates', v.insurance) },
      { label: 'Flags', render: (v) => h('div', { class: 'badges' }, R.flags('vehicleFlags', v.flags)) },
    ], vehicles, (v) => CAD.go('vehicles', { id: v.id })) : CAD.empty('No vehicles.'));

    const weaponTable = () => (weapons.length ? CAD.table([
      { label: 'Serial', render: (w) => h('span', { class: 'mono' }, w.serial) },
      { label: 'Weapon', render: (w) => w.kind },
      { label: 'Status', render: (w) => CAD.stateBadge('weaponStates', w.status) },
    ], weapons, (w) => CAD.go('weapons', { id: w.id })) : CAD.empty('No weapons.'));

    const reportTable = () => (reports.length ? CAD.table([
      { label: 'Report', render: (r) => h('span', { class: 'mono' }, CAD.fmt.id('report', r.id)) },
      { label: 'Type', render: (r) => (CAD.cfg('reportTypes', r.type) || {}).label || r.type },
      { label: 'Title', render: (r) => r.title },
      { label: 'Status', render: (r) => R.reportStatus(r.status) },
      { label: 'Date', render: (r) => CAD.fmt.date(r.createdAt) },
    ], reports, (r) => CAD.go('reports', { id: r.id })) : CAD.empty('No reports name this person.'));

    const warrantTable = () => (warrants.length ? CAD.table([
      { label: 'Warrant', render: (w) => h('span', { class: 'mono' }, CAD.fmt.id('warrant', w.id)) },
      { label: 'Status', render: (w) => R.warrantStatus(w.status) },
      { label: 'Charges', render: (w) => CAD.list(w.totals && w.totals.items).map((i) => i.name).join(', ') },
      { label: 'Date', render: (w) => CAD.fmt.date(w.createdAt) },
    ], warrants, () => CAD.go('warrants')) : CAD.empty('No warrants.'));

    const boloList = () => (bolos.length ? h('div', { class: 'stack' }, bolos.map((b) => h('div', { class: 'rec-bolo-line' },
      CAD.badge('BOLO', '#f97316'), h('b', null, b.title), h('span', { class: 'muted' }, b.description))))
      : CAD.empty('No active BOLOs.'));

    const licenses = h('div', { class: 'rec-licenses' }, CAD.list(CAD.state.config.licenses).map((l) => h('div', { class: 'rec-license' },
      h('span', null, l.label), CAD.stateBadge('licenseStates', (p.licenses || {})[l.key] || 'none'))));

    const tabs = [
      { key: 'licenses', label: 'Licenses', render: () => licenses },
      { key: 'vehicles', label: 'Vehicles', count: vehicles.length, render: vehicleTable },
      { key: 'weapons', label: 'Weapons', count: weapons.length, render: weaponTable },
    ];
    if (reports) tabs.push({ key: 'reports', label: 'Reports', count: reports.length, render: reportTable });
    if (warrants) tabs.push({ key: 'warrants', label: 'Warrants', count: warrants.length, render: warrantTable });
    tabs.push({ key: 'bolos', label: 'BOLOs', count: bolos.length, render: boloList });
    tabs.push({ key: 'notes', label: 'Notes', render: () => (p.notes ? h('p', { class: 'selectable rec-pre' }, p.notes) : CAD.empty('No notes.')) });

    const activeWarrants = warrants ? warrants.filter((w) => w.status === 'active') : [];
    root.replaceChildren(
      h('div', { class: 'page-head' }, CAD.button('People', () => CAD.go('people'), { kind: 'ghost', icon: 'back', small: true }),
        h('span', { class: 'spacer' }), actions),
      activeWarrants.length ? h('div', { class: 'rec-alert' }, CAD.icon('warrant', 18),
        `${activeWarrants.length} active warrant${activeWarrants.length === 1 ? '' : 's'}: `,
        activeWarrants.map((w) => CAD.list(w.totals && w.totals.items).map((i) => i.name).join(', ')).join('; ')) : null,
      h('section', { class: 'card rec-profile' },
        R.avatar(p, 'is-large'),
        h('div', { class: 'rec-profile-main' },
          h('div', { class: 'row' }, h('h1', null, CAD.fmt.name(p)), h('span', { class: 'mono muted' }, CAD.fmt.id('person', p.id))),
          R.personBadges(s),
          h('dl', { class: 'facts rec-facts' },
            h('dt', null, 'Born'), h('dd', null, p.dob ? `${p.dob}${age !== null ? ` (${age} years)` : ''}` : '—'),
            h('dt', null, 'Gender'), h('dd', null, p.gender || '—'),
            h('dt', null, 'Address'), h('dd', { class: 'selectable' }, p.address || '—'),
            h('dt', null, 'Phone'), h('dd', { class: 'selectable' }, p.phone || '—'),
            h('dt', null, 'Height'), h('dd', null, p.height || '—'),
            h('dt', null, 'Description'), h('dd', { class: 'selectable' }, p.description || '—')))),
      h('section', { class: 'card' }, CAD.tabs(tabs)));
  };

  R.reportStatus = (status) => CAD.badge({ draft: 'Draft', submitted: 'Submitted', approved: 'Approved' }[status] || status,
    { draft: '#64748b', submitted: '#3b82f6', approved: '#22c55e' }[status]);
  R.warrantStatus = (status) => CAD.badge(status ? status[0].toUpperCase() + status.slice(1) : '',
    { requested: '#f59e0b', active: '#ef4444', served: '#22c55e', recalled: '#64748b', denied: '#64748b' }[status]);

  // ------------------------------------------------------------------ search

  const view = { query: '' };

  const search = (root, params) => {
    if (params && params.query) view.query = params.query;
    const input = CAD.input({ placeholder: 'Name, "last, first", date of birth (1991-04-12), phone or P-12', value: view.query });
    const results = h('div', { class: 'rec-results' });
    const run = CAD.run(async () => {
      view.query = input.value;
      const q = input.value.trim();
      if (!q) { results.replaceChildren(CAD.empty('Search for a person by name, date of birth or phone.')); return; }
      results.replaceChildren(CAD.loading());
      const list = CAD.list(await CAD.rpc('person.search', { query: q }));
      results.replaceChildren(list.length ? CAD.table([
        { label: 'Name', render: (s) => R.personLine(s) },
        { label: 'Age', class: 'num', render: (s) => { const a = CAD.fmt.age(s.dob); return a === null ? '—' : String(a); } },
        { label: "Driver's license", render: (s) => CAD.stateBadge('licenseStates', (s.licenses || {}).driver || 'none') },
        { label: 'Alerts', render: (s) => R.personBadges(s) },
      ], list, (s) => CAD.go('people', { id: s.id })) : CAD.empty('Nobody found.'));
    });
    input.addEventListener('input', CAD.debounce(run, 250));
    root.append(
      h('div', { class: 'page-head' }, h('h1', null, 'People'),
        h('div', { class: 'search-box' }, CAD.icon('search', 16), input),
        CAD.can('records.edit') ? CAD.button('New person', () => R.personForm({}, (saved) => CAD.go('people', { id: saved.id })),
          { kind: 'primary', icon: 'plus' }) : null),
      h('section', { class: 'card' }, results));
    run();
    setTimeout(() => input.focus(), 0);
  };

  CAD.page('people', {
    title: 'People', icon: 'people', ability: 'people.view', order: 20,
    render: (root, params) => (params && params.id ? profile(root, params.id) : search(root, params)),
  });
})();
