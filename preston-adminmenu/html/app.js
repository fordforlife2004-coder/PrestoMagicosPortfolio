'use strict';

// The admin menu panel. Every button sends a request through the game to the server, which checks
// permissions and does the work; this page only shows what the server sends back. All text from
// players (names, reasons, reports) is shown with textContent, never as HTML.

const RESOURCE = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'preston-adminmenu';

const TABS = [
    { id: 'players', label: 'Players', icon: 'users', show: () => true },
    { id: 'reports', label: 'Reports', icon: 'flag', show: (p) => p.reports },
    { id: 'bans', label: 'Bans', icon: 'ban', show: (p) => p.ban || p.unban },
    { id: 'self', label: 'Self & vehicle', icon: 'bolt', show: (p) => p.noclip || p.god || p.invisible || p.teleport || p.vehicle || p.spectate },
    { id: 'server', label: 'Announce', icon: 'megaphone', show: (p) => p.announce },
    { id: 'logs', label: 'Logs', icon: 'list', show: (p) => p.logs },
];

const ICONS = {
    users: 'M16 8a4 4 0 1 1-8 0 4 4 0 0 1 8 0zM4 21a8 8 0 0 1 16 0',
    flag: 'M5 21V4m0 0h12l-2.5 4.5L17 13H5',
    ban: 'M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18zM5.6 5.6l12.8 12.8',
    bolt: 'M13 2 4 14h7l-1 8 9-12h-7z',
    megaphone: 'M3 10v4h4l6 4V6l-6 4H3zm14-2a5 5 0 0 1 0 8',
    list: 'M8 6h13M8 12h13M8 18h13M3 6h.01M3 12h.01M3 18h.01',
    pin: 'M12 21s-7-6.2-7-11a7 7 0 0 1 14 0c0 4.8-7 11-7 11zm0-8a3 3 0 1 0 0-6 3 3 0 0 0 0 6z',
    magnet: 'M6 3v8a6 6 0 0 0 12 0V3h-4v8a2 2 0 0 1-4 0V3zM6 7h4m4 0h4',
    undo: 'M9 14 4 9l5-5M4 9h11a5 5 0 0 1 0 10h-3',
    eye: 'M2 12s3.6-7 10-7 10 7 10 7-3.6 7-10 7S2 12 2 12zm10 3a3 3 0 1 0 0-6 3 3 0 0 0 0 6z',
    snow: 'M12 2v20M4.9 4.9l14.2 14.2M2 12h20M4.9 19.1 19.1 4.9',
    heart: 'M20.8 5.6a5.5 5.5 0 0 0-7.8 0L12 6.7l-1-1.1a5.5 5.5 0 0 0-7.8 7.8L12 22l8.8-8.6a5.5 5.5 0 0 0 0-7.8z',
    alert: 'M12 9v4m0 4h.01M10.3 3.9 1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z',
    door: 'M14 3h5v18h-5M10 17l5-5-5-5M15 12H3',
    copy: 'M9 9h11v11H9zM5 15H4V4h11v1',
    car: 'M5 17h14M3 13l2-6h14l2 6v4H3zm4 4v2m10-2v2M7 13h.01M17 13h.01',
    wrench: 'M14.7 6.3a4 4 0 0 0 5 5L22 14l-8 8-2.3-2.3a4 4 0 0 0-5-5L2 10l8-8z',
    trash: 'M3 6h18M8 6V4h8v2m-9 0 1 15h8l1-15',
    send: 'M22 2 11 13M22 2l-7 20-4-9-9-4z',
};

const S = {
    me: null,
    perms: {},
    tab: 'players',
    players: [],
    selectedId: null,
    filter: '',
    reports: [],
    bans: { active: [], recentlyLeft: [] },
    banFilter: '',
    logs: [],
    logFilter: '',
    modes: {},
    spectating: false,
    clockOffset: 0,
    timer: null,
    announceDraft: '',
    vehicleModel: '',
};

const $ = (selector) => document.querySelector(selector);

// ------------------------------------------------------------ helpers

function el(tag, props = {}, ...children) {
    const node = document.createElement(tag);
    for (const [key, value] of Object.entries(props)) {
        if (value === undefined || value === null || value === false) continue;
        if (key === 'class') node.className = value;
        else if (key === 'text') node.textContent = value;
        else if (key === 'value') node.value = value;
        else if (key.startsWith('on')) node.addEventListener(key.slice(2), value);
        else node.setAttribute(key, value === true ? '' : value);
    }
    for (const child of children.flat()) {
        if (child === null || child === undefined || child === false) continue;
        node.append(child instanceof Node ? child : document.createTextNode(String(child)));
    }
    return node;
}

