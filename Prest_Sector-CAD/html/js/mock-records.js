'use strict';
// Browser preview only: answers the records requests (people, vehicles, weapons, plates, reports,
// warrants, BOLOs) the way the server does, from the made-up data in mock.js.

(() => {
  if (CAD.inGame) return;
  const M = CAD.mock;
  const S = M.state;

  const find = (list, id, what) => list.find((x) => x.id === Number(id)) || S.fail(`That ${what} could not be found.`);
  const plateKey = (plate) => { const k = String(plate || '').toUpperCase().replace(/[^A-Z0-9]/g, ''); return k.length >= 1 && k.length <= 8 ? k : null; };
  const pub = (record) => { const out = { ...record }; delete out.owner; delete out.authorLicense; delete out.requesterLicense; return out; };
  const lower = (v) => String(v || '').toLowerCase();
  const newest = (a, b) => (b.updatedAt - a.updatedAt) || (b.id - a.id);
  const charge = (code) => { for (const t of S.config.penal) { const c = t.charges.find((x) => x.code === code); if (c) return c; } return null; };
  const totals = (charges) => {
    const items = [];
    (charges || []).forEach((c) => {
      const ch = charge(c.code) || S.fail(`There is no charge ${c.code} in the penal code.`);
      const count = Math.max(1, Math.min(20, Number(c.count) || 1));
      const have = items.find((i) => i.code === ch.code);
      if (have) { have.count = Math.min(20, have.count + count); } else items.push({ code: ch.code, name: ch.name, class: ch.class, count });
    });
    items.forEach((i) => { const ch = charge(i.code); i.fine = ch.fine * i.count; i.jail = ch.jail * i.count; });
    return { fine: items.reduce((s, i) => s + i.fine, 0), jail: items.reduce((s, i) => s + i.jail, 0), items };
  };
  const by = () => ({ name: S.me.name, callsign: S.myUnit() ? S.myUnit().callsign : null });

  // ------------------------------------------------------------------ people

  M.on('person.search', ({ query }) => {
    S.need('people.view');
    const q = lower(query).trim();
    if (!q) return [];
    const id = /^p-?(\d+)$/.exec(q);
    return S.persons.filter((p) => (id ? p.id === Number(id[1])
      : `${lower(p.first)} ${lower(p.last)}`.includes(q) || `${lower(p.last)}, ${lower(p.first)}`.includes(q) || (p.dob || '').includes(q)
        || (/\d{3}/.test(q) && !/[a-z]/.test(q) && (p.phone || '').replace(/\D/g, '').includes(q.replace(/\D/g, '')))))
      .sort((a, b) => a.last.localeCompare(b.last) || a.first.localeCompare(b.first)).slice(0, 25).map(S.summary);
  });

  M.on('person.get', ({ id }) => {
    S.need('people.view');
    const p = find(S.persons, id, 'person');
    const out = {
      person: pub(p), summary: S.summary(p),
      vehicles: S.vehicles.filter((v) => v.ownerId === p.id).map((v) => pub(S.withOwner(v))),
      weapons: S.weapons.filter((w) => w.ownerId === p.id).map((w) => pub(S.withOwner(w))),
      bolos: S.bolos.filter((b) => b.active && b.personId === p.id).map(pub),
    };
    if (S.can('records.view')) {
      out.reports = S.reports.filter((r) => r.persons.includes(p.id)).sort(newest)
        .map((r) => ({ ...pub(r), personNames: r.persons.map((i) => S.personName(i) || 'Deleted person') }));
      out.warrants = S.warrants.filter((w) => w.personId === p.id).sort(newest).map((w) => ({ ...pub(w), personName: S.personName(w.personId) }));
    }
    return out;
  });

  M.on('person.save', ({ person }) => {
    S.need('records.edit');
    const old = person.id ? find(S.persons, person.id, 'person') : null;
    ['first', 'last'].forEach((f) => { if (!String(person[f] || '').trim()) S.fail(`Enter a ${f} name.`); });
    if (!/^\d{4}-\d{2}-\d{2}$/.test(person.dob || '')) S.fail('Enter the date of birth as YYYY-MM-DD.');
    if (!S.config.genders.includes(person.gender)) S.fail('Pick a gender.');
    const p = old || { id: S.nextId('person'), owner: null, createdAt: S.now() };
    Object.assign(p, {
      first: person.first.trim(), last: person.last.trim(), dob: person.dob, gender: person.gender, address: person.address || '',
      phone: person.phone || '', height: person.height || '', mugshot: person.mugshot || '', description: person.description || '',
      notes: person.notes || '', licenses: { ...person.licenses }, flags: [...new Set(person.flags || [])], updatedAt: S.now(),
    });
    if (!old) S.persons.push(p);
    return pub(p);
  });

  M.on('person.delete', ({ id }) => {
    S.need('records.delete');
    const p = find(S.persons, id, 'person');
    S.vehicles.concat(S.weapons).forEach((r) => { if (r.ownerId === p.id) r.ownerId = null; });
    S.persons = S.persons.filter((x) => x !== p);
    return true;
  });

  // ------------------------------------------------------------------ vehicles and weapons

  M.on('vehicle.search', ({ query }) => {
    S.need('people.view');
    const q = lower(query).trim();
    if (!q) return [];
    const key = plateKey(q);
    return S.vehicles.filter((v) => (key && v.plateKey.includes(key)) || lower(v.model).includes(q) || lower(S.personName(v.ownerId)).includes(q))
      .slice(0, 25).map((v) => pub(S.withOwner(v)));
  });

  M.on('vehicle.get', ({ id }) => {
    S.need('people.view');
    const v = find(S.vehicles, id, 'vehicle');
    return { vehicle: pub(S.withOwner(v)), owner: S.summary(S.persons.find((p) => p.id === v.ownerId)) || null,
      bolos: S.bolos.filter((b) => b.active && b.plate === v.plateKey).map(pub) };
  });

  M.on('vehicle.save', ({ vehicle }) => {
    S.need('records.edit');
    const old = vehicle.id ? find(S.vehicles, vehicle.id, 'vehicle') : null;
    const key = plateKey(vehicle.plate) || S.fail('Enter a plate of 1 to 8 letters and numbers.');
    if (S.vehicles.some((v) => v.plateKey === key && v !== old)) S.fail(`Plate ${key} is already registered to another vehicle.`);
    if (vehicle.ownerId && !S.persons.some((p) => p.id === vehicle.ownerId)) S.fail('That owner could not be found.');
    const v = old || { id: S.nextId('vehicle'), owner: null, createdAt: S.now() };
    Object.assign(v, { plate: key, plateKey: key, model: vehicle.model || '', color: vehicle.color || '', ownerId: vehicle.ownerId || null,
      registration: vehicle.registration, insurance: vehicle.insurance, flags: [...new Set(vehicle.flags || [])], notes: vehicle.notes || '', updatedAt: S.now() });
    if (!old) S.vehicles.push(v);
    return pub(S.withOwner(v));
  });

  M.on('vehicle.delete', ({ id }) => { S.need('records.delete'); const v = find(S.vehicles, id, 'vehicle'); S.vehicles = S.vehicles.filter((x) => x !== v); return true; });

  M.on('weapon.search', ({ query }) => {
    S.need('people.view');
    const q = lower(query).trim();
    if (!q) return [];
    return S.weapons.filter((w) => lower(w.serial).includes(q) || lower(w.kind).includes(q) || lower(S.personName(w.ownerId)).includes(q))
      .slice(0, 25).map((w) => pub(S.withOwner(w)));
  });

  M.on('weapon.get', ({ id }) => {
    S.need('people.view');
    const w = find(S.weapons, id, 'weapon');
    return { weapon: pub(S.withOwner(w)), owner: S.summary(S.persons.find((p) => p.id === w.ownerId)) || null };
  });

  M.on('weapon.save', ({ weapon }) => {
    S.need('records.edit');
    const old = weapon.id ? find(S.weapons, weapon.id, 'weapon') : null;
    const serial = String(weapon.serial || '').toUpperCase().replace(/\s/g, '');
    if (!/^[A-Z0-9-]{1,20}$/.test(serial)) S.fail('Enter a serial number of up to 20 letters, numbers and dashes.');
    if (S.weapons.some((w) => w.serial === serial && w !== old)) S.fail(`Serial ${serial} is already registered.`);
    if (!String(weapon.kind || '').trim()) S.fail('Enter the kind of weapon.');
    const w = old || { id: S.nextId('weapon'), owner: null, createdAt: S.now() };
    Object.assign(w, { serial, kind: weapon.kind.trim(), ownerId: weapon.ownerId || null, status: weapon.status, notes: weapon.notes || '', updatedAt: S.now() });
    if (!old) S.weapons.push(w);
    return pub(S.withOwner(w));
  });

  M.on('weapon.delete', ({ id }) => { S.need('records.delete'); const w = find(S.weapons, id, 'weapon'); S.weapons = S.weapons.filter((x) => x !== w); return true; });

  M.on('plate.check', ({ plate }) => {
    S.need('people.view');
    const key = plateKey(plate) || S.fail('That is not a plate.');
    const v = S.vehicles.find((x) => x.plateKey === key);
    const result = { plate: key, found: Boolean(v), alerts: [] };
    const alert = (text, tone = 'warning') => result.alerts.push({ text, tone });
    S.bolos.filter((b) => b.active && b.plate === key).forEach((b) => alert(`BOLO: ${b.title}`, 'error'));
    if (!v) { alert('No record of this plate.'); return result; }
    result.vehicle = pub(S.withOwner(v));
    if (v.flags.includes('stolen')) alert('Reported STOLEN.', 'error');
    if (v.flags.includes('flagged')) alert('Flagged for stop.', 'error');
    if (v.flags.includes('impounded')) alert('Marked as impounded.');
    const label = (list, k) => (S.config[list].find((x) => x.key === k) || {}).label || k;
    if (v.registration !== 'valid') alert(`Registration: ${label('registrationStates', v.registration)}.`);
    if (v.insurance !== 'valid') alert(`Insurance: ${label('insuranceStates', v.insurance)}.`);
    const owner = S.persons.find((p) => p.id === v.ownerId);
    if (!owner) { alert('No registered owner.'); return result; }
    result.owner = S.summary(owner);
    if (result.owner.warrants) alert(`Owner has ${result.owner.warrants} active warrant${result.owner.warrants === 1 ? '' : 's'}.`, 'error');
    if (owner.licenses.driver !== 'valid') alert(`Owner's driver's license: ${label('licenseStates', owner.licenses.driver)}.`);
    owner.flags.filter((f) => f === 'armed' || f === 'officer_safety').forEach((f) => alert(`Owner: ${label('personFlags', f)}.`, 'error'));
    return result;
  });

  // ------------------------------------------------------------------ reports

  const canRead = (r) => S.can('records.view') || r.authorLicense === S.myLicense;
  const entry = (r) => ({ ...pub(r), personNames: r.persons.map((i) => S.personName(i) || 'Deleted person') });
  const full = (r) => ({ ...pub(r), personsInfo: r.persons.map((i) => S.summary(S.persons.find((p) => p.id === i)) || { id: i, first: 'Deleted', last: 'person', flags: [] }),
    vehiclesInfo: r.vehicles.map((i) => S.vehicles.find((v) => v.id === i)).filter(Boolean).map((v) => pub(S.withOwner(v))) });

  M.on('report.list', ({ query, type, status, mine }) => {
    if (!S.can('records.view') && !S.can('reports.write')) S.fail("You aren't allowed to do that.");
    const q = lower(query).trim();
    return S.reports.filter(canRead).filter((r) => (!type || r.type === type) && (!status || r.status === status) && (!mine || r.authorLicense === S.myLicense)
      && (!q || lower(r.title).includes(q) || lower(r.author && r.author.name).includes(q) || entry(r).personNames.some((n) => lower(n).includes(q))
        || q === `r-${r.id}`)).sort(newest).slice(0, 50).map(entry);
  });

  M.on('report.get', ({ id }) => {
    const r = find(S.reports, id, 'report');
    if (!canRead(r)) S.fail('You can only read your own reports.');
    return full(r);
  });

  M.on('report.save', ({ report }) => {
    S.need('reports.write');
    const old = report.id ? find(S.reports, report.id, 'report') : null;
    if (old && !S.can('reports.approve') && !(old.authorLicense === S.myLicense && old.status !== 'approved')) S.fail('You can only change your own reports.');
    if (!S.me.reportTypes.includes(report.type)) S.fail("You can't write that type of report.");
    const type = S.config.reportTypes.find((t) => t.key === report.type);
    if (!String(report.title || '').trim()) S.fail('Enter a title.');
    const charges = report.charges || [];
    if (charges.length && !type.charges) S.fail('This type of report has no charges.');
    const t = charges.length ? totals(charges) : null;
    if (report.status === 'submitted' && type.charges) {
      if (!(report.persons || []).length) S.fail('Name the person this is for before submitting it.');
      if (!charges.length) S.fail('Add at least one charge before submitting it.');
    }
    if (report.callId && !S.calls.concat(S.closedCalls).some((c) => c.id === Number(report.callId))) S.fail('That call could not be found.');
    const r = old || { id: S.nextId('report'), createdAt: S.now(), author: by(), authorLicense: S.myLicense, approvedBy: null };
    Object.assign(r, { type: report.type, title: report.title.trim().slice(0, 80), narrative: report.narrative || '', persons: [...new Set(report.persons || [])],
      vehicles: [...new Set(report.vehicles || [])], callId: report.callId || null, charges: t ? t.items.map((i) => ({ code: i.code, count: i.count })) : [],
      totals: t, status: old && old.status === 'approved' ? 'approved' : report.status, updatedAt: S.now() });
    if (!old) S.reports.push(r);
    return full(r);
  });

  M.on('report.approve', ({ id }) => {
    S.need('reports.approve');
    const r = find(S.reports, id, 'report');
    if (r.status !== 'submitted') S.fail('Only submitted reports can be approved.');
    Object.assign(r, { status: 'approved', approvedBy: S.me.name, updatedAt: S.now() });
    return full(r);
  });

  M.on('report.delete', ({ id }) => { S.need('records.delete'); const r = find(S.reports, id, 'report'); S.reports = S.reports.filter((x) => x !== r); return true; });

  // ------------------------------------------------------------------ warrants

  const warrantOut = (w) => ({ ...pub(w), personName: S.personName(w.personId) || 'Deleted person' });
  M.on('warrant.list', ({ status }) => {
    S.need('records.view');
    return S.warrants.filter((w) => !status || w.status === status).sort(newest).map(warrantOut);
  });

  M.on('warrant.save', ({ warrant }) => {
    S.need('warrants.request');
    if (!S.persons.some((p) => p.id === Number(warrant.personId))) S.fail('That person could not be found.');
    if (!(warrant.charges || []).length) S.fail('Add at least one charge.');
    if (!String(warrant.reason || '').trim()) S.fail('Enter the reason for the warrant.');
    const t = totals(warrant.charges);
    const active = !S.config.warrantsNeedApproval || S.can('warrants.approve');
    const w = { id: S.nextId('warrant'), personId: Number(warrant.personId), charges: t.items.map((i) => ({ code: i.code, count: i.count })), totals: t,
      reason: warrant.reason.trim(), status: active ? 'active' : 'requested', requestedBy: by(), decidedBy: active ? { name: S.me.name } : null,
      createdAt: S.now(), updatedAt: S.now() };
    S.warrants.push(w);
    return warrantOut(w);
  });

  const MOVES = { requested: { active: 'warrants.approve', denied: 'warrants.approve' }, active: { served: 'warrants.request', recalled: 'warrants.approve' } };
  M.on('warrant.setStatus', ({ id, status }) => {
    const w = find(S.warrants, id, 'warrant');
    const ability = (MOVES[w.status] || {})[status] || S.fail(`A ${w.status} warrant can't be marked ${status}.`);
    S.need(ability);
    w.status = status;
    if (status === 'served') w.servedBy = by(); else w.decidedBy = { name: S.me.name };
    w.updatedAt = S.now();
    return warrantOut(w);
  });

  // ------------------------------------------------------------------ BOLOs

  const boloOut = (b) => ({ ...pub(b), personName: S.personName(b.personId) });
  M.on('bolo.list', ({ active }) => {
    S.need('people.view');
    return S.bolos.filter((b) => typeof active !== 'boolean' || b.active === active).sort(newest).map(boloOut);
  });

  M.on('bolo.save', ({ bolo }) => {
    S.need('bolos.edit');
    if (!['person', 'vehicle', 'other'].includes(bolo.kind)) S.fail('Pick what the BOLO is for: a person, a vehicle or something else.');
    if (!String(bolo.title || '').trim()) S.fail('Enter a title.');
    let plate = null;
    if (bolo.plate) plate = plateKey(bolo.plate) || S.fail('Enter a plate of 1 to 8 letters and numbers.');
    const old = bolo.id ? find(S.bolos, bolo.id, 'BOLO') : null;
    const b = old || { id: S.nextId('bolo'), active: true, createdBy: by(), createdAt: S.now() };
    Object.assign(b, { kind: bolo.kind, title: bolo.title.trim().slice(0, 80), description: bolo.description || '', plate, personId: bolo.personId || null, updatedAt: S.now() });
    if (!old) S.bolos.push(b);
    return boloOut(b);
  });

  M.on('bolo.setActive', ({ id, active }) => {
    S.need('bolos.edit');
    const b = find(S.bolos, id, 'BOLO');
    b.active = active === true;
    b.updatedAt = S.now();
    return boloOut(b);
  });
})();
