// The browser preview: open html/index.html outside the game to see the radar with made-up traffic.
// It plays the part of client/main.lua. In the game this file does nothing.
//   ?shot=hit     hold still on a plate reader hit (for screenshots)
//   ?shot=fast    hold still on a car over the fast limit
//   ?remote=1     open the remote

(() => {
  'use strict';
  if (typeof window.GetParentResourceName === 'function') return;

  const RADAR = window.RADAR;
  const query = new URLSearchParams(window.location.search);
  const shot = query.get('shot');

  document.body.classList.add('is-preview');
  document.getElementById('preview-bar').hidden = false;

  let settings = {
    front: { on: true, mode: 'both' }, rear: { on: true, mode: 'same' }, plates: true,
    fastLimit: 75, fastLock: false, volume: 0, scale: 1,
  };
  const clamp = (n, lo, hi) => Math.max(lo, Math.min(hi, n));
  const locks = {};
  let platesLocked = false;
  let lastHit = null;

  // Plates that pass by, with what the server would say about each.
  const CARS = [
    { plate: '46EEK572', style: 0, status: 'clear', reasons: [], vehicle: 'Black Sultan', owner: 'Maria Lopez' },
    { plate: '82KQT211', style: 3, status: 'notice', reasons: ['Registration: Expired.', 'Insurance: None.'] },
    { plate: '07ABC123', style: 0, status: 'hit', reasons: ['BOLO: Robbery suspect vehicle, gray sedan', 'Owner has 1 active warrant.'] },
    { plate: '19RTX448', style: 1, status: 'clear', reasons: [], vehicle: 'White Buffalo', owner: 'Derek Shaw' },
    { plate: '3MDJ902', style: 0, status: 'clear', reasons: [], vehicle: 'Red Blista' },
  ];

  const state = { t: 0, front: null, rear: null, plates: { front: null, rear: null } };

  const antenna = (name, target, fast) => {
    const a = settings[name];
    const lock = locks[name];
    const shown = lock || { target, fast };
    const top = shown.fast || shown.target;
    return { on: a.on, mode: a.mode, locked: Boolean(lock), target: a.on ? shown.target : null,
      fast: a.on ? shown.fast : null, over: Boolean(a.on && top && top >= settings.fastLimit) };
  };

  const frame = () => {
    state.t += 1;
    const t = state.t / 5;
    let frontTarget = Math.round(52 + 6 * Math.sin(t / 3));
    let frontFast = Math.sin(t / 7) > 0.2 ? Math.round(78 + 6 * Math.sin(t / 2)) : null;
    let rearTarget = Math.round(41 + 4 * Math.cos(t / 4));
    if (shot === 'fast') { frontTarget = 54; frontFast = 87; }
    if (shot === 'hit') { frontTarget = 49; frontFast = null; }
    if (settings.fastLock && !locks.front && (frontFast || frontTarget) >= settings.fastLimit) {
      locks.front = { target: frontTarget, fast: frontFast };
    }
    if (!platesLocked) {
      const i = shot === 'hit' ? 2 : Math.floor(state.t / 25) % CARS.length;
      const j = shot === 'hit' ? 0 : (Math.floor(state.t / 25) + 3) % CARS.length;
      state.plates.front = { ...CARS[i], locked: false };
      state.plates.rear = { ...CARS[j], locked: false };
      if (CARS[i].status === 'hit') lastHit = CARS[i].plate;
    }
    RADAR.handle({
      type: 'update', units: 'mph', patrol: shot ? 47 : Math.round(47 + 3 * Math.sin(t / 5)), limit: settings.fastLimit,
      fastLock: settings.fastLock, front: antenna('front', frontTarget, frontFast), rear: antenna('rear', rearTarget, null),
      platesOn: settings.plates,
      plates: settings.plates ? { front: state.plates.front, rear: state.plates.rear } : { front: null, rear: null },
      canOpenCad: Boolean(lastHit),
    });
  };

  // What client/main.lua answers to the remote.
  RADAR.post = async (name, data) => {
    if (name === 'settings') {
      const next = { ...settings, ...data };
      if (data.resetPos) delete next.pos;
      delete next.resetPos;
      next.fastLimit = clamp(Math.round(Number(next.fastLimit) || 75), 5, 250);
      next.volume = clamp(Number(next.volume) || 0, 0, 100);
      next.scale = clamp(Number(next.scale) || 1, 0.6, 1.6);
      settings = next;
      frame();
      return settings;
    }
    if (name === 'action') {
      const a = data.action;
      if (a === 'lockFront') locks.front = locks.front ? null : { ...RADAR.last.front };
      if (a === 'lockRear') locks.rear = locks.rear ? null : { ...RADAR.last.rear };
      if (a === 'lockPlates') {
        platesLocked = !platesLocked;
        for (const p of Object.values(state.plates)) if (p) p.locked = platesLocked;
      }
      if (a === 'reset') {
        delete locks.front;
        delete locks.rear;
        platesLocked = false;
      }
      if (a === 'openCad') window.alert(`In the game this opens ${lastHit} on the Prest_Sector CAD tablet.`);
      frame();
      return {};
    }
    if (name === 'close') RADAR.handle({ type: 'remote', open: false });
    return {};
  };

  const openRemote = () => {
    RADAR.handle({ type: 'settings', settings, units: 'mph' });
    RADAR.handle({ type: 'remote', open: true });
  };
  document.getElementById('preview-remote').addEventListener('click', openRemote);

  RADAR.handle({ type: 'settings', settings, units: 'mph' });
  RADAR.handle({ type: 'show', visible: true });
  frame();
  if (!shot) setInterval(frame, 200);
  if (query.get('remote')) openRemote();
})();