function icon(name) {
    const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    svg.setAttribute('viewBox', '0 0 24 24');
    svg.setAttribute('class', 'icon');
    svg.setAttribute('aria-hidden', 'true');
    const path = document.createElementNS(svg.namespaceURI, 'path');
    path.setAttribute('d', ICONS[name] || '');
    svg.append(path);
    return svg;
}

function button(label, onclick, { kind = '', iconName, small, disabled, title } = {}) {
    return el('button', {
        type: 'button',
        class: ['btn', kind, small && 'small'].filter(Boolean).join(' '),
        onclick,
        disabled,
        title,
    }, iconName && icon(iconName), label);
}

const serverNow = () => Date.now() / 1000 + S.clockOffset;

function ago(time) {
    if (!time) return '';
    const s = Math.max(0, serverNow() - time);
    if (s < 60) return 'just now';
    if (s < 3600) return `${Math.floor(s / 60)}m ago`;
    if (s < 86400) return `${Math.floor(s / 3600)}h ago`;
    return `${Math.floor(s / 86400)}d ago`;
}

function duration(time) {
    if (!time) return '';
    const s = Math.max(0, serverNow() - time);
    const h = Math.floor(s / 3600);
    const m = Math.floor((s % 3600) / 60);
    return h > 0 ? `${h}h ${m}m` : `${m}m`;
}

function clock(time) {
    return new Date(time * 1000).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
}

function pingClass(ping) {
    if (ping < 80) return 'ping-good';
    if (ping < 160) return 'ping-ok';
    return 'ping-bad';
}

function copy(text) {
    const area = el('textarea', { class: 'clip' });
    area.value = text;
    document.body.append(area);
    area.select();
    document.execCommand('copy');
    area.remove();
    toast('Copied.', 'success');
}

// ------------------------------------------------------------ talking to the game

