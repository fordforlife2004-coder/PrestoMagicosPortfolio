'use strict';

// The ELS control panel. It only shows what the game sends; all text is set with textContent.

const POSITIONS = ['bottom-right', 'bottom-center', 'top-right'];
const $ = (id) => document.getElementById(id);

function setKey(name, on, value, bind) {
    $(`key-${name}`).classList.toggle('on', Boolean(on));
    if (value !== undefined) $(`value-${name}`).textContent = value;
    $(`bind-${name}`).textContent = bind || '';
}

function render(hud) {
    const panel = $('hud');
    panel.hidden = !hud.visible;
    if (!hud.visible) return;

    panel.className = `hud ${POSITIONS.includes(hud.position) ? hud.position : 'bottom-right'}${hud.lights ? ' lights-on' : ''}`;
    $('vehicle').textContent = hud.vehicle || '';

    const keys = hud.keys || {};
    setKey('lights', hud.lights, hud.lights ? 'On' : 'Off', keys.lights);
    setKey('siren', hud.siren, hud.siren ? 'On' : 'Off', keys.siren);
    setKey('tone', hud.siren, hud.tone || '', keys.tone);
    const hasPattern = typeof hud.pattern === 'string';
    setKey('pattern', hud.lights && hasPattern, hasPattern ? hud.pattern : 'Built-in', keys.pattern);
    $('key-pattern').classList.toggle('unused', !hasPattern);
    setKey('horn', hud.horn, hud.horn ? 'On' : 'Hold', keys.horn);
}

window.addEventListener('message', (event) => {
    const message = event.data;
    if (message && message.type === 'hud') render(message);
});
