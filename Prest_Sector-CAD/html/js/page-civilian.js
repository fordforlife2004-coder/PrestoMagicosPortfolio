'use strict';
// "My records" for every player: their characters, each character's vehicles and weapons, and the
// citations and arrests on file for them. Police see these when they run a name or a plate.

(() => {
  const { h } = CAD;

  const initials = (p) => `${(p.first || '?')[0]}${(p.last || '')[0] || ''}`.toUpperCase();
  const avatar = (p) => h('div', { class: 'civ-avatar' },
    p.mugshot ? h('img', { src: p.mugshot, alt: '', referrerpolicy: 'no-referrer', onError: (e) => e.target.remove() }) : null,
    p.mugshot ? null : initials(p));

  // ------------------------------------------------------------------ forms

  const personForm = (p, after) => {
    const isNew = !p.id;
    const f = {
      first: CAD.input({ value: p.first || '', maxlength: 30 }),
      last: CAD.input({ value: p.last || '', maxlength: 30 }),
      dob: CAD.input({ type: 'date', value: p.dob || '', min: '1900-01-01' }),
      gender: CAD.select(CAD.list(CAD.state.config.genders), p.gender || CAD.list(CAD.state.config.genders)[0]),
      address: CAD.input({ value: p.address || '', maxlength: 80 }),
      phone: CAD.input({ value: p.phone || '', maxlength: 20 }),
      height: CAD.input({ value: p.height || '', maxlength: 10, placeholder: `e.g. 5'11"` }),
      description: CAD.textarea({ value: p.description || '', maxlength: 300, rows: 2, placeholder: 'Hair, eyes, build, tattoos' }),
      mugshot: CAD.input({ value: p.mugshot || '', maxlength: 300, placeholder: 'https://… (optional)' }),
    };
    const licenses = {};
    const licenseFields = CAD.list(CAD.state.config.licenses).map((l) => {
      licenses[l.key] = h('input', { type: 'checkbox', checked: (p.licenses || {})[l.key] === 'valid' });
      return h('label', { class: 'check' }, licenses[l.key], l.label);
    });
    CAD.modal({
      title: isNew ? 'New character' : `Edit ${CAD.fmt.name(p)}`,
      wide: true,
      body: h('div', { class: 'form' },
        h('div', { class: 'form-grid' },
          CAD.field('First name', f.first), CAD.field('Last name', f.last),
          CAD.field('Date of birth', f.dob), CAD.field('Gender', f.gender),
          CAD.field('Address', f.address), CAD.field('Phone', f.phone),
          CAD.field('Height', f.height), CAD.field('Photo', f.mugshot, 'A link to a picture of your character'),
          h('div', { class: 'wide' }, CAD.field('What they look like', f.description))),
        isNew ? h('div', { class: 'field' }, h('span', { class: 'field-label' }, 'Licenses you hold'),
          h('div', { class: 'civ-license-picks row' }, licenseFields),
          h('span', { class: 'field-hint' }, 'You pick these once. After that, only the police can suspend or revoke them.')) : null),
      actions: [{ label: 'Cancel' }, {
        label: isNew ? 'Create character' : 'Save', kind: 'primary',
        onClick: async () => {
          const person = { id: p.id, first: f.first.value, last: f.last.value, dob: f.dob.value, gender: f.gender.value, address: f.address.value,
            phone: f.phone.value, height: f.height.value, description: f.description.value, mugshot: f.mugshot.value };
          if (isNew) {
            person.licenses = {};
            Object.entries(licenses).forEach(([key, box]) => { person.licenses[key] = box.checked ? 'valid' : 'none'; });
          }
          await CAD.rpc('civ.savePerson', { person });
          CAD.toast(isNew ? 'Character created.' : 'Saved.', 'success');
          after();
        },
      }],
    });
  };

  const vehicleForm = (v, owners, after) => {
    const isNew = !v.id;
    const f = {
      owner: CAD.select(owners.map((p) => ({ value: p.id, label: CAD.fmt.name(p) })), v.ownerId),
      plate: CAD.input({ value: v.plate || '', maxlength: 10, class: 'input mono', placeholder: 'e.g. 46EEK572' }),
      model: CAD.input({ value: v.model || '', maxlength: 30, placeholder: 'e.g. Karin Sultan' }),
      color: CAD.input({ value: v.color || '', maxlength: 20, placeholder: 'e.g. Silver' }),
      registration: h('input', { type: 'checkbox', checked: v.registration !== 'none' }),
      insurance: h('input', { type: 'checkbox', checked: v.insurance !== 'none' }),
    };
    CAD.modal({
      title: isNew ? 'Register a vehicle' : `Edit ${v.plate}`,
      body: h('div', { class: 'form' },
        CAD.field('Owner', f.owner), CAD.field('Plate', f.plate, 'Up to 8 letters and numbers'),
        h('div', { class: 'form-grid' }, CAD.field('Model', f.model), CAD.field('Colour', f.color)),
        isNew ? h('div', { class: 'row' }, h('label', { class: 'check' }, f.registration, 'Registered'),
          h('label', { class: 'check' }, f.insurance, 'Insured')) : null),
      actions: [{ label: 'Cancel' }, {
        label: isNew ? 'Register' : 'Save', kind: 'primary',
        onClick: async () => {
          await CAD.rpc('civ.saveVehicle', { vehicle: {
            id: v.id, ownerId: Number(f.owner.value), plate: f.plate.value, model: f.model.value, color: f.color.value,
            registration: f.registration.checked ? 'valid' : 'none', insurance: f.insurance.checked ? 'valid' : 'none',
          } });
          CAD.toast(isNew ? 'Vehicle registered.' : 'Saved.', 'success');
          after();
        },
      }],
    });
  };

  const weaponForm = (w, owners, after) => {
    const isNew = !w.id;
    const f = {
      owner: CAD.select(owners.map((p) => ({ value: p.id, label: CAD.fmt.name(p) })), w.ownerId),
      serial: CAD.input({ value: w.serial || '', maxlength: 20, class: 'input mono', placeholder: 'e.g. GLK-44817' }),
      kind: CAD.input({ value: w.kind || '', maxlength: 30, placeholder: 'e.g. Pistol' }),
    };
    CAD.modal({
      title: isNew ? 'Register a weapon' : `Edit ${w.serial}`,
      body: h('div', { class: 'form' }, CAD.field('Owner', f.owner), CAD.field('Serial number', f.serial), CAD.field('Weapon', f.kind)),
      actions: [{ label: 'Cancel' }, {
        label: isNew ? 'Register' : 'Save', kind: 'primary',
        onClick: async () => {
          await CAD.rpc('civ.saveWeapon', { weapon: { id: w.id, ownerId: Number(f.owner.value), serial: f.serial.value, kind: f.kind.value } });
          CAD.toast(isNew ? 'Weapon registered.' : 'Saved.', 'success');
          after();
        },
      }],
    });
  };

  // ------------------------------------------------------------------ the page

  const render = async (root) => {
    root.replaceChildren(CAD.loading());
    const data = await CAD.rpc('civ.list');
    const persons = CAD.list(data.persons);
    const vehicles = CAD.list(data.vehicles);
    const weapons = CAD.list(data.weapons);
    const citations = CAD.list(data.citations);
    const limits = CAD.state.config.civilian || { maxCharacters: 5, maxVehicles: 10, maxWeapons: 10 };
    const again = () => render(root);

    const confirmDelete = (title, text, action, payload) => CAD.run(async () => {
      if (!(await CAD.confirm(title, text, 'Delete'))) return;
      await CAD.rpc(action, payload);
      CAD.toast('Deleted.', 'info');
      again();
    });

    const vehicleItem = (v) => {
      const stolen = CAD.list(v.flags).includes('stolen');
      return h('div', { class: 'civ-item' },
        h('div', { class: 'row' }, h('span', { class: 'plate-box' }, v.plate), h('span', null, [v.color, v.model].filter(Boolean).join(' ')),
          h('span', { class: 'spacer' }), stolen ? CAD.badge('Stolen', '#ef4444') : null),
        h('div', { class: 'row' }, CAD.stateBadge('registrationStates', v.registration), CAD.stateBadge('insuranceStates', v.insurance),
          CAD.list(v.flags).filter((f) => f !== 'stolen').map((f) => CAD.stateBadge('vehicleFlags', f))),
        h('div', { class: 'row' },
          CAD.button('Edit', () => vehicleForm(v, persons, again), { small: true, icon: 'edit' }),
          CAD.button(stolen ? 'Found it' : 'Report stolen', CAD.run(async () => {
            await CAD.rpc('civ.reportStolen', { vehicleId: v.id, stolen: !stolen });
            CAD.toast(stolen ? 'Marked as recovered.' : 'Reported stolen. Police running the plate will see it.', stolen ? 'success' : 'warning');
            again();
          }), { small: true, kind: stolen ? undefined : 'danger' }),
          h('span', { class: 'spacer' }),
          CAD.button('', confirmDelete(`Delete ${v.plate}?`, 'The vehicle is removed from your records.', 'civ.deleteVehicle', { id: v.id }),
            { small: true, kind: 'ghost', icon: 'trash', title: 'Delete' })));
    };

    const weaponItem = (w) => {
      const seized = w.status === 'seized';
      return h('div', { class: 'civ-item' },
        h('div', { class: 'row' }, h('span', { class: 'mono' }, w.serial), h('span', null, w.kind), h('span', { class: 'spacer' }),
          CAD.stateBadge('weaponStates', w.status)),
        seized ? h('p', { class: 'muted' }, 'Seized by the police.') : h('div', { class: 'row' },
          CAD.button('Edit', () => weaponForm(w, persons, again), { small: true, icon: 'edit' }),
          CAD.button(w.status === 'stolen' ? 'Found it' : 'Report stolen', CAD.run(async () => {
            await CAD.rpc('civ.reportStolen', { weaponId: w.id, stolen: w.status !== 'stolen' });
            again();
          }), { small: true }),
          h('span', { class: 'spacer' }),
          CAD.button('', confirmDelete(`Delete ${w.serial}?`, 'The weapon is removed from your records.', 'civ.deleteWeapon', { id: w.id }),
            { small: true, kind: 'ghost', icon: 'trash', title: 'Delete' })));
    };

    const personCard = (p) => {
      const mineV = vehicles.filter((v) => v.ownerId === p.id);
      const mineW = weapons.filter((w) => w.ownerId === p.id);
      const age = CAD.fmt.age(p.dob);
      return h('section', { class: 'card' },
        h('div', { class: 'civ-person-head' }, avatar(p),
          h('div', null, h('h2', null, CAD.fmt.name(p)),
            h('div', { class: 'sub' }, [p.dob ? `Born ${p.dob}${age !== null ? ` (${age})` : ''}` : '', p.gender, p.address, p.phone].filter(Boolean).join(' · '))),
          h('span', { class: 'spacer' }),
          CAD.button('Edit', () => personForm(p, again), { small: true, icon: 'edit' }),
          CAD.button('', confirmDelete(`Delete ${CAD.fmt.name(p)}?`, 'Their vehicles and weapons are deleted too.', 'civ.deletePerson', { id: p.id }),
            { small: true, kind: 'ghost', icon: 'trash', title: 'Delete character' })),
        h('div', { class: 'civ-licenses' }, CAD.list(CAD.state.config.licenses).map((l) => h('span', { class: 'civ-license' }, l.label,
          CAD.stateBadge('licenseStates', (p.licenses || {})[l.key] || 'none')))),
        h('div', { class: 'civ-section' },
          h('h3', null, `Vehicles ${mineV.length}/${limits.maxVehicles}`, h('span', { class: 'spacer' }),
            mineV.length < limits.maxVehicles ? CAD.button('Register vehicle', () => vehicleForm({ ownerId: p.id }, persons, again), { small: true, icon: 'plus' }) : null),
          mineV.length ? h('div', { class: 'civ-items' }, mineV.map(vehicleItem)) : CAD.empty('No vehicles registered.')),
        h('div', { class: 'civ-section' },
          h('h3', null, `Weapons ${mineW.length}/${limits.maxWeapons}`, h('span', { class: 'spacer' }),
            mineW.length < limits.maxWeapons ? CAD.button('Register weapon', () => weaponForm({ ownerId: p.id }, persons, again), { small: true, icon: 'plus' }) : null),
          mineW.length ? h('div', { class: 'civ-items' }, mineW.map(weaponItem)) : CAD.empty('No weapons registered.')));
    };

    const nameOf = (id) => { const p = persons.find((x) => x.id === id); return p ? CAD.fmt.name(p) : ''; };
    const fines = citations.reduce((sum, c) => sum + ((c.totals && c.totals.fine) || 0), 0);
    root.replaceChildren(
      h('div', { class: 'page-head' },
        h('div', null, h('h1', null, 'My records'),
          h('div', { class: 'sub' }, 'Your characters, and the vehicles and weapons registered to them. Police see these when they run a name or plate.')),
        h('span', { class: 'spacer' }),
        h('span', { class: 'muted' }, `Characters ${persons.length}/${limits.maxCharacters}`),
        persons.length < limits.maxCharacters ? CAD.button('New character', () => personForm({}, again), { kind: 'primary', icon: 'plus' }) : null),
      persons.length ? h('div', { class: 'civ-people' }, persons.map(personCard))
        : h('div', { class: 'empty' }, h('p', null, "You don't have a character yet."), h('p', null, 'Make one to register vehicles and weapons.'),
          h('div', { style: { marginTop: '12px' } }, CAD.button('New character', () => personForm({}, again), { kind: 'primary', icon: 'plus' }))),
      citations.length ? h('section', { class: 'card', style: { marginTop: '14px' } },
        h('div', { class: 'card-head' }, h('h2', null, 'Citations and arrests'), h('span', { class: 'spacer' }),
          h('span', { class: 'muted' }, `Fines on file: ${CAD.fmt.money(fines)}`)),
        CAD.table([
          { label: 'Date', render: (c) => CAD.fmt.date(c.createdAt) },
          { label: 'Who', render: (c) => nameOf(c.personId) },
          { label: 'What', render: (c) => h('span', null, CAD.badge(c.type === 'arrest' ? 'Arrest' : 'Citation', c.type === 'arrest' ? '#ef4444' : '#f59e0b'), ' ', c.title) },
          { label: 'Fine', class: 'num', render: (c) => CAD.fmt.money(c.totals && c.totals.fine) },
          { label: 'Jail', class: 'num', render: (c) => (c.totals && c.totals.jail ? CAD.fmt.months(c.totals.jail) : '—') },
        ], citations)) : null);
  };

  CAD.page('civilian', { title: 'My records', icon: 'civilian', ability: null, order: 90, render });
})();