async function post(name, body) {
    try {
        const response = await fetch(`https://${RESOURCE}/${name}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(body || {}),
        });
        return await response.json();
    } catch (err) {
        return { ok: false, data: 'The game did not answer.' };
    }
}

// Runs an action and shows the server's message. Returns the data, or null when it failed.
async function act(action, payload = {}, { quiet = false, quietErrors = false } = {}) {
    const result = await post('action', { action, payload });
    if (!result || !result.ok) {
        if (!quietErrors) toast((result && result.data) || 'Something went wrong.', 'danger');
        return null;
    }
    if (!quiet && typeof result.data === 'string') toast(result.data, 'success');
    return result.data === undefined ? true : result.data;
}

function closeMenu() {
    hide();
    post('close');
}

// ------------------------------------------------------------ toasts and overlays

function toast(message, tone = 'info') {
    if (!message) return;
    const box = $('#toasts');
    while (box.children.length >= 5) box.firstChild.remove();
    const node = el('div', { class: `toast ${tone}` }, el('span', { text: message }));
    box.append(node);
    setTimeout(() => node.classList.add('leaving'), 4200);
    setTimeout(() => node.remove(), 4600);
}

const announcements = [];
let announcing = false;

function showAnnouncement(message) {
    announcements.push(message);
    if (!announcing) nextAnnouncement();
}

function nextAnnouncement() {
    const next = announcements.shift();
    if (!next) {
        announcing = false;
        $('#announcement').hidden = true;
        return;
    }
    announcing = true;
    $('#announcement-text').textContent = next.message;
    $('#announcement-by').textContent = next.by ? `From ${next.by}` : '';
    $('#announcement').hidden = false;
    setTimeout(nextAnnouncement, 10000);
}

const warnings = [];

function showWarning(message) {
    warnings.push(message);
    if (warnings.length === 1) renderWarning();
}

function renderWarning() {
    const current = warnings[0];
    $('#warning').hidden = !current;
    if (!current) return;
    $('#warning-text').textContent = current.message;
    $('#warning-by').textContent = current.by ? `Warned by ${current.by}` : '';
}

$('#warning-ok').addEventListener('click', () => {
    warnings.shift();
    post('warnSeen');
    renderWarning();
});

function setSpectate(message) {
    S.spectating = message.active ? message.name : false;
    $('#spectate-name').textContent = message.name || '';
    $('#spectate-hint').hidden = !message.active;
    if (!$('#app').hidden && S.tab === 'self') renderView();
}

// ------------------------------------------------------------ modal

function modalOpen() {
    return !$('#backdrop').hidden;
}

function closeModal() {
    $('#backdrop').hidden = true;
    $('#modal').replaceChildren();
}

// fields: [{ name, label, type: 'text' | 'textarea' | 'select', options, placeholder, maxlength }]
// onSubmit(values) returns true to close, or false to keep the modal open (the action showed an error).
function modal({ title, text, fields = [], confirmLabel = 'Confirm', kind = 'primary', onSubmit }) {
    const form = $('#modal');
    const error = el('div', { class: 'modal-error' });
    const inputs = {};
    const fieldNodes = fields.map((f) => {
        let input;
        if (f.type === 'select') {
            input = el('select', { class: 'select', name: f.name },
                f.options.map((o) => el('option', { value: o.value, text: o.label })));
            if (f.value) input.value = f.value;
        } else if (f.type === 'textarea') {
            input = el('textarea', { class: 'textarea', name: f.name, placeholder: f.placeholder, maxlength: f.maxlength });
        } else {
            input = el('input', { class: 'input', name: f.name, placeholder: f.placeholder, maxlength: f.maxlength });
        }
        inputs[f.name] = input;
        return el('div', { class: 'field' }, el('label', { text: f.label }), input);
    });
    const submit = el('button', { type: 'submit', class: `btn ${kind}`, text: confirmLabel });
    form.replaceChildren(
        el('h2', { text: title }),
        text && el('p', { text }),
        ...fieldNodes,
        error,
        el('div', { class: 'modal-actions' },
            button('Cancel', closeModal),
            submit),
    );
    form.onsubmit = async (event) => {
        event.preventDefault();
        const values = {};
        for (const [name, input] of Object.entries(inputs)) values[name] = input.value.trim();
        for (const f of fields) {
            if (f.minLength && values[f.name].length < f.minLength) {
                error.textContent = `${f.label} needs at least ${f.minLength} characters.`;
                inputs[f.name].focus();
                return;
            }
        }
        submit.disabled = true;
        const done = await onSubmit(values);
        submit.disabled = false;
        if (done !== false) closeModal();
    };
    $('#backdrop').hidden = false;
    const first = Object.values(inputs)[0];
    (first || submit).focus();
}

const reasonField = { name: 'reason', label: 'Reason', type: 'textarea', placeholder: 'What did they do? The player sees this.', maxlength: 200, minLength: 3 };

function banDurationField() {
    return {
        name: 'duration',
        label: 'How long',
        type: 'select',
        options: S.me.banDurations || [],
        value: (S.me.banDurations || [])[1] && S.me.banDurations[1].value,
    };
}

// ------------------------------------------------------------ open, close, load

function open(me) {
    S.me = me;
    S.perms = me.perms || {};
    S.modes = Array.isArray(me.modes) ? {} : (me.modes || {});
    S.spectating = me.spectating || false;
    S.clockOffset = (me.serverTime || Date.now() / 1000) - Date.now() / 1000;
    if (!TABS.some((t) => t.id === S.tab && t.show(S.perms))) S.tab = 'players';
    $('#app').hidden = false;
    renderTabs();
    renderMe();
    switchTab(S.tab);
    clearInterval(S.timer);
    S.timer = setInterval(refreshInBackground, 4000);
}

function hide() {
    $('#app').hidden = true;
    closeModal();
    clearInterval(S.timer);
}

function refreshInBackground() {
    if ($('#app').hidden || modalOpen()) return;
    if (['players', 'reports', 'bans', 'logs'].includes(S.tab)) load(S.tab, true);
    if (S.perms.reports && S.tab !== 'reports') loadReportCount();
}

async function loadReportCount() {
    const reports = await act('reports', {}, { quiet: true, quietErrors: true });
    if (reports) {
        S.reports = reports;
        renderTabs();
    }
}

async function load(tab, background = false) {
    const opts = { quiet: true, quietErrors: background };
    if (tab === 'players') {
        const players = await act('players', {}, opts);
        if (players) S.players = players;
    } else if (tab === 'reports') {
        const reports = await act('reports', {}, opts);
        if (reports) S.reports = reports;
        renderTabs();
    } else if (tab === 'bans') {
        const bans = await act('bans', {}, opts);
        if (bans) S.bans = { active: bans.active || [], recentlyLeft: bans.recentlyLeft || [] };
    } else if (tab === 'logs') {
        const logs = await act('logs', {}, opts);
        if (logs) S.logs = logs;
    }
    if (tab === S.tab && !$('#app').hidden) renderView();
}

function switchTab(id) {
    S.tab = id;
    renderTabs();
    renderView();
    load(id);
}

// ------------------------------------------------------------ chrome

function openReportCount() {
    if (S.reports.length) return S.reports.filter((r) => r.status !== 'closed').length;
    return S.me.openReports || 0;
}

function renderTabs() {
    const nav = $('#tabs');
    nav.replaceChildren(...TABS.filter((t) => t.show(S.perms)).map((t) => {
        const count = t.id === 'reports' ? openReportCount() : 0;
        return el('button', {
            type: 'button',
            class: `tab${S.tab === t.id ? ' active' : ''}`,
            onclick: () => switchTab(t.id),
        }, icon(t.icon), t.label, count > 0 && el('span', { class: 'badge accent', text: count }));
    }));
    const tab = TABS.find((t) => t.id === S.tab);
    $('#title').textContent = tab ? tab.label : '';
    $('#head-meta').textContent = S.tab === 'players' ? `${S.players.length || S.me.playerCount || 0} online` : '';
}

function renderMe() {
    $('#me').replaceChildren(
        el('div', {}, 'Signed in as ', el('strong', { text: S.me.name })),
        el('div', { text: `Server ID ${S.me.id} · Bans saved in ${S.me.storage === 'oxmysql' ? 'MySQL' : 'server storage'}` }),
        el('div', {}, 'Close with ', el('kbd', { text: 'Esc' })),
    );
}

// Re-rendering replaces the view, so keep the cursor in whichever search box had it.
function renderView() {
    const active = document.activeElement;
    const focusKey = active && active.dataset ? active.dataset.focus : null;
    const caret = focusKey ? active.selectionStart : null;
    const view = $('#view');
    const scroll = view.scrollTop;
    const views = { players: viewPlayers, reports: viewReports, bans: viewBans, self: viewSelf, server: viewServer, logs: viewLogs };
    view.replaceChildren((views[S.tab] || viewPlayers)());
    view.scrollTop = scroll;
    renderTabs();
    if (focusKey) {
        const again = view.querySelector(`[data-focus="${focusKey}"]`);
        if (again) {
            again.focus();
            if (caret !== null) again.setSelectionRange(caret, caret);
        }
    }
}

function searchBox(key, value, placeholder, onChange) {
    return el('input', {
        class: 'input',
        placeholder,
        value,
        'data-focus': key,
        oninput: (event) => {
            onChange(event.target.value);
            renderView();
        },
    });
}

// ------------------------------------------------------------ players

function viewPlayers() {
    const query = S.filter.trim().toLowerCase();
    const list = S.players.filter((p) => !query || String(p.id) === query || (p.name || '').toLowerCase().includes(query));
    if (S.selectedId === null && list.length) S.selectedId = list[0].id;
    const selected = S.players.find((p) => p.id === S.selectedId);

    const rows = list.length
        ? list.map((p) => el('button', {
            type: 'button',
            class: `player${p.id === S.selectedId ? ' selected' : ''}`,
            onclick: () => { S.selectedId = p.id; renderView(); },
        },
        el('span', { class: 'player-id', text: p.id }),
        el('span', { class: 'player-name', text: p.name }),
        p.frozen && el('span', { class: 'badge info', text: 'Frozen' }),
        p.staff && el('span', { class: 'badge accent', text: 'Staff' }),
        el('span', { class: `player-ping ${pingClass(p.ping)}`, text: `${p.ping}ms` })))
        : [el('div', { class: 'empty', text: query ? 'No players match that search.' : 'No players online.' })];

    return el('div', { class: 'players' },
        el('div', { class: 'player-list' },
            searchBox('players', S.filter, 'Search by name or server ID', (v) => { S.filter = v; S.selectedId = null; }),
            el('div', { class: 'scroll' }, rows)),
        el('div', { class: 'detail' }, selected ? playerDetail(selected) : el('div', { class: 'empty', text: 'Pick a player to see what you can do.' })));
}

function playerDetail(p) {
    const can = S.perms;
    const isMe = p.id === S.me.id;
    const refresh = () => load('players');

    const moveButtons = [
        can.teleport && !isMe && button('Go to player', () => act('gotoPlayer', { target: p.id }), { iconName: 'pin' }),
        can.bring && !isMe && button('Bring here', () => act('bring', { target: p.id }), { iconName: 'magnet' }),
        can.bring && button('Send back', () => act('sendBack', { target: p.id }), { iconName: 'undo', title: 'Return them to where they were before a bring or teleport' }),
        can.spectate && !isMe && button('Spectate', () => act('spectate', { target: p.id }), { iconName: 'eye' }),
    ].filter(Boolean);

    const playerButtons = [
        can.freeze && button(p.frozen ? 'Unfreeze' : 'Freeze', async () => {
            if (await act('freeze', { target: p.id, enabled: !p.frozen })) refresh();
        }, { iconName: 'snow' }),
        can.heal && button('Heal / revive', () => act('heal', { target: p.id }), { iconName: 'heart' }),
    ].filter(Boolean);

    const moderationButtons = [
        can.warn && button('Warn', () => modal({
            title: `Warn ${p.name}`,
            text: 'They see this on their screen and must click "I understand".',
            fields: [{ name: 'message', label: 'Warning', type: 'textarea', placeholder: 'Stop ramming other players.', maxlength: 200, minLength: 3 }],
            confirmLabel: 'Send warning',
            kind: 'primary',
            onSubmit: async (v) => Boolean(await act('warn', { target: p.id, message: v.message })),
        }), { kind: 'warn', iconName: 'alert' }),
        can.kick && !isMe && button('Kick', () => modal({
            title: `Kick ${p.name}`,
            text: 'They are removed from the server and can join again.',
            fields: [reasonField],
            confirmLabel: 'Kick player',
            kind: 'danger',
            onSubmit: async (v) => {
                const ok = await act('kick', { target: p.id, reason: v.reason });
                if (ok) refresh();
                return Boolean(ok);
            },
        }), { kind: 'ghost-danger', iconName: 'door' }),
        can.ban && !isMe && button('Ban', () => modal({
            title: `Ban ${p.name}`,
            text: 'Banned on their license, Discord, Steam and hardware IDs, so changing their name will not get around it.',
            fields: [reasonField, banDurationField()],
            confirmLabel: 'Ban player',
            kind: 'danger',
            onSubmit: async (v) => {
                const ok = await act('ban', { target: p.id, reason: v.reason, duration: v.duration });
                if (ok) refresh();
                return Boolean(ok);
            },
        }), { kind: 'danger', iconName: 'ban' }),
    ].filter(Boolean);

    const group = (title, buttons) => buttons.length > 0 && el('div', { class: 'card' },
        el('div', { class: 'section-title', text: title }),
        el('div', { class: 'actions' }, buttons));

    const ids = p.identifiers && p.identifiers.length > 0 && el('div', { class: 'card' },
        el('div', { class: 'section-title', text: 'Identifiers' }),
        el('div', { class: 'ids' }, p.identifiers.map((id) => {
            const split = id.indexOf(':');
            return el('div', { class: 'id-row' },
                el('span', { class: 'id-kind', text: id.slice(0, split) }),
                el('span', { class: 'id-value mono', text: id.slice(split + 1), title: id }),
                button('Copy', () => copy(id), { small: true, iconName: 'copy' }));
        })));

    return el('div', { class: 'stack' },
        el('div', { class: 'detail-head' },
            el('div', { class: 'avatar', text: (p.name || '?').trim().charAt(0).toUpperCase() || '?' }),
            el('div', {},
                el('div', { class: 'detail-name' }, p.name,
                    isMe && el('span', { class: 'badge', text: 'You' }),
                    p.staff && el('span', { class: 'badge accent', text: 'Staff' }),
                    p.frozen && el('span', { class: 'badge info', text: 'Frozen' })),
                el('div', { class: 'detail-meta', text: `Server ID ${p.id} · ${p.ping}ms ping${p.joinedAt ? ` · online ${duration(p.joinedAt)}` : ''}` }))),
        group('Move', moveButtons),
        group('Player', playerButtons),
        group('Moderation', moderationButtons),
        ids);
}

// ------------------------------------------------------------ reports

const REPORT_STATUS = { open: ['Open', 'warn'], claimed: ['Claimed', 'info'], closed: ['Closed', ''] };

function viewReports() {
    if (!S.reports.length) {
        return el('div', { class: 'empty', text: 'No reports yet. Players send them with /report followed by a message.' });
    }
    const after = () => load('reports');
    return el('div', { class: 'list' }, S.reports.map((r) => {
        const [label, tone] = REPORT_STATUS[r.status] || ['?', ''];
        return el('div', { class: `report${r.status === 'closed' ? ' closed' : ''}` },
            el('div', { class: 'report-top' },
                el('span', { class: 'report-title', text: `#${r.id} · ${r.reporterName}` }),
                el('span', { class: `badge ${tone}`, text: label }),
                !r.online && el('span', { class: 'badge', text: 'Left the server' }),
                el('span', { class: 'muted', text: `${ago(r.createdAt)}${r.claimedBy ? ` · ${r.claimedBy}` : ''}` })),
            el('div', { class: 'report-message', text: r.message }),
            el('div', { class: 'report-actions' },
                r.status === 'open' && button('Claim', async () => { if (await act('reportClaim', { id: r.id })) after(); }, { small: true, kind: 'primary' }),
                r.status !== 'closed' && r.online && S.perms.teleport && button('Go to', () => act('reportGoto', { id: r.id }), { small: true, iconName: 'pin' }),
                r.status !== 'closed' && button('Close', async () => { if (await act('reportClose', { id: r.id })) after(); }, { small: true })));
    }));
}

