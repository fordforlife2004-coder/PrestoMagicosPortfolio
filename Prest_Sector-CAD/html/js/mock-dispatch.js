'use strict';
// Browser preview only: answers the call and civilian requests the way the server does, from the
// made-up data in mock.js. Add &live=1 to the address to get a made-up 911 call every 40 seconds.

(() => {
  if (CAD.inGame) return;
  const M = CAD.mock;
  const S = M.state;

  const findCall = (id) => S.calls.find((c) => c.id === Number(id)) || S.closedCalls.find((c) => c.id === Number(id))
    || S.fail('That call could not be found.');
  const openCall = (id) => { const c = findCall(id); if (c.status === 'closed') S.fail('That call is closed.'); return c; };
  const by = () => (S.myUnit() ? S.myUnit().callsign : S.me.name);
  const note = (call, text, system = true) => { call.notes.push({ at: S.now(), by: by(), text, system }); call.updatedAt = S.now(); };
  const pushCall = (call) => setTimeout(() => CAD.push('call', call), 0);
  const pushUnits = () => setTimeout(() => CAD.push('units', S.units), 0);
  const pushMe = () => setTimeout(() => CAD.push('me', S.meNow()), 0);
  const canWork = (call) => S.can('dispatch.manage') || (S.myUnit() && call.units.includes(S.me.id));
  const unitFor = (id) => {
    if (id === undefined || id === S.me.id) return S.myUnit() || S.fail("You aren't on duty.");
    S.need('dispatch.manage');
    return S.units.find((u) => u.id === Number(id)) || S.fail('That unit is not on duty.');
  };

  const detach = (call, unit) => {
    call.units = call.units.filter((id) => id !== unit.id);
    if (call.primary === unit.id) call.primary = call.units[0] || null;
    if (!call.units.length && call.status === 'active') call.status = 'pending';
    if (unit.callId === call.id) { unit.callId = null; unit.status = 'available'; unit.since = S.now(); }
  };
  const attach = (call, unit) => {
    if (unit.callId && unit.callId !== call.id) {
      const old = S.calls.find((c) => c.id === unit.callId);
      if (old) { detach(old, unit); note(old, `${unit.callsign} left the call.`); pushCall(old); }
    }
    if (call.units.includes(unit.id)) return;
    call.units.push(unit.id);
    call.primary = call.primary || unit.id;
    if (call.status === 'pending') call.status = 'active';
    unit.callId = call.id;
    unit.status = 'enroute';
    unit.since = S.now();
    note(call, `${unit.callsign} attached.`);
  };

  const sorted = (list) => [...list].sort((a, b) => (a.priority - b.priority) || (a.createdAt - b.createdAt));

  M.on('call.list', (p) => {
    S.need('dispatch.view');
    const open = sorted(S.calls);
    return p.closed ? open.concat([...S.closedCalls].sort((a, b) => b.closedAt - a.closedAt)) : open;
  });
  M.on('call.get', (p) => { S.need('dispatch.view'); return findCall(p.id); });

  M.on('call.create', (p) => {
    S.need('calls.create');
    const code = S.config.callCodes.find((c) => c.code === p.code) || S.fail('Pick a call type.');
    const unit = S.myUnit();
    let location = null;
    if (p.useMyLocation) location = { ...(unit && unit.location ? unit.location : { x: 430, y: -980, z: 30, street: '' }) };
    else if (p.location && p.location.street && p.location.street.trim()) location = { street: p.location.street.trim().slice(0, 80) };
    const dispatcher = !unit || unit.role === 'dispatch';
    const call = {
      id: S.nextId('call'), title: (p.title || '').trim().slice(0, 80) || code.label, code: code.code,
      priority: p.priority || code.priority, service: p.service || code.service, status: 'pending',
      description: (p.description || '').trim().slice(0, 2000), location, caller: null, units: [], primary: null,
      notes: [], disposition: null, source: dispatcher ? 'dispatch' : 'unit', createdAt: S.now(), updatedAt: S.now(), closedAt: null,
    };
    note(call, `Call created by ${by()}.`);
    S.calls.push(call);
    if (!dispatcher) { attach(call, unit); pushUnits(); pushMe(); }
    return call;
  });

  M.on('call.update', (p) => {
    const call = openCall(p.id);
    if (!canWork(call)) S.fail('Only units on the call or dispatch can change it.');
    if (!String(p.title || '').trim()) S.fail('Enter a title.');
    const changed = [];
    const set = (field, value, label) => { if (value !== undefined && value !== call[field]) { call[field] = value; changed.push(label); } };
    set('title', String(p.title).trim().slice(0, 80), 'title');
    set('code', p.code, 'type');
    set('priority', Number(p.priority), 'priority');
    set('service', p.service, 'service');
    set('description', String(p.description || '').trim().slice(0, 2000), 'description');
    if (changed.length) note(call, `${by()} changed the ${changed.join(', ')}.`);
    return call;
  });

  M.on('call.attach', (p) => {
    const call = openCall(p.id);
    const unit = unitFor(p.unit);
    attach(call, unit);
    pushUnits();
    if (unit.id === S.me.id) pushMe();
    return call;
  });

  M.on('call.detach', (p) => {
    const call = openCall(p.id);
    const unit = unitFor(p.unit);
    if (!call.units.includes(unit.id)) S.fail('That unit is not on this call.');
    detach(call, unit);
    note(call, `${unit.callsign} left the call.`);
    pushUnits();
    if (unit.id === S.me.id) pushMe();
    return call;
  });

  M.on('call.note', (p) => {
    const call = findCall(p.id);
    if (!canWork(call)) S.fail('Only units on the call or dispatch can add notes.');
    const text = String(p.text || '').trim().slice(0, 500);
    if (!text) S.fail('Write the note first.');
    note(call, text, false);
    return call;
  });

  M.on('call.close', (p) => {
    const call = openCall(p.id);
    const unit = S.myUnit();
    if (!S.can('dispatch.manage') && !(unit && call.primary === unit.id)) S.fail('Only dispatch or the primary unit can close a call.');
    if (!S.config.dispositions.includes(p.disposition)) S.fail('Pick how the call ended.');
    call.units.forEach((id) => { const u = S.units.find((x) => x.id === id); if (u) { u.callId = null; u.status = 'available'; u.since = S.now(); } });
    call.units = [];
    call.primary = null;
    call.status = 'closed';
    call.disposition = p.disposition;
    call.closedAt = S.now();
    note(call, `Closed: ${p.disposition}.`);
    S.calls = S.calls.filter((c) => c.id !== call.id);
    S.closedCalls.unshift(call);
    pushUnits();
    pushMe();
    return call;
  });

  M.on('call.reopen', (p) => {
    S.need('dispatch.manage');
    const call = findCall(p.id);
    if (call.status !== 'closed') S.fail('That call is already open.');
    call.status = 'pending';
    call.closedAt = null;
    call.disposition = null;
    note(call, `Reopened by ${by()}.`);
    S.closedCalls = S.closedCalls.filter((c) => c.id !== call.id);
    S.calls.push(call);
    return call;
  });

  // ------------------------------------------------------------------ civilians

  const mine = () => S.persons.filter((p) => p.owner === S.myLicense);
  const myPerson = (id) => {
    const p = S.persons.find((x) => x.id === Number(id));
    if (!p || p.owner !== S.myLicense) S.fail('That is not one of your characters.');
    return p;
  };
  const myRecord = (list, id, what) => {
    const r = list.find((x) => x.id === Number(id));
    if (!r || r.owner !== S.myLicense) S.fail(`That is not your ${what}.`);
    return r;
  };
  const name = (v, what) => {
    const t = String(v || '').trim();
    if (!t) S.fail(`Enter ${what}.`);
    if (!/^[\p{L}][\p{L} '.-]*$/u.test(t)) S.fail(`${what[0].toUpperCase()}${what.slice(1)} can only have letters, spaces, apostrophes and dashes.`);
    return t.slice(0, 30);
  };
  const identity = (input, into) => {
    into.first = name(input.first, 'a first name');
    into.last = name(input.last, 'a last name');
    if (!/^\d{4}-\d{2}-\d{2}$/.test(input.dob || '')) S.fail('Enter the date of birth as YYYY-MM-DD.');
    into.dob = input.dob;
    if (!S.config.genders.includes(input.gender)) S.fail('Pick a gender.');
    into.gender = input.gender;
    ['address', 'phone', 'height', 'description'].forEach((f) => { into[f] = String(input[f] || '').trim(); });
    const url = String(input.mugshot || '').trim();
    if (url && !/^https?:\/\/[^\s"'<>]+$/.test(url)) S.fail('The photo must be a web address starting with http:// or https://.');
    into.mugshot = url;
    return into;
  };
  const plateKey = (plate) => { const k = String(plate || '').toUpperCase().replace(/[^A-Z0-9]/g, ''); return k.length >= 1 && k.length <= 8 ? k : null; };

  M.on('civ.list', () => {
    const persons = mine();
    const ids = persons.map((p) => p.id);
    const citations = [];
    S.reports.filter((r) => ['citation', 'arrest'].includes(r.type) && ['submitted', 'approved'].includes(r.status)).forEach((r) => {
      r.persons.filter((id) => ids.includes(id)).forEach((personId) => citations.push({
        reportId: r.id, type: r.type, title: r.title, createdAt: r.createdAt, totals: r.totals, personId,
      }));
    });
    return {
      persons,
      vehicles: S.vehicles.filter((v) => ids.includes(v.ownerId)).map(S.withOwner),
      weapons: S.weapons.filter((w) => ids.includes(w.ownerId)).map(S.withOwner),
      citations,
    };
  });

  M.on('civ.savePerson', ({ person }) => {
    const old = person.id ? myPerson(person.id) : null;
    if (!old && mine().length >= S.config.civilian.maxCharacters) S.fail(`You can keep up to ${S.config.civilian.maxCharacters} characters.`);
    const p = old || {};
    identity(person, p);
    if (!old) {
      const licenses = {};
      S.config.licenses.forEach((l) => {
        const state = (person.licenses || {})[l.key] || 'none';
        if (!['valid', 'none'].includes(state)) S.fail(`${l.label} can only be valid or none.`);
        licenses[l.key] = state;
      });
      Object.assign(p, { id: S.nextId('person'), licenses, flags: [], notes: '', owner: S.myLicense, createdAt: S.now() });
      S.persons.push(p);
    }
    p.updatedAt = S.now();
    return p;
  });

  M.on('civ.deletePerson', ({ id }) => {
    const p = myPerson(id);
    S.vehicles = S.vehicles.filter((v) => !(v.ownerId === p.id && v.owner === S.myLicense));
    S.weapons = S.weapons.filter((w) => !(w.ownerId === p.id && w.owner === S.myLicense));
    S.persons = S.persons.filter((x) => x.id !== p.id);
    return true;
  });

  M.on('civ.saveVehicle', ({ vehicle }) => {
    const old = vehicle.id ? myRecord(S.vehicles, vehicle.id, 'vehicle') : null;
    const owner = myPerson(vehicle.ownerId);
    const count = S.vehicles.filter((v) => v.ownerId === owner.id).length;
    if ((!old || old.ownerId !== owner.id) && count >= S.config.civilian.maxVehicles) S.fail(`Each character can register up to ${S.config.civilian.maxVehicles} vehicles.`);
    const key = plateKey(vehicle.plate) || S.fail('Enter a plate of 1 to 8 letters and numbers.');
    if (S.vehicles.some((v) => v.plateKey === key && v !== old)) S.fail(`Plate ${key} is already registered to another vehicle.`);
    const model = String(vehicle.model || '').trim() || S.fail('Enter the model.');
    const v = old || { id: S.nextId('vehicle'), flags: [], notes: '', owner: S.myLicense, createdAt: S.now(),
      registration: vehicle.registration === 'none' ? 'none' : 'valid', insurance: vehicle.insurance === 'none' ? 'none' : 'valid' };
    Object.assign(v, { plate: key, plateKey: key, model: model.slice(0, 30), color: String(vehicle.color || '').trim().slice(0, 20), ownerId: owner.id, updatedAt: S.now() });
    if (!old) S.vehicles.push(v);
    return S.withOwner(v);
  });

  M.on('civ.deleteVehicle', ({ id }) => { const v = myRecord(S.vehicles, id, 'vehicle'); S.vehicles = S.vehicles.filter((x) => x !== v); return true; });

  M.on('civ.saveWeapon', ({ weapon }) => {
    const old = weapon.id ? myRecord(S.weapons, weapon.id, 'weapon') : null;
    const owner = myPerson(weapon.ownerId);
    const count = S.weapons.filter((w) => w.ownerId === owner.id).length;
    if ((!old || old.ownerId !== owner.id) && count >= S.config.civilian.maxWeapons) S.fail(`Each character can register up to ${S.config.civilian.maxWeapons} weapons.`);
    const serial = String(weapon.serial || '').toUpperCase().replace(/\s/g, '');
    if (!/^[A-Z0-9-]{1,20}$/.test(serial)) S.fail('Enter a serial number of up to 20 letters, numbers and dashes.');
    if (S.weapons.some((w) => w.serial === serial && w !== old)) S.fail(`Serial ${serial} is already registered.`);
    const kind = String(weapon.kind || '').trim() || S.fail('Enter the kind of weapon.');
    const w = old || { id: S.nextId('weapon'), status: 'registered', notes: '', owner: S.myLicense, createdAt: S.now() };
    Object.assign(w, { serial, kind: kind.slice(0, 30), ownerId: owner.id, updatedAt: S.now() });
    if (!old) S.weapons.push(w);
    return S.withOwner(w);
  });

  M.on('civ.deleteWeapon', ({ id }) => {
    const w = myRecord(S.weapons, id, 'weapon');
    if (w.status === 'seized') S.fail('This weapon was seized by the police.');
    S.weapons = S.weapons.filter((x) => x !== w);
    return true;
  });

  M.on('civ.reportStolen', ({ vehicleId, weaponId, stolen }) => {
    if (vehicleId !== undefined) {
      const v = myRecord(S.vehicles, vehicleId, 'vehicle');
      v.flags = v.flags.filter((f) => f !== 'stolen').concat(stolen ? ['stolen'] : []);
      return S.withOwner(v);
    }
    const w = myRecord(S.weapons, weaponId, 'weapon');
    if (w.status === 'seized') S.fail('This weapon was seized by the police.');
    w.status = stolen ? 'stolen' : 'registered';
    return S.withOwner(w);
  });

  // ------------------------------------------------------------------ live preview

  if (new URLSearchParams(window.location.search).get('live')) {
    const samples = [
      ['10-66', 'Shots heard near the motel', 'Pink Cage Motel, Alta'],
      ['10-50', 'Car into a pole, driver unconscious', 'Mirror Park Blvd, Mirror Park'],
      ['10-31', 'Man breaking into parked cars', 'Elgin Ave, Pillbox Hill'],
      ['10-70', 'Smoke coming from a warehouse', 'Elysian Fields Fwy, Elysian Island'],
    ];
    let i = 0;
    setInterval(() => {
      const [code, title, street] = samples[i % samples.length];
      i += 1;
      const c = S.config.callCodes.find((x) => x.code === code);
      const call = {
        id: S.nextId('call'), title, code, priority: c.priority, service: c.service, status: 'pending', description: title,
        location: { x: 100 * i, y: -200 * i, z: 30, street }, caller: { name: 'Preview caller', anonymous: false }, units: [], primary: null,
        notes: [{ at: S.now(), by: '911', text: 'Call received.', system: true }], disposition: null, source: '911',
        createdAt: S.now(), updatedAt: S.now(), closedAt: null,
      };
      S.calls.push(call);
      CAD.push('call', call);
      if (S.myUnit()) CAD.push('alert', { kind: 'new', call });
    }, 40000);
  }
})();
