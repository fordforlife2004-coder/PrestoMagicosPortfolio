'use strict';
// Warrants: asked for by police, approved or denied by a judge or supervisor, served by police and
// recalled by a judge. Each status has its own tab, and only the moves you're allowed show as buttons.

(() => {
  const { h } = CAD;
  const R = CAD.rec;
  const STATUSES = [
    { key: 'requested', label: 'Waiting for approval' }, { key: 'active', label: 'Active' }, { key: 'served', label: 'Served' },
    { key: 'recalled', label: 'Recalled' }, { key: 'denied', label: 'Denied' },
  ];
  // The moves from each status: [new status, button label, ability, button kind].
  const MOVES = {
    requested: [['active', 'Approve', 'warrants.approve', 'primary'], ['denied', 'Deny', 'warrants.approve', 'danger']],
    active: [['served', 'Mark served', 'warrants.request', 'primary'], ['recalled', 'Recall', 'warrants.approve', 'danger']],
  };
  const view = { tab: 'active' };

  const requestForm = async (personId, after) => {
    let person = personId ? (await CAD.rpc('person.get', { id: personId })).summary : null;
    const who = h('div', { class: 'row rec-owner-pick' });
    const drawWho = () => who.replaceChildren(person ? R.personLine(person) : h('span', { class: 'muted' }, 'Nobody picked'), h('span', { class: 'spacer' }),
      CAD.button(person ? 'Change' : 'Pick person', CAD.run(async () => { const s = await CAD.pick.person(); if (s) { person = s; drawWho(); } }),
        { small: true, icon: 'search' }));
    drawWho();
    const charges = CAD.chargesEditor([]);
    const reason = CAD.textarea({ maxlength: 1000, rows: 4, placeholder: 'What they did, and the evidence for it' });
    const needs = CAD.state.config.warrantsNeedApproval && !CAD.can('warrants.approve');
    CAD.modal({
      title: 'Request a warrant', wide: true,
      body: h('div', { class: 'form' }, CAD.field('Person', who), CAD.field('Charges', charges.node), CAD.field('Reason', reason),
        h('p', { class: 'muted' }, needs ? 'A judge or supervisor has to approve it before it is active.' : 'It is active as soon as you save it.')),
      actions: [{ label: 'Cancel' }, {
        label: needs ? 'Send for approval' : 'Issue warrant', kind: 'primary',
        onClick: async () => {
          if (!person) throw new Error('Pick the person first.');
          const w = await CAD.rpc('warrant.save', { warrant: { personId: person.id, charges: charges.value(), reason: reason.value } });
          CAD.toast(w.status === 'active' ? 'Warrant issued.' : 'Warrant sent for approval.', 'success');
          view.tab = w.status;
          after();
        },
      }],
    });
  };

  const card = (w, again) => {
    const moves = (MOVES[w.status] || []).filter(([, , ability]) => CAD.can(ability));
    return h('section', { class: `card rec-warrant is-${w.status}` },
      h('div', { class: 'row' }, h('span', { class: 'mono muted' }, CAD.fmt.id('warrant', w.id)), R.warrantStatus(w.status),
        h('span', { class: 'spacer' }), h('span', { class: 'muted rec-small' }, CAD.fmt.dateTime(w.createdAt))),
      h('div', { class: 'row rec-warrant-who' }, h('h2', null, w.personName), R.link('Open profile', 'people', { id: w.personId })),
      h('div', { class: 'badges' }, CAD.list(w.totals && w.totals.items).map((i) => CAD.badge(`${i.count > 1 ? `${i.count}× ` : ''}${i.name}`, R.classColor(i.class)))),
      w.totals ? h('div', { class: 'rec-small muted' }, `${CAD.fmt.money(w.totals.fine)} · ${CAD.fmt.months(w.totals.jail)}`) : null,
      h('p', { class: 'selectable rec-pre rec-warrant-reason' }, w.reason),
      h('div', { class: 'rec-meta' },
        w.requestedBy ? h('span', null, `Asked for by ${w.requestedBy.callsign ? `${w.requestedBy.callsign} ` : ''}${w.requestedBy.name}`) : null,
        w.decidedBy ? h('span', null, `${w.status === 'denied' ? 'Denied' : w.status === 'recalled' ? 'Recalled' : 'Approved'} by ${w.decidedBy.name}`) : null,
        w.servedBy ? h('span', null, `Served by ${w.servedBy.callsign ? `${w.servedBy.callsign} ` : ''}${w.servedBy.name}`) : null),
      moves.length ? h('div', { class: 'row' }, moves.map(([status, label, , kind]) => CAD.button(label, CAD.run(async () => {
        if (status !== 'active' && !(await CAD.confirm(`${label} ${CAD.fmt.id('warrant', w.id)}?`, `${w.personName}: ${w.reason}`, label, kind))) return;
        await CAD.rpc('warrant.setStatus', { id: w.id, status });
        CAD.toast(`Warrant ${status}.`, 'success');
        again();
      }), { kind, small: true }))) : null);
  };

  const render = async (root, params) => {
    const again = () => render(root, {});
    root.replaceChildren(CAD.loading());
    const all = CAD.list(await CAD.rpc('warrant.list', {}));
    const tabs = STATUSES.map((s) => {
      const list = all.filter((w) => w.status === s.key);
      return { key: s.key, label: s.label, count: list.length,
        render: () => (list.length ? h('div', { class: 'rec-cards' }, list.map((w) => card(w, again))) : CAD.empty(`No ${s.label.toLowerCase()} warrants.`)) };
    });
    const tabbed = CAD.tabs(tabs, view.tab);
    tabbed.addEventListener('click', (e) => { const t = e.target.closest('.tab'); if (t) view.tab = t.dataset.key; });
    root.replaceChildren(
      h('div', { class: 'page-head' }, h('h1', null, 'Warrants'), h('span', { class: 'spacer' }),
        CAD.can('warrants.request') ? CAD.button('Request warrant', () => requestForm(null, again), { kind: 'primary', icon: 'plus' }) : null),
      tabbed);
    if (params && params.new && CAD.can('warrants.request')) requestForm(params.personId, again);
  };

  CAD.page('warrants', { title: 'Warrants', icon: 'warrant', ability: 'records.view', order: 50, render });
})();