// ------------------------------------------------------------ bans

function viewBans() {
    const query = S.banFilter.trim().toLowerCase();
    const active = S.bans.active.filter((b) => !query
        || String(b.id) === query.replace('#', '')
        || (b.name || '').toLowerCase().includes(query)
        || (b.reason || '').toLowerCase().includes(query));
    const after = () => load('bans');

    const activeTable = active.length
        ? el('table', { class: 'table' },
            el('thead', {}, el('tr', {},
                el('th', { text: 'Ban' }), el('th', { text: 'Player' }), el('th', { text: 'Reason' }),
                el('th', { text: 'By' }), el('th', { text: 'Ends' }), el('th', {}))),
            el('tbody', {}, active.map((b) => el('tr', {},
                el('td', { class: 'num', text: `#${b.id}` }),
                el('td', {}, el('div', { text: b.name }), el('div', { class: 'muted', text: ago(b.createdAt) })),
                el('td', { class: 'reason', text: b.reason }),
                el('td', { class: 'muted', text: b.bannedBy }),
                el('td', {}, el('span', { class: `badge ${b.remaining === 'Permanent' ? 'danger' : 'warn'}`, text: b.remaining })),
                el('td', { class: 'right' }, S.perms.unban && button('Unban', () => modal({
                    title: `Unban ${b.name}?`,
                    text: `Ban #${b.id}: ${b.reason}`,
                    confirmLabel: 'Unban',
                    onSubmit: async () => {
                        const ok = await act('unban', { id: b.id });
                        if (ok) after();
                        return Boolean(ok);
                    },
                }), { small: true }))))))
        : el('div', { class: 'empty', text: query ? 'No bans match that search.' : 'No active bans.' });

    const left = S.bans.recentlyLeft;
    const leftTable = left.length
        ? el('table', { class: 'table' },
            el('thead', {}, el('tr', {}, el('th', { text: 'Player' }), el('th', { text: 'Left' }), el('th', { text: 'Why' }), el('th', {}))),
            el('tbody', {}, left.map((l) => el('tr', {},
                el('td', { text: l.name }),
                el('td', { class: 'muted', text: ago(l.leftAt) }),
                el('td', { class: 'reason muted', text: l.reason || '' }),
                el('td', { class: 'right' }, button('Ban', () => modal({
                    title: `Ban ${l.name}`,
                    text: 'They left the server, but their IDs were kept for a while so they can still be banned.',
                    fields: [reasonField, banDurationField()],
                    confirmLabel: 'Ban player',
                    kind: 'danger',
                    onSubmit: async (v) => {
                        const ok = await act('banRecent', { leftId: l.id, reason: v.reason, duration: v.duration });
                        if (ok) after();
                        return Boolean(ok);
                    },
                }), { small: true, kind: 'ghost-danger' }))))))
        : el('div', { class: 'empty', text: 'Nobody has left since the server started.' });

    return el('div', { class: 'stack' },
        el('div', { class: 'card' },
            el('div', { class: 'row', style: 'justify-content: space-between; margin-bottom: 12px;' },
                el('h2', { text: `Active bans (${S.bans.active.length})` }),
                el('div', { style: 'width: 260px;' }, searchBox('bans', S.banFilter, 'Search name, reason or ban ID', (v) => { S.banFilter = v; }))),
            activeTable),
        S.perms.ban && el('div', { class: 'card' },
            el('h2', { text: 'Recently left' }),
            el('p', { class: 'hint', text: 'The last 30 players who left. Ban someone who quit before you could act.' }),
            leftTable));
}

