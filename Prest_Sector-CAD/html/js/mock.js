'use strict';
// Made-up data for previewing the tablet in a normal browser (it isn't used in game). Open
// html/index.html?as=police (or dispatch, fire, supervisor, judge, civilian) and &page=people.
// mock-dispatch.js and mock-records.js answer the rest of the server's requests from this data.

(() => {
  if (CAD.inGame) return;
  const M = CAD.mock;
  const now = () => Math.floor(Date.now() / 1000);
  const ago = (min) => now() - min * 60;

  // A copy of config.lua's lists (the penal code is shortened).
  const config = {
    departments: [
      { key: 'lspd', label: 'Los Santos Police Department', short: 'LSPD', role: 'police', color: '#3b82f6' },
      { key: 'bcso', label: "Blaine County Sheriff's Office", short: 'BCSO', role: 'police', color: '#a16207' },
      { key: 'sahp', label: 'San Andreas Highway Patrol', short: 'SAHP', role: 'police', color: '#eab308' },
      { key: 'lsfd', label: 'Los Santos Fire Department', short: 'LSFD', role: 'fire', color: '#ef4444' },
      { key: 'ems', label: 'Emergency Medical Services', short: 'EMS', role: 'fire', color: '#f97316' },
      { key: 'comms', label: 'Communications (Dispatch)', short: 'COMMS', role: 'dispatch', color: '#8b5cf6' },
    ],
    statuses: [
      { key: 'available', code: '10-8', label: 'Available', color: '#22c55e' },
      { key: 'enroute', code: '10-97', label: 'En route', color: '#3b82f6' },
      { key: 'onscene', code: '10-23', label: 'On scene', color: '#a855f7' },
      { key: 'busy', code: '10-6', label: 'Busy', color: '#f59e0b' },
      { key: 'transport', code: '10-15', label: 'Transporting', color: '#06b6d4' },
      { key: 'break', code: '10-7', label: 'Out of service', color: '#64748b' },
    ],
    priorities: [
      { level: 1, label: 'P1 Emergency', color: '#ef4444' },
      { level: 2, label: 'P2 Urgent', color: '#f59e0b' },
      { level: 3, label: 'P3 Routine', color: '#22c55e' },
    ],
    services: [{ key: 'police', label: 'Police' }, { key: 'fire', label: 'Fire' }, { key: 'ems', label: 'EMS' }, { key: 'all', label: 'All units' }],
    callCodes: [
      { code: '911', label: '911 call', priority: 2, service: 'all' },
      { code: '311', label: 'Non-emergency call', priority: 3, service: 'police' },
      { code: '10-10', label: 'Fight in progress', priority: 2, service: 'police' },
      { code: '10-16', label: 'Domestic disturbance', priority: 2, service: 'police' },
      { code: '10-31', label: 'Crime in progress', priority: 1, service: 'police' },
      { code: '10-32', label: 'Person with a gun', priority: 1, service: 'police' },
      { code: '10-38', label: 'Traffic stop', priority: 3, service: 'police' },
      { code: '10-50', label: 'Traffic collision', priority: 2, service: 'all' },
      { code: '10-55', label: 'Impaired driver', priority: 2, service: 'police' },
      { code: '10-60', label: 'Suspicious person or vehicle', priority: 3, service: 'police' },
      { code: '10-66', label: 'Shots fired', priority: 1, service: 'police' },
      { code: '10-70', label: 'Fire', priority: 1, service: 'fire' },
      { code: '10-80', label: 'Pursuit', priority: 1, service: 'police' },
      { code: '10-90', label: 'Robbery or alarm', priority: 1, service: 'police' },
      { code: '10-52', label: 'Medical emergency', priority: 1, service: 'ems' },
      { code: '10-99', label: 'Officer needs help (panic)', priority: 1, service: 'police' },
    ],
    dispositions: ['Report taken', 'Arrest made', 'Citation issued', 'Warning given', 'Gone on arrival', 'Unfounded',
      'Handled by caller', 'Transported', 'Cancelled', 'Duplicate call'],
    genders: ['Male', 'Female', 'Other'],
    licenses: [
      { key: 'driver', label: "Driver's license" }, { key: 'commercial', label: 'Commercial (CDL)' },
      { key: 'motorcycle', label: 'Motorcycle' }, { key: 'weapon', label: 'Weapon permit' }, { key: 'pilot', label: 'Pilot' },
      { key: 'hunting', label: 'Hunting' }, { key: 'fishing', label: 'Fishing' },
    ],
    licenseStates: [
      { key: 'valid', label: 'Valid', color: '#22c55e' }, { key: 'suspended', label: 'Suspended', color: '#f59e0b' },
      { key: 'revoked', label: 'Revoked', color: '#ef4444' }, { key: 'expired', label: 'Expired', color: '#f97316' },
      { key: 'none', label: 'None', color: '#64748b' },
    ],
    personFlags: [
      { key: 'armed', label: 'Armed and dangerous', color: '#ef4444' }, { key: 'officer_safety', label: 'Officer safety caution', color: '#ef4444' },
      { key: 'gang', label: 'Gang affiliation', color: '#a855f7' }, { key: 'mental', label: 'Mental health', color: '#06b6d4' },
      { key: 'probation', label: 'On probation', color: '#f59e0b' }, { key: 'parole', label: 'On parole', color: '#f59e0b' },
      { key: 'missing', label: 'Missing person', color: '#3b82f6' },
    ],
    registrationStates: [
      { key: 'valid', label: 'Valid', color: '#22c55e' }, { key: 'expired', label: 'Expired', color: '#f97316' },
      { key: 'suspended', label: 'Suspended', color: '#ef4444' }, { key: 'none', label: 'Unregistered', color: '#64748b' },
    ],
    insuranceStates: [
      { key: 'valid', label: 'Insured', color: '#22c55e' }, { key: 'expired', label: 'Expired', color: '#f97316' },
      { key: 'none', label: 'Uninsured', color: '#ef4444' },
    ],
    vehicleFlags: [
      { key: 'stolen', label: 'Stolen', color: '#ef4444' }, { key: 'impounded', label: 'Impounded', color: '#f59e0b' },
      { key: 'flagged', label: 'Flagged for stop', color: '#a855f7' },
    ],
    weaponStates: [
      { key: 'registered', label: 'Registered', color: '#22c55e' }, { key: 'stolen', label: 'Stolen', color: '#ef4444' },
      { key: 'seized', label: 'Seized', color: '#f59e0b' },
    ],
    reportTypes: [
      { key: 'incident', label: 'Incident report', roles: ['police', 'dispatch'] },
      { key: 'arrest', label: 'Arrest report', roles: ['police'], charges: true },
      { key: 'citation', label: 'Citation', roles: ['police'], charges: true },
      { key: 'warning', label: 'Written warning', roles: ['police'] },
      { key: 'field', label: 'Field interview', roles: ['police'] },
      { key: 'medical', label: 'Patient care report', roles: ['fire'] },
      { key: 'fire', label: 'Fire incident report', roles: ['fire'] },
    ],
    penal: [
      {
        title: 'Title 1 - Crimes against people',
        charges: [
          { code: '1-01', name: 'Assault', class: 'misdemeanor', fine: 750, jail: 10 },
          { code: '1-02', name: 'Assault with a deadly weapon', class: 'felony', fine: 2500, jail: 30 },
          { code: '1-03', name: 'Battery', class: 'misdemeanor', fine: 1000, jail: 15 },
          { code: '1-06', name: 'Murder', class: 'felony', fine: 25000, jail: 120 },
        ],
      },
      {
        title: 'Title 2 - Crimes against property',
        charges: [
          { code: '2-01', name: 'Petty theft', class: 'misdemeanor', fine: 300, jail: 0 },
          { code: '2-03', name: 'Grand theft auto', class: 'felony', fine: 2000, jail: 20 },
          { code: '2-05', name: 'Robbery', class: 'felony', fine: 3000, jail: 30 },
        ],
      },
      {
        title: 'Title 5 - Vehicles and traffic',
        charges: [
          { code: '5-01', name: 'Speeding (up to 15 over)', class: 'infraction', fine: 150, jail: 0 },
          { code: '5-05', name: 'Reckless driving', class: 'misdemeanor', fine: 1000, jail: 5 },
          { code: '5-06', name: 'Driving under the influence', class: 'misdemeanor', fine: 1500, jail: 10 },
          { code: '5-08', name: 'Driving on a suspended license', class: 'misdemeanor', fine: 1000, jail: 5 },
        ],
      },
    ],
    civilian: { maxCharacters: 5, maxVehicles: 10, maxWeapons: 10 },
    warrantsNeedApproval: true,
    unitsCanManageCalls: true,
  };

  // The same rules as shared/cad.lua's C.abilities, for the preview.
  const abilities = (roles) => {
    const has = (...list) => list.some((r) => roles[r]);
    const a = {};
    const give = (name, yes) => { if (yes) a[name] = true; };
    give('unit.signon', has('police', 'fire', 'dispatch', 'supervisor', 'admin'));
    give('dispatch.view', has('police', 'fire', 'dispatch', 'supervisor', 'admin'));
    give('dispatch.manage', has('dispatch', 'supervisor', 'admin') || (config.unitsCanManageCalls && has('police', 'fire')));
    give('calls.create', has('police', 'fire', 'dispatch', 'supervisor', 'admin'));
    give('people.view', has('police', 'dispatch', 'supervisor', 'judge', 'admin', 'fire'));
    give('records.view', has('police', 'dispatch', 'supervisor', 'judge', 'admin'));
    give('records.edit', has('police', 'dispatch', 'supervisor', 'admin'));
    give('records.delete', has('supervisor', 'admin'));
    give('reports.write', has('police', 'fire', 'dispatch', 'supervisor', 'admin'));
    give('reports.approve', has('supervisor', 'admin'));
    give('warrants.request', has('police', 'supervisor', 'admin'));
    give('warrants.approve', has('judge', 'supervisor', 'admin'));
    give('bolos.edit', has('police', 'dispatch', 'supervisor', 'admin'));
    return a;
  };

  const as = new URLSearchParams(window.location.search).get('as') || 'police';
  const roles = {};
  if (as === 'supervisor') Object.assign(roles, { police: true, supervisor: true });
  else if (as !== 'civilian') roles[as] = true;
  const departments = config.departments.filter((d) => roles.supervisor || roles.admin || roles[d.role]).map((d) => d.key);
  const reportTypes = config.reportTypes.filter((t) => roles.supervisor || roles.admin || t.roles.some((r) => roles[r])).map((t) => t.key);

  const S = M.state;
  S.config = config;
  S.me = { id: 7, name: as === 'civilian' ? 'Jordan Hayes' : 'Alex Mercer', roles, abilities: abilities(roles), unit: null, departments, reportTypes };
  S.myLicense = 'license:me';
  S.seq = { person: 6, vehicle: 6, weapon: 4, report: 4, warrant: 3, bolo: 3, call: 1004 };
  S.nextId = (kind) => { const id = S.seq[kind]; S.seq[kind] += 1; return id; };
  S.now = now;
  S.fail = (text) => { throw new Error(text); };

  const loc = (x, y, street) => ({ x, y, z: 30, street });
  S.units = [
    { id: 2, name: 'Sam Ortiz', callsign: '1-ADAM-12', department: 'lspd', role: 'police', status: 'enroute', callId: 1001, location: loc(215, -810, 'Strawberry Ave / Davis Ave, Strawberry'), since: ago(4), signedOnAt: ago(80) },
    { id: 3, name: 'Riley Chen', callsign: '1-ADAM-20', department: 'lspd', role: 'police', status: 'available', callId: null, location: loc(-540, -210, 'Vespucci Blvd, Little Seoul'), since: ago(12), signedOnAt: ago(95) },
    { id: 4, name: 'Dana Brooks', callsign: 'S-14', department: 'bcso', role: 'police', status: 'onscene', callId: 1002, location: loc(1960, 3740, 'Panorama Dr, Sandy Shores'), since: ago(9), signedOnAt: ago(60) },
    { id: 5, name: 'Morgan Lee', callsign: 'E-7', department: 'ems', role: 'fire', status: 'available', callId: null, location: loc(300, -590, 'Pillbox Hill Medical'), since: ago(30), signedOnAt: ago(120) },
    { id: 6, name: 'Casey Ward', callsign: 'DISPATCH-1', department: 'comms', role: 'dispatch', status: 'available', callId: null, location: loc(440, -980, 'Mission Row'), since: ago(60), signedOnAt: ago(200) },
  ];
  S.calls = [
    {
      id: 1001, title: 'Armed robbery at a convenience store', code: '10-90', priority: 1, service: 'police', status: 'active',
      description: 'Caller says a man with a handgun is robbing the clerk. Black hoodie, left on foot heading north.',
      location: loc(25, -1345, 'Innocence Blvd / Strawberry Ave, Strawberry'), caller: { name: 'Priya Natarajan', anonymous: false },
      units: [2], primary: 2, source: '911', disposition: null, createdAt: ago(6), updatedAt: ago(4), closedAt: null,
      notes: [
        { at: ago(6), by: '911', text: 'Call received from Priya Natarajan.', system: true },
        { at: ago(4), by: 'DISPATCH-1', text: '1-ADAM-12 attached.', system: true },
        { at: ago(3), by: 'DISPATCH-1', text: 'Second caller reports the suspect got into a silver sedan.', system: false },
      ],
    },
    {
      id: 1002, title: 'Traffic collision, two vehicles', code: '10-50', priority: 2, service: 'all', status: 'active',
      description: 'Two cars, one on its side. One driver complaining of neck pain.',
      location: loc(1960, 3745, 'Panorama Dr, Sandy Shores'), caller: { name: 'Unknown', anonymous: false },
      units: [4], primary: 4, source: '911', disposition: null, createdAt: ago(15), updatedAt: ago(9), closedAt: null,
      notes: [{ at: ago(15), by: '911', text: 'Call received.', system: true }],
    },
    {
      id: 1003, title: 'Loud music, neighbour complaint', code: '311', priority: 3, service: 'police', status: 'pending',
      description: 'Party at the house next door since 10pm.', location: loc(-1110, -1490, 'Prosperity St, Vespucci Canals'),
      caller: { name: 'Anonymous', anonymous: true }, units: [], primary: null, source: '311', disposition: null,
      createdAt: ago(22), updatedAt: ago(22), closedAt: null, notes: [{ at: ago(22), by: '311', text: 'Call received.', system: true }],
    },
  ];
  S.closedCalls = [];

  const person = (id, first, last, dob, gender, extra = {}) => ({
    id, first, last, dob, gender, address: '', phone: '', height: '', description: '', mugshot: '', notes: '',
    licenses: { driver: 'valid', commercial: 'none', motorcycle: 'none', weapon: 'none', pilot: 'none', hunting: 'none', fishing: 'none' },
    flags: [], owner: null, createdAt: ago(60 * 24 * 10), updatedAt: ago(60 * 24 * 2), ...extra,
  });
  S.persons = [
    person(1, 'Marcus', 'Bell', '1991-04-12', 'Male', { address: '14 Grove St, Davis', phone: '555-0142', height: "6'1\"", flags: ['armed', 'gang'],
      licenses: { driver: 'suspended', commercial: 'none', motorcycle: 'none', weapon: 'revoked', pilot: 'none', hunting: 'none', fishing: 'none' },
      notes: 'Known to carry a pistol in the waistband.' }),
    person(2, 'Jordan', 'Hayes', '1998-09-03', 'Female', { address: '220 Alta St, Downtown', phone: '555-0199', owner: 'license:me' }),
    person(3, 'Priya', 'Natarajan', '1987-01-25', 'Female', { address: 'Innocence Blvd, Strawberry', phone: '555-0110' }),
    person(4, 'Tommy', 'Reyes', '2001-07-19', 'Male', { flags: ['probation'], address: 'Sandy Shores trailer park' }),
    person(5, 'Ava', 'Kowalski', '1979-11-30', 'Female', { flags: ['missing'], address: 'Mirror Park' }),
  ];
  const vehicle = (id, plate, model, color, ownerId, extra = {}) => ({
    id, plate, plateKey: plate.replace(/[^A-Z0-9]/g, ''), model, color, ownerId, registration: 'valid', insurance: 'valid', flags: [], notes: '',
    owner: null, createdAt: ago(60 * 24 * 9), updatedAt: ago(60 * 24 * 3), ...extra,
  });
  S.vehicles = [
    vehicle(1, '46EEK572', 'Karin Sultan', 'Silver', 1, { registration: 'expired', insurance: 'none' }),
    vehicle(2, 'JHAYES01', 'Benefactor Schafter', 'Black', 2, { owner: 'license:me' }),
    vehicle(3, '8ABC123', 'Vapid Stanier', 'White', 3, { flags: ['stolen'] }),
    vehicle(4, 'RDNECK', 'Bravado Bison', 'Red', 4),
    vehicle(5, '5PLX902', 'Declasse Granger', 'Blue', null, { registration: 'none', flags: ['flagged'] }),
  ];
  S.weapons = [
    { id: 1, serial: 'GLK-44817', kind: 'Combat pistol', ownerId: 1, status: 'stolen', notes: '', owner: null, createdAt: ago(9000), updatedAt: ago(800) },
    { id: 2, serial: 'RUG-20931', kind: 'Pistol', ownerId: 2, status: 'registered', notes: '', owner: 'license:me', createdAt: ago(7000), updatedAt: ago(7000) },
    { id: 3, serial: 'REM-87001', kind: 'Pump shotgun', ownerId: 4, status: 'registered', notes: '', owner: null, createdAt: ago(5000), updatedAt: ago(5000) },
  ];
  S.reports = [
    { id: 1, type: 'arrest', title: 'Arrest of Marcus Bell for armed robbery', narrative: 'On the above date I responded to a robbery call...',
      persons: [1], vehicles: [1], callId: null, charges: [{ code: '2-05', count: 1 }, { code: '4-01', count: 1 }],
      totals: { fine: 4500, jail: 40, items: [{ code: '2-05', name: 'Robbery', class: 'felony', count: 1, fine: 3000, jail: 30 }, { code: '4-01', name: 'Carrying a weapon without a permit', class: 'misdemeanor', count: 1, fine: 1500, jail: 10 }] },
      status: 'approved', author: { name: 'Sam Ortiz', callsign: '1-ADAM-12' }, authorLicense: 'license:sam', createdAt: ago(60 * 24 * 4), updatedAt: ago(60 * 24 * 3), approvedBy: 'Sgt. Hale' },
    { id: 2, type: 'citation', title: 'Speeding on the Great Ocean Hwy', narrative: 'Clocked at 92 in a 65.',
      persons: [2], vehicles: [2], callId: null, charges: [{ code: '5-01', count: 1 }],
      totals: { fine: 150, jail: 0, items: [{ code: '5-01', name: 'Speeding (up to 15 over)', class: 'infraction', count: 1, fine: 150, jail: 0 }] },
      status: 'submitted', author: { name: 'Alex Mercer', callsign: '2-LINCOLN-4' }, authorLicense: 'license:me', createdAt: ago(60 * 30), updatedAt: ago(60 * 30), approvedBy: null },
    { id: 3, type: 'incident', title: 'Vandalism at Legion Square', narrative: 'Graffiti on the north wall, no suspects.',
      persons: [], vehicles: [], callId: null, charges: [], totals: null, status: 'draft',
      author: { name: 'Alex Mercer', callsign: '2-LINCOLN-4' }, authorLicense: 'license:me', createdAt: ago(90), updatedAt: ago(60), approvedBy: null },
  ];
  S.warrants = [
    { id: 1, personId: 1, charges: [{ code: '1-02', count: 1 }], totals: { fine: 2500, jail: 30, items: [{ code: '1-02', name: 'Assault with a deadly weapon', class: 'felony', count: 1, fine: 2500, jail: 30 }] },
      reason: 'Identified on CCTV in the Vinewood shooting.', status: 'active', requestedBy: { name: 'Sam Ortiz', callsign: '1-ADAM-12' },
      decidedBy: { name: 'Judge Whitfield' }, createdAt: ago(60 * 24 * 2), updatedAt: ago(60 * 24) },
    { id: 2, personId: 4, charges: [{ code: '2-01', count: 2 }], totals: { fine: 600, jail: 0, items: [{ code: '2-01', name: 'Petty theft', class: 'misdemeanor', count: 2, fine: 600, jail: 0 }] },
      reason: 'Shoplifting at the 24/7, twice.', status: 'requested', requestedBy: { name: 'Dana Brooks', callsign: 'S-14' },
      decidedBy: null, createdAt: ago(120), updatedAt: ago(120) },
  ];
  S.bolos = [
    { id: 1, kind: 'vehicle', title: 'Silver sedan from the Strawberry robbery', description: 'Silver Karin Sultan, partial plate 46E. Suspect armed.',
      plate: '46EEK572', personId: null, active: true, createdBy: { name: 'Casey Ward', callsign: 'DISPATCH-1' }, createdAt: ago(5), updatedAt: ago(5) },
    { id: 2, kind: 'person', title: 'Missing: Ava Kowalski', description: '44, brown hair, last seen in Mirror Park wearing a green coat.',
      plate: null, personId: 5, active: true, createdBy: { name: 'Riley Chen', callsign: '1-ADAM-20' }, createdAt: ago(60 * 26), updatedAt: ago(60 * 26) },
  ];

  // ------------------------------------------------------------------ shared helpers for the mocks

  S.personName = (id) => { const p = S.persons.find((x) => x.id === id); return p ? `${p.first} ${p.last}` : null; };
  S.summary = (p) => p && ({
    id: p.id, first: p.first, last: p.last, dob: p.dob, gender: p.gender, mugshot: p.mugshot, flags: p.flags, licenses: p.licenses,
    warrants: S.warrants.filter((w) => w.personId === p.id && w.status === 'active').length,
    bolo: S.bolos.some((b) => b.active && b.personId === p.id),
  });
  S.withOwner = (v) => ({ ...v, ownerName: S.personName(v.ownerId) });
  S.myUnit = () => S.units.find((u) => u.id === S.me.id) || null;
  S.meNow = () => ({ ...S.me, unit: S.myUnit() });
  S.can = (ability) => Boolean(S.me.abilities[ability]);
  S.need = (ability) => { if (!S.can(ability)) S.fail("You aren't allowed to do that."); };

  // ------------------------------------------------------------------ session and units

  M.on('session', () => ({ me: S.meNow(), config: S.config }));

  M.on('unit.signOn', ({ callsign, department }) => {
    S.need('unit.signon');
    if (!/^[A-Za-z0-9 -]{1,12}$/.test(callsign || '')) S.fail('Pick a callsign of up to 12 letters, numbers, spaces or dashes.');
    if (!S.me.departments.includes(department)) S.fail("You can't sign on with that department.");
    if (S.units.some((u) => u.id !== S.me.id && u.callsign.toUpperCase() === callsign.toUpperCase())) S.fail('Another unit already has that callsign.');
    const dept = S.config.departments.find((d) => d.key === department);
    S.units = S.units.filter((u) => u.id !== S.me.id);
    S.units.push({ id: S.me.id, name: S.me.name, callsign: callsign.toUpperCase(), department, role: dept.role, status: 'available', callId: null,
      location: loc(430, -980, 'Sinner St, Mission Row'), since: now(), signedOnAt: now() });
    setTimeout(() => CAD.push('units', S.units), 0);
    return S.meNow();
  });

  M.on('unit.signOff', () => {
    const unit = S.myUnit();
    if (unit && unit.callId) {
      const call = S.calls.find((c) => c.id === unit.callId);
      if (call) call.units = call.units.filter((id) => id !== unit.id);
    }
    S.units = S.units.filter((u) => u.id !== S.me.id);
    setTimeout(() => CAD.push('units', S.units), 0);
    return S.meNow();
  });

  M.on('unit.status', ({ status, unit }) => {
    const target = unit ? S.units.find((u) => u.id === unit) : S.myUnit();
    if (!target) S.fail(unit ? 'That unit is not on duty.' : "You aren't on duty.");
    if (unit && unit !== S.me.id) S.need('dispatch.manage');
    if (!S.config.statuses.some((s) => s.key === status)) S.fail('Unknown status.');
    target.status = status;
    target.since = now();
    setTimeout(() => CAD.push('units', S.units), 0);
    return target;
  });

  M.on('unit.list', () => { S.need('dispatch.view'); return S.units; });

  // &duty=1 starts the preview signed on (with the first department you can use).
  if (new URLSearchParams(window.location.search).get('duty') && S.me.departments.length) {
    const dept = S.config.departments.find((d) => d.key === S.me.departments[0]);
    S.units.push({ id: S.me.id, name: S.me.name, callsign: dept.role === 'dispatch' ? 'DISPATCH-2' : '2-LINCOLN-4', department: dept.key,
      role: dept.role, status: 'available', callId: null, location: loc(430, -980, 'Sinner St, Mission Row'), since: now(), signedOnAt: now() });
  }
})();
