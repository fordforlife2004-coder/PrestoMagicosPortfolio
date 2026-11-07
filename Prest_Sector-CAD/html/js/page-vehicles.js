'use strict';
// Vehicles and weapons: search, details, editing, and running a plate for everything an officer
// should know about it (stolen, BOLOs, papers, the owner's warrants and license).

(() => {
  const { h } = CAD;
  const R = CAD.rec;

  // The alerts from a plate check, as a list.
  R.plateAlerts = (result) => {
    const alerts = CAD.list(result.alerts);
    if (!alerts.length) return h('div', { class: 'rec-clear' }, CAD.icon('check', 16), 'Nothing to report on this plate.');
    return h('ul', { class: 'rec-alerts' }, alerts.map((a) => h('li', { class: `rec-alert-item is-${a.tone}` },
      CAD.icon(a.tone === 'error' ? 'panic' : 'bolo', 15), a.text)));
  };

  const runPlate = CAD.run(async (plate) => {
    const result = await CAD.rpc('plate.check', { plate });
    CAD.modal({
      title: `Plate ${result.plate}`,
      body: h('div', { class: 'stack' },
        result.vehicle ? h('div', { class: 'row' }, R.plate(result.vehicle.plate),
          h('span', null, [result.vehicle.color, result.vehicle.model].filter(Boolean).join(' ')), h('span', { class: 'spacer' }),
          R.link('Open vehicle', 'vehicles', { id: result.vehicle.id })) : null,
        result.owner ? h('div', { class: 'row' }, R.personLine(result.owner), h('span', { class: 'spacer' }),
          R.link('Open owner', 'people', { id: result.owner.id })) : null,
        R.plateAlerts(result)),
    });
  });

  // ------------------------------------------------------------------ forms

  const ownerPicker = (ownerId, ownerName) => {
    let id = ownerId || null;
    const label = h('span', null, ownerName || 'No owner');
    const node = h('div', { class: 'row rec-owner-pick' }, label, h('span', { class: 'spacer' }),
      CAD.button('Pick', CAD.run(async () => {
        const s = await CAD.pick.person();
        if (s) { id = s.id; label.textContent = CAD.fmt.name(s); }
      }), { small: true, icon: 'search' }),
      CAD.button('Clear', () => { id = null; label.textContent = 'No owner'; }, { small: true, kind: 'ghost' }));
    return { node, value: () => id };
  };

  const checks = (list, chosen) => {
    const boxes = {};
    const node = h('div', { class: 'row rec-flag-picks' }, CAD.list(CAD.state.config[list]).map((f) => {
      boxes[f.key] = h('input', { type: 'checkbox', checked: CAD.list(chosen).includes(f.key) });
      return h('label', { class: 'check' }, boxes[f.key], f.label);
    }));
    return { node, value: () => Object.keys(boxes).filter((k) => boxes[k].checked) };
  };

  const vehicleForm = (v, after) => {
    const isNew = !v.id;
    const f = {
      plate: CAD.input({ value: v.plate || '', maxlength: 10, class: 'input mono' }),
      model: CAD.input({ value: v.model || '', maxlength: 30 }),
      color: CAD.input({ value: v.color || '', maxlength: 20 }),
      registration: CAD.select(CAD.options('registrationStates'), v.registration || 'valid'),
      insurance: CAD.select(CAD.options('insuranceStates'), v.insurance || 'valid'),
      notes: CAD.textarea({ value: v.notes || '', maxlength: 1000, rows: 3 }),
    };
    const owner = ownerPicker(v.ownerId, v.ownerName);
    const flags = checks('vehicleFlags', v.flags);
    CAD.modal({
      title: isNew ? 'New vehicle' : `Edit ${v.plate}`, wide: true,
      body: h('div', { class: 'form' },
        h('div', { class: 'form-grid' }, CAD.field('Plate', f.plate), CAD.field('Model', f.model), CAD.field('Colour', f.color),
          CAD.field('Owner', owner.node), CAD.field('Registration', f.registration), CAD.field('Insurance', f.insurance)),
        CAD.field('Flags', flags.node), CAD.field('Notes', f.notes)),
      actions: [{ label: 'Cancel' }, {
        label: isNew ? 'Create' : 'Save', kind: 'primary',
        onClick: async () => {
          const saved = await CAD.rpc('vehicle.save', { vehicle: {
            id: v.id, plate: f.plate.value, model: f.model.value, color: f.color.value, ownerId: owner.value(),
            registration: f.registration.value, insurance: f.insurance.value, flags: flags.value(), notes: f.notes.value,
          } });
          CAD.toast(isNew ? 'Vehicle added.' : 'Saved.', 'success');
          after(saved);
        },
      }],
    });
  };

  const weaponForm = (w, after) => {
    const isNew = !w.id;
    const f = {
      serial: CAD.input({ value: w.serial || '', maxlength: 20, class: 'input mono' }),
      kind: CAD.input({ value: w.kind || '', maxlength: 30 }),
      status: CAD.select(CAD.options('weaponStates'), w.status || 'registered'),
      notes: CAD.textarea({ value: w.notes || '', maxlength: 1000, rows: 3 }),
    };
    const owner = ownerPicker(w.ownerId, w.ownerName);
    CAD.modal({
      title: isNew ? 'New weapon' : `Edit ${w.serial}`,
      body: h('div', { class: 'form' }, h('div', { class: 'form-grid' }, CAD.field('Serial number', f.serial), CAD.field('Weapon', f.kind),
        CAD.field('Status', f.status), CAD.field('Owner', owner.node)), CAD.field('Notes', f.notes)),
      actions: [{ label: 'Cancel' }, {
        label: isNew ? 'Create' : 'Save', kind: 'primary',
        onClick: async () => {
          const saved = await CAD.rpc('weapon.save', { weapon: { id: w.id, serial: f.serial.value, kind: f.kind.value, status: f.status.value,
            ownerId: owner.value(), notes: f.notes.value } });
          CAD.toast(isNew ? 'Weapon added.' : 'Saved.', 'success');
          after(saved);
        },
      }],
    });
  };

  // ------------------------------------------------------------------ details

  const deleteButton = (kind, id, label, page) => (CAD.can('records.delete') ? CAD.button('', CAD.run(async () => {
    if (!(await CAD.confirm(`Delete ${label}?`, 'This removes it from the records.', 'Delete'))) return;
    await CAD.rpc(`${kind}.delete`, { id });
    CAD.toast('Deleted.', 'info');
    CAD.go(page);
  }), { kind: 'ghost', icon: 'trash', title: 'Delete' }) : null);

  const vehicleDetail = async (root, id) => {
    root.replaceChildren(CAD.loading());
    const data = await CAD.rpc('vehicle.get', { id });
    const v = data.vehicle;
    const again = () => vehicleDetail(root, id);
    root.replaceChildren(
      h('div', { class: 'page-head' }, CAD.button('Vehicles', () => CAD.go('vehicles'), { kind: 'ghost', icon: 'back', small: true }),
        h('span', { class: 'spacer' }),
        CAD.button('Run plate', () => runPlate(v.plate), { icon: 'search' }),
        CAD.can('bolos.edit') ? CAD.button('Add BOLO', () => CAD.go('bolos', { new: true, kind: 'vehicle', plate: v.plate }), { icon: 'bolo' }) : null,
        CAD.can('records.edit') ? CAD.button('Edit', () => vehicleForm(v, again), { icon: 'edit' }) : null,
        deleteButton('vehicle', v.id, v.plate, 'vehicles')),
      h('div', { class: 'grid-2' },
        h('section', { class: 'card' },
          h('div', { class: 'rec-vehicle-head' }, h('span', { class: 'plate-box is-large' }, v.plate),
            h('div', null, h('h1', null, [v.color, v.model].filter(Boolean).join(' ') || 'Unknown vehicle'),
              h('span', { class: 'mono muted' }, CAD.fmt.id('vehicle', v.id)))),
          h('div', { class: 'badges', style: { margin: '10px 0' } }, R.flags('vehicleFlags', v.flags)),
          h('dl', { class: 'facts' },
            h('dt', null, 'Registration'), h('dd', null, CAD.stateBadge('registrationStates', v.registration)),
            h('dt', null, 'Insurance'), h('dd', null, CAD.stateBadge('insuranceStates', v.insurance)),
            h('dt', null, 'Notes'), h('dd', { class: 'selectable rec-pre' }, v.notes || '—'),
            h('dt', null, 'Updated'), h('dd', null, CAD.fmt.dateTime(v.updatedAt)))),
        h('section', { class: 'card' }, h('div', { class: 'card-head' }, h('h2', null, 'Registered owner')),
          data.owner ? h('div', { class: 'stack' }, h('div', { class: 'row' }, R.personLine(data.owner), h('span', { class: 'spacer' }),
            R.link('Open profile', 'people', { id: data.owner.id })), R.personBadges(data.owner),
          h('div', { class: 'row' }, h('span', { class: 'muted' }, "Driver's license"), CAD.stateBadge('licenseStates', (data.owner.licenses || {}).driver || 'none')))
            : CAD.empty('No registered owner.'))),
      CAD.list(data.bolos).length ? h('section', { class: 'card' }, h('div', { class: 'card-head' }, h('h2', null, 'Active BOLOs')),
        CAD.list(data.bolos).map((b) => h('div', { class: 'rec-bolo-line' }, CAD.badge('BOLO', '#f97316'), h('b', null, b.title),
          h('span', { class: 'muted' }, b.description)))) : null);
  };

  const weaponDetail = async (root, id) => {
    root.replaceChildren(CAD.loading());
    const data = await CAD.rpc('weapon.get', { id });
    const w = data.weapon;
    root.replaceChildren(
      h('div', { class: 'page-head' }, CAD.button('Weapons', () => CAD.go('weapons'), { kind: 'ghost', icon: 'back', small: true }),
        h('span', { class: 'spacer' }),
        CAD.can('records.edit') ? CAD.button('Edit', () => weaponForm(w, () => weaponDetail(root, id)), { icon: 'edit' }) : null,
        deleteButton('weapon', w.id, w.serial, 'weapons')),
      h('div', { class: 'grid-2' },
        h('section', { class: 'card' }, h('div', { class: 'row' }, h('h1', { class: 'mono' }, w.serial), CAD.stateBadge('weaponStates', w.status)),
          h('dl', { class: 'facts', style: { marginTop: '12px' } },
            h('dt', null, 'Weapon'), h('dd', null, w.kind),
            h('dt', null, 'Notes'), h('dd', { class: 'selectable rec-pre' }, w.notes || '—'),
            h('dt', null, 'Updated'), h('dd', null, CAD.fmt.dateTime(w.updatedAt)))),
        h('section', { class: 'card' }, h('div', { class: 'card-head' }, h('h2', null, 'Registered owner')),
          data.owner ? h('div', { class: 'stack' }, h('div', { class: 'row' }, R.personLine(data.owner), h('span', { class: 'spacer' }),
            R.link('Open profile', 'people', { id: data.owner.id })), R.personBadges(data.owner)) : CAD.empty('No registered owner.'))));
  };

  // ------------------------------------------------------------------ search pages

  const searchPage = (kind, title, placeholder, columns, form, extra) => {
    const view = { query: '' };
    return (root, params) => {
      if (params && params.query) view.query = params.query;
      const input = CAD.input({ placeholder, value: view.query });
      const results = h('div');
      const run = CAD.run(async () => {
        view.query = input.value;
        const q = input.value.trim();
        if (!q) { results.replaceChildren(CAD.empty(`Search ${title.toLowerCase()} by ${placeholder.toLowerCase()}.`)); return; }
        results.replaceChildren(CAD.loading());
        const list = CAD.list(await CAD.rpc(`${kind}.search`, { query: q }));
        results.replaceChildren(list.length ? CAD.table(columns, list, (row) => CAD.go(`${kind}s`, { id: row.id })) : CAD.empty('Nothing found.'));
      });
      input.addEventListener('input', CAD.debounce(run, 250));
      root.append(
        h('div', { class: 'page-head' }, h('h1', null, title), h('div', { class: 'search-box' }, CAD.icon('search', 16), input),
          extra ? extra(input) : null,
          CAD.can('records.edit') ? CAD.button(`New ${kind}`, () => form({}, (saved) => CAD.go(`${kind}s`, { id: saved.id })), { kind: 'primary', icon: 'plus' }) : null),
        h('section', { class: 'card' }, results));
      run();
      setTimeout(() => input.focus(), 0);
    };
  };

  const vehicleSearch = searchPage('vehicle', 'Vehicles', 'Plate, model or owner', [
    { label: 'Plate', render: (v) => R.plate(v.plate) },
    { label: 'Vehicle', render: (v) => [v.color, v.model].filter(Boolean).join(' ') || '—' },
    { label: 'Owner', render: (v) => v.ownerName || h('span', { class: 'muted' }, 'No owner') },
    { label: 'Papers', render: (v) => h('div', { class: 'badges' }, CAD.stateBadge('registrationStates', v.registration), CAD.stateBadge('insuranceStates', v.insurance)) },
    { label: 'Flags', render: (v) => h('div', { class: 'badges' }, R.flags('vehicleFlags', v.flags)) },
  ], vehicleForm, (input) => CAD.button('Run plate', () => { if (input.value.trim()) runPlate(input.value.trim()); else CAD.toast('Type a plate first.', 'warning'); }, { icon: 'search' }));

  const weaponSearch = searchPage('weapon', 'Weapons', 'Serial, weapon or owner', [
    { label: 'Serial', render: (w) => h('span', { class: 'mono' }, w.serial) },
    { label: 'Weapon', render: (w) => w.kind },
    { label: 'Owner', render: (w) => w.ownerName || h('span', { class: 'muted' }, 'No owner') },
    { label: 'Status', render: (w) => CAD.stateBadge('weaponStates', w.status) },
  ], weaponForm);

  CAD.page('vehicles', {
    title: 'Vehicles', icon: 'car', ability: 'people.view', order: 30,
    render: (root, params) => (params && params.id ? vehicleDetail(root, params.id) : vehicleSearch(root, params)),
  });
  CAD.page('weapons', {
    title: 'Weapons', icon: 'gun', ability: 'people.view', order: 35,
    render: (root, params) => (params && params.id ? weaponDetail(root, params.id) : weaponSearch(root, params)),
  });
})();