// ------------------------------------------------------------ self & vehicle

const MODE_INFO = {
    noclip: ['Noclip', 'Fly through walls. W A S D to move, Space and Ctrl for up and down, Shift faster, Alt slower.'],
    god: ['God mode', 'You can\'t be hurt or killed.'],
    invisible: ['Invisible', 'Other players can\'t see you. You see yourself see-through.'],
};

function viewSelf() {
    const can = S.perms;
    const modes = Object.keys(MODE_INFO).filter((m) => can[m]);

    const modeCard = modes.length > 0 && el('div', { class: 'card' },
        el('h2', { text: 'Admin modes' }),
        el('p', { class: 'hint', text: 'Switched on by the server, so cheats can\'t fake them. Each change is logged.' }),
        modes.map((mode) => {
            const [title, sub] = MODE_INFO[mode];
            const on = S.modes[mode] === true;
            return el('button', {
                type: 'button',
                class: `toggle${on ? ' on' : ''}`,
                onclick: async () => {
                    const result = await act('setMode', { mode, enabled: !on }, { quiet: true });
                    if (result !== null) {
                        S.modes[mode] = result === true;
                        renderView();
                    }
                },
            }, el('div', { class: 'toggle-text' }, el('div', { class: 'toggle-title', text: title }), el('div', { class: 'toggle-sub', text: sub })),
            el('span', { class: 'switch' }));
        }));

    const spectateCard = S.spectating && el('div', { class: 'card' },
        el('h2', { text: `Spectating ${S.spectating}` }),
        el('p', { class: 'hint', text: 'You are hidden and frozen near them. Stop to go back to where you were.' }),
        button('Stop spectating', () => act('stopSpectate'), { kind: 'primary', iconName: 'eye' }));

    const teleportCard = can.teleport && el('div', { class: 'card' },
        el('h2', { text: 'Teleport' }),
        el('p', { class: 'hint', text: 'Set a waypoint on the map first. "Go back" returns you to where you were before your last teleport.' }),
        el('div', { class: 'row' },
            button('Teleport to waypoint', () => act('teleportWaypoint'), { kind: 'primary', iconName: 'pin' }),
            button('Go back', () => act('goBack'), { iconName: 'undo' })));

    const spawn = async () => {
        if (!S.vehicleModel.trim()) return toast('Type a model name first, like adder or police3.', 'warn');
        await act('spawnVehicle', { model: S.vehicleModel.trim() });
    };
    const vehicleCard = can.vehicle && el('div', { class: 'card' },
        el('h2', { text: 'Vehicle' }),
        el('p', { class: 'hint', text: 'Spawned by the server and put in your name. Fix, flip, clean and delete work on the vehicle you are in or next to.' }),
        el('div', { class: 'row', style: 'flex-wrap: nowrap; margin-bottom: 12px;' },
            el('input', {
                class: 'input',
                placeholder: 'Model name, like adder',
                value: S.vehicleModel,
                maxlength: 32,
                'data-focus': 'vehicle',
                oninput: (e) => { S.vehicleModel = e.target.value; },
                onkeydown: (e) => { if (e.key === 'Enter') spawn(); },
            }),
            button('Spawn', spawn, { kind: 'primary', iconName: 'car' })),
        el('div', { class: 'row' },
            button('Fix', () => act('vehicleAction', { action: 'fix' }), { iconName: 'wrench' }),
            button('Flip', () => act('vehicleAction', { action: 'flip' }), { iconName: 'undo' }),
            button('Clean', () => act('vehicleAction', { action: 'clean' })),
            button('Delete', () => act('deleteVehicle'), { kind: 'ghost-danger', iconName: 'trash' })));

    return el('div', { class: 'stack' },
        spectateCard,
        el('div', { class: 'grid-2' },
            el('div', { class: 'stack' }, modeCard),
            el('div', { class: 'stack' }, teleportCard, vehicleCard)));
}

