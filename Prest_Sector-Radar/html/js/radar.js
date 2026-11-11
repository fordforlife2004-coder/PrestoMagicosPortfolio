// Prest_Sector Radar: draws the console and runs the remote. The game (client/main.lua) sends what to
// show; the remote sends changes back. Everything here is text and numbers set with textContent.

(() => {
  'use strict';

  const $ = (sel, root = document) => root.querySelector(sel);
  const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];
  const inGame = typeof window.GetParentResourceName === 'function';

  const RADAR = {
    settings: null,
    units: 'mph',
    last: null,
    // Talks to client/main.lua. The preview (demo.js) swaps this for its own.
    post: async (name, data) => {
      const res = await fetch(`https://${window.GetParentResourceName()}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data || {}),
      });
      try { return await res.json(); } catch { return null; }
    },
  };
  window.RADAR = RADAR;

  // ------------------------------------------------------------------ seven-segment digits

  // Segments a to g, as on a real display.
  const SEGMENTS = {
    a: 'M3 1h10l-2 2H5z', b: 'M14 2v10l-2-1.5V4z', c: 'M14 14v10l-2-2V15.5z', d: 'M3 25h10l-2-2H5z',
    e: 'M2 14v10l2-2V15.5z', f: 'M2 2v10l2-1.5V4z', g: 'M3 13l2-1.5h6l2 1.5-2 1.5H5z',
  };
  const GLYPHS = {
    0: 'abcdef', 1: 'bc', 2: 'abdeg', 3: 'abcdg', 4: 'bcfg', 5: 'acdfg', 6: 'acdefg', 7: 'abc', 8: 'abcdefg', 9: 'abcdfg',
    '-': 'g', ' ': '',
  };
  const SVG = 'http://www.w3.org/2000/svg';

  const makeDigits = (box, count, size) => {
    box.replaceChildren();
    const digits = [];
    for (let i = 0; i < count; i++) {
      const svg = document.createElementNS(SVG, 'svg');
      svg.setAttribute('viewBox', '0 0 16 26');
      svg.setAttribute('width', String(size * 16 / 26));
      svg.setAttribute('height', String(size));
      const segs = {};
      for (const [name, d] of Object.entries(SEGMENTS)) {
        const path = document.createElementNS(SVG, 'path');
        path.setAttribute('d', d);
        path.setAttribute('class', 'seg');
        svg.append(path);
        segs[name] = path;
      }
      box.append(svg);
      digits.push(segs);
    }
    box.digits = digits;
  };

  // Shows a number right-aligned (blank when null), or '---' when off.
  const setDigits = (box, value, off) => {
    const n = box.digits.length;
    let text;
    if (off) text = '-'.repeat(n);
    else if (value === null || value === undefined) text = ' '.repeat(n);
    else text = String(Math.max(0, Math.min(10 ** n - 1, Math.round(value)))).padStart(n, ' ');
    box.digits.forEach((segs, i) => {
      const lit = GLYPHS[text[i]] || '';
      for (const [name, path] of Object.entries(segs)) path.classList.toggle('lit', lit.includes(name));
    });
  };

  $$('.antenna').forEach((a) => {
    makeDigits($('[data-digits="target"]', a), 3, 44);
    makeDigits($('[data-digits="fast"]', a), 3, 30);
  });
  makeDigits($('[data-digits="patrol"]'), 3, 34);

  // ------------------------------------------------------------------ sounds (made here, no files)

  let audio = null;
  const tone = (freq, start, length, volume) => {
    if (!audio) audio = new (window.AudioContext || window.webkitAudioContext)();
    const osc = audio.createOscillator();
    const gain = audio.createGain();
    osc.type = 'square';
    osc.frequency.value = freq;
    const t = audio.currentTime + start;
    gain.gain.setValueAtTime(0, t);
    gain.gain.linearRampToValueAtTime(volume, t + 0.01);
    gain.gain.setValueAtTime(volume, t + length - 0.02);
    gain.gain.linearRampToValueAtTime(0, t + length);
    osc.connect(gain).connect(audio.destination);
    osc.start(t);
    osc.stop(t + length + 0.02);
  };
  const SOUNDS = {
    lock: [[1800, 0, 0.06]],
    fast: [[1200, 0, 0.12], [1200, 0.18, 0.12]],
    hit: [[880, 0, 0.16], [1320, 0.2, 0.16], [880, 0.4, 0.16], [1320, 0.6, 0.16]],
  };
  RADAR.beep = (kind, volume) => {
    try {
      const v = Math.max(0, Math.min(100, Number(volume) || 0)) / 100 * 0.12;
      if (!v) return;
      (SOUNDS[kind] || []).forEach(([f, s, l]) => tone(f, s, l, v));
    } catch (e) { /* no sound device: nothing to play */ }
  };

  // ------------------------------------------------------------------ the console

  const MODE = { same: 'Same', opp: 'Opp', both: 'Both' };
  const STATUS = { reading: 'Checking', clear: 'Clear', notice: 'Notice', hit: 'Hit' };

  const renderAntenna = (name, a) => {
    const box = $(`.antenna[data-antenna="${name}"]`);
    box.classList.toggle('off', !a.on);
    const over = Boolean(a.on && a.over);
    const hasFast = a.fast !== null && a.fast !== undefined;
    box.classList.toggle('over-fast', over && hasFast);
    box.classList.toggle('over-target', over && !hasFast);
    $('.ant-mode', box).textContent = a.on ? MODE[a.mode] || a.mode : 'Off';
    $('.lamp.lock', box).classList.toggle('on', Boolean(a.locked));
    setDigits($('[data-digits="target"]', box), a.target, !a.on);
    setDigits($('[data-digits="fast"]', box), a.fast, !a.on);
  };

  const renderCamera = (name, p) => {
    const box = $(`.camera[data-camera="${name}"]`);
    const plate = $('.plate', box);
    const text = $('.plate-text', box);
    const status = $('.cam-status', box);
    box.classList.remove('clear', 'notice', 'hit', 'reading', 'locked');
    plate.className = 'plate';
    if (!p) {
      plate.classList.add('empty');
      text.textContent = 'No read';
      status.replaceChildren();
      return;
    }
    plate.classList.add(`style-${Number(p.style) || 0}`);
    text.textContent = p.plate;
    box.classList.add(p.status || 'reading');
    box.classList.toggle('locked', Boolean(p.locked));
    const head = document.createElement('b');
    head.textContent = STATUS[p.status] || 'Checking';
    const lines = [];
    if (p.status === 'hit' || p.status === 'notice') lines.push(...(p.reasons || []));
    else if (p.status === 'clear') {
      if (p.vehicle) lines.push(p.vehicle);
      if (p.owner) lines.push(`Owner: ${p.owner}`);
      if (!p.vehicle && !p.owner) lines.push('Nothing to report.');
    }
    status.replaceChildren(head, ...lines.slice(0, 3).map((line) => {
      const span = document.createElement('span');
      span.className = 'reason';
      span.textContent = line;
      span.title = line;
      return span;
    }));
  };

  RADAR.render = (u) => {
    RADAR.last = u;
    RADAR.units = u.units || RADAR.units;
    renderAntenna('front', u.front);
    renderAntenna('rear', u.rear);
    setDigits($('[data-digits="patrol"]'), u.patrol, false);
    $('#limit').textContent = String(u.limit);
    $('#units').textContent = RADAR.units === 'kmh' ? 'km/h' : 'mph';
    $('#fastlock').classList.toggle('on', Boolean(u.fastLock));
    $('#plates').classList.toggle('off', !u.platesOn);
    renderCamera('front', u.plates && u.plates.front);
    renderCamera('rear', u.plates && u.plates.rear);
    $('#open-cad').disabled = !u.canOpenCad;
  };

  // ------------------------------------------------------------------ where the console sits

  const radar = $('#radar');
  const place = () => {
    const s = RADAR.settings;
    radar.style.setProperty('--scale', String((s && s.scale) || 1));
    if (s && s.pos) {
      radar.classList.add('placed');
      const rect = radar.getBoundingClientRect();
      const maxX = Math.max(0, window.innerWidth - rect.width);
      const maxY = Math.max(0, window.innerHeight - rect.height);
      radar.style.left = `${Math.round(Math.min(maxX, s.pos.x * window.innerWidth))}px`;
      radar.style.top = `${Math.round(Math.min(maxY, s.pos.y * window.innerHeight))}px`;
    } else {
      radar.classList.remove('placed');
      radar.style.left = '';
      radar.style.top = '';
    }
  };
  window.addEventListener('resize', place);

  let drag = null;
  radar.addEventListener('mousedown', (e) => {
    if (!document.body.classList.contains('remote-open')) return;
    const rect = radar.getBoundingClientRect();
    drag = { dx: e.clientX - rect.left, dy: e.clientY - rect.top, moved: false };
    // Pin it where it is first, so taking it out of its corner doesn't make it jump.
    radar.style.left = `${Math.round(rect.left)}px`;
    radar.style.top = `${Math.round(rect.top)}px`;
    radar.classList.add('placed', 'dragging');
    e.preventDefault();
  });
  window.addEventListener('mousemove', (e) => {
    if (!drag) return;
    drag.moved = true;
    const rect = radar.getBoundingClientRect();
    const x = Math.max(0, Math.min(window.innerWidth - rect.width, e.clientX - drag.dx));
    const y = Math.max(0, Math.min(window.innerHeight - rect.height, e.clientY - drag.dy));
    radar.style.left = `${Math.round(x)}px`;
    radar.style.top = `${Math.round(y)}px`;
  });
  window.addEventListener('mouseup', () => {
    if (!drag) return;
    const moved = drag.moved;
    drag = null;
    radar.classList.remove('dragging');
    if (!moved) {
      place(); // just a click: back where it was
      return;
    }
    const rect = radar.getBoundingClientRect();
    change({ pos: { x: rect.left / window.innerWidth, y: rect.top / window.innerHeight } });
  });

  // ------------------------------------------------------------------ the remote

  const renderSettings = () => {
    const s = RADAR.settings;
    if (!s) return;
    const get = (path) => path.split('.').reduce((o, k) => (o ? o[k] : undefined), s);
    $$('.btn.toggle[data-set]').forEach((b) => b.classList.toggle('on', Boolean(get(b.dataset.set))));
    $$('.seg[data-set]').forEach((seg) => {
      const value = get(seg.dataset.set);
      $$('button', seg).forEach((b) => b.classList.toggle('on', b.dataset.value === value));
    });
    $('#remote-limit').textContent = String(s.fastLimit);
    $('#remote-units').textContent = RADAR.units === 'kmh' ? 'km/h' : 'mph';
    $('#volume').value = String(s.volume);
    $('#volume-value').textContent = String(s.volume);
    $('#scale').value = String(s.scale);
    $('#scale-value').textContent = `${Math.round(s.scale * 100)}%`;
    place();
  };

  // Sends a change; the game answers with the settings as they now are.
  const change = async (patch) => {
    const updated = await RADAR.post('settings', patch);
    if (updated && typeof updated === 'object') {
      RADAR.settings = updated;
      renderSettings();
    }
  };

  $$('.btn.toggle[data-set]').forEach((b) => b.addEventListener('click', () => {
    const [key, sub] = b.dataset.set.split('.');
    const s = RADAR.settings;
    if (sub) change({ [key]: { ...s[key], [sub]: !s[key][sub] } });
    else change({ [key]: !s[key] });
  }));
  $$('.seg[data-set]').forEach((seg) => $$('button', seg).forEach((b) => b.addEventListener('click', () => {
    const [key, sub] = seg.dataset.set.split('.');
    change({ [key]: { ...RADAR.settings[key], [sub]: b.dataset.value } });
  })));
  $$('[data-step]').forEach((b) => b.addEventListener('click', () => {
    change({ fastLimit: RADAR.settings.fastLimit + Number(b.dataset.step) });
  }));
  $('#volume').addEventListener('input', (e) => { $('#volume-value').textContent = e.target.value; });
  $('#volume').addEventListener('change', (e) => {
    change({ volume: Number(e.target.value) });
    RADAR.beep('lock', Number(e.target.value));
  });
  $('#scale').addEventListener('input', (e) => {
    $('#scale-value').textContent = `${Math.round(Number(e.target.value) * 100)}%`;
    radar.style.setProperty('--scale', e.target.value);
  });
  $('#scale').addEventListener('change', (e) => change({ scale: Number(e.target.value) }));

  const closeRemote = () => RADAR.post('close', {});
  $$('[data-action]').forEach((b) => b.addEventListener('click', () => {
    const action = b.dataset.action;
    if (action === 'close') closeRemote();
    else if (action === 'resetPos') change({ resetPos: true });
    else RADAR.post('action', { action });
  }));
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && !$('#remote-wrap').hidden) closeRemote();
  });

  // ------------------------------------------------------------------ messages from the game

  RADAR.handle = (m) => {
    if (!m || typeof m !== 'object') return;
    if (m.type === 'show') {
      radar.hidden = !m.visible;
      if (m.visible) place();
    } else if (m.type === 'update') {
      RADAR.render(m);
    } else if (m.type === 'settings') {
      RADAR.settings = m.settings;
      if (m.units) RADAR.units = m.units;
      renderSettings();
    } else if (m.type === 'remote') {
      $('#remote-wrap').hidden = !m.open;
      document.body.classList.toggle('remote-open', Boolean(m.open));
    } else if (m.type === 'beep') {
      RADAR.beep(m.kind, m.volume);
    }
  };
  window.addEventListener('message', (e) => RADAR.handle(e.data));

  if (inGame) RADAR.post('ready', {});
})();