// ------------------------------------------------------------ announce

function viewServer() {
    const counter = el('div', { class: 'counter', text: `${S.announceDraft.length} / 300` });
    const previewText = el('div', { class: 'announcement-text', text: S.announceDraft || 'Your message appears here.' });
    const area = el('textarea', {
        class: 'textarea',
        maxlength: 300,
        placeholder: 'Server restart in 10 minutes. Finish what you are doing.',
        value: S.announceDraft,
        'data-focus': 'announce',
        oninput: (e) => {
            S.announceDraft = e.target.value;
            counter.textContent = `${S.announceDraft.length} / 300`;
            previewText.textContent = S.announceDraft || 'Your message appears here.';
        },
    });
    const send = () => {
        const message = S.announceDraft.trim();
        if (message.length < 2) return toast('Write the announcement first.', 'warn');
        modal({
            title: 'Send to everyone?',
            text: `Every player online (${S.players.length || S.me.playerCount}) sees this at the top of their screen for 10 seconds.`,
            confirmLabel: 'Send announcement',
            onSubmit: async () => {
                const ok = await act('announce', { message });
                if (ok) {
                    S.announceDraft = '';
                    renderView();
                }
                return Boolean(ok);
            },
        });
    };
    return el('div', { class: 'card', style: 'max-width: 640px;' },
        el('h2', { text: 'Server announcement' }),
        el('p', { class: 'hint', text: 'Shown to every player as a banner, with a sound.' }),
        area,
        counter,
        el('div', { class: 'preview' },
            el('div', { class: 'announcement-label', text: 'Preview' }),
            previewText,
            el('div', { class: 'announcement-by', text: `From ${S.me.name}` })),
        el('div', { class: 'row', style: 'justify-content: flex-end; margin-top: 14px;' },
            button('Send to everyone', send, { kind: 'primary', iconName: 'send' })));
}

// ------------------------------------------------------------ logs

function viewLogs() {
    const query = S.logFilter.trim().toLowerCase();
    const logs = S.logs.filter((l) => !query || [l.actor, l.action, l.target, l.detail].some((v) => (v || '').toLowerCase().includes(query)));
    return el('div', { class: 'card' },
        el('div', { class: 'row', style: 'justify-content: space-between; margin-bottom: 12px;' },
            el('h2', { text: 'Recent actions' }),
            el('div', { style: 'width: 280px;' }, searchBox('logs', S.logFilter, 'Search by admin, player or action', (v) => { S.logFilter = v; }))),
        logs.length
            ? el('table', { class: 'table' },
                el('thead', {}, el('tr', {}, el('th', {}), el('th', { text: 'Time' }), el('th', { text: 'By' }), el('th', { text: 'Action' }), el('th', { text: 'Player' }), el('th', { text: 'Details' }))),
                el('tbody', {}, logs.map((l) => el('tr', {},
                    el('td', {}, el('span', { class: `log-tone ${l.tone || 'info'}` })),
                    el('td', { class: 'num', text: clock(l.time) }),
                    el('td', { text: l.actor }),
                    el('td', { text: l.action }),
                    el('td', { class: 'muted', text: l.target || '' }),
                    el('td', { class: 'reason muted', text: l.detail || '' })))))
            : el('div', { class: 'empty', text: query ? 'Nothing matches that search.' : 'No actions yet since the server started.' }),
        el('p', { class: 'hint', style: 'margin: 12px 0 0;', text: 'The last 200 actions. Set preston_admin_webhook in server.cfg to keep them in Discord too.' }));
}

// ------------------------------------------------------------ events

$('#close').addEventListener('click', closeMenu);
$('#backdrop').addEventListener('mousedown', (event) => { if (event.target === $('#backdrop')) closeModal(); });

document.addEventListener('keydown', (event) => {
    if (event.key !== 'Escape') return;
    if (!$('#warning').hidden) return;
    if (modalOpen()) return closeModal();
    if (!$('#app').hidden) closeMenu();
});

window.addEventListener('message', (event) => {
    const message = event.data;
    if (!message || typeof message !== 'object') return;
    switch (message.type) {
        case 'open': open(message.state); break;
        case 'close': hide(); break;
        case 'toast': toast(message.message, message.tone); break;
        case 'warn': showWarning(message); break;
        case 'announce': showAnnouncement(message); break;
        case 'spectate': setSpectate(message); break;
        case 'modes':
            S.modes = Array.isArray(message.modes) ? {} : (message.modes || {});
            if (!$('#app').hidden && S.tab === 'self') renderView();
            break;
        default: break;
    }
});
