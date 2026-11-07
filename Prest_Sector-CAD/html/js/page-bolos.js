'use strict';
// BOLOs (be on the lookout): people, vehicles or anything else every unit should watch for. A BOLO
// with a plate also shows up when that plate is run.

(() => {
  const { h } = CAD;
  const R = CAD.rec;
  const KINDS = [{ value: 'person', label: 'Person' }, { value: 'vehicle', label: 'Vehicle' }, { value: 'other', label: 'Something else' }];
  const ICON = { person: 'people', vehicle: 'car', other: 'bolo' };
  const view = { active: true };

  const form = async (b, after) => {
    const isNew = !b.id;
    let person = b.personId ? (await CAD.rpc('person.get', { id: b.personId })).summary : null;
    const kind = CAD.select(KINDS, b.kind || 'vehicle');
    const title = CAD.input({ value: b.title || '', maxlength: 80, placeholder: 'e.g. Silver sedan from the Strawberry robbery' });
    const description = CAD.textarea({ value: b.description || '', maxlength: 1000, rows: 4, placeholder: 'What to look for, last seen where, any danger' });
    const plate = CAD.input({ value: b.plate || '', maxlength: 10, class: 'input mono', placeholder: 'Optional' });
    const who = h('div', { class: 'row rec-owner-pick' });
    const drawWho = () => who.replaceChildren(person ? R.personLine(person) : h('span', { class: 'muted' }, 'Nobody picked'), h('span', { class: 'spacer' }),
      CAD.button('Pick', CAD.run(async () => { const s = await CAD.pick.person(); if (s) { person = s; drawWho(); } }), { small: true, icon: 'search' }),
      person ? CAD.button('Clear', () => { person = null; drawWho(); }, { small: true, kind: 'ghost' }) : null);
    drawWho();
    const plateField = CAD.field('Plate', plate, 'Anyone running this plate will see the BOLO');
    const personField = CAD.field('Person on file', who);
    const sync = () => { plateField.hidden = kind.value === 'person'; personField.hidden = kind.value === 'vehicle'; };
    kind.addEventListener('change', sync);
    sync();
    CAD.modal({
      title: isNew ? 'New BOLO' : 'Edit BOLO', wide: true,
      body: h('div', { class: 'form' }, h('div', { class: 'form-grid' }, CAD.field('For', kind), plateField),
        CAD.field('Title', title), CAD.field('Description', description), personField),
      actions: [{ label: 'Cancel' }, {
        label: isNew ? 'Send BOLO' : 'Save', kind: 'primary',
        onClick: async () => {
          await CAD.rpc('bolo.save', { bolo: { id: b.id, kind: kind.value, title: title.value, description: description.value,
            plate: kind.value === 'person' ? '' : plate.value, personId: kind.value === 'vehicle' || !person ? null : person.id } });
          CAD.toast(isNew ? 'BOLO sent to every unit.' : 'Saved.', 'success');
          after();
        },
      }],
    });
  };

  const card = (b, again) => h('section', { class: `card rec-bolo ${b.active ? '' : 'is-off'}` },
    h('div', { class: 'row' }, h('span', { class: 'rec-bolo-icon' }, CAD.icon(ICON[b.kind] || 'bolo', 18)),
      h('span', { class: 'mono muted' }, CAD.fmt.id('bolo', b.id)), b.active ? CAD.badge('Active', '#f97316') : CAD.badge('Off', '#64748b'),
      h('span', { class: 'spacer' }), h('span', { class: 'muted rec-small' }, CAD.fmt.ago(b.createdAt))),
    h('h2', null, b.title),
    b.plate ? h('div', null, R.plate(b.plate)) : null,
    b.description ? h('p', { class: 'selectable rec-pre' }, b.description) : null,
    b.personId ? h('div', { class: 'row' }, h('span', { class: 'muted' }, 'Person:'), R.link(b.personName || CAD.fmt.id('person', b.personId), 'people', { id: b.personId })) : null,
    h('div', { class: 'rec-meta' }, b.createdBy ? h('span', null, `By ${b.createdBy.callsign ? `${b.createdBy.callsign} ` : ''}${b.createdBy.name}`) : null,
      h('span', null, CAD.fmt.dateTime(b.createdAt))),
    CAD.can('bolos.edit') ? h('div', { class: 'row' },
      CAD.button('Edit', () => form(b, again), { small: true, icon: 'edit' }),
      CAD.button(b.active ? 'Switch off' : 'Switch on', CAD.run(async () => {
        await CAD.rpc('bolo.setActive', { id: b.id, active: !b.active });
        again();
      }), { small: true })) : null);

  const render = async (root, params) => {
    const again = () => render(root, {});
    root.replaceChildren(CAD.loading());
    const list = CAD.list(await CAD.rpc('bolo.list', view.active ? { active: true } : {}));
    const active = h('input', { type: 'checkbox', checked: view.active });
    active.addEventListener('change', () => { view.active = active.checked; again(); });
    root.replaceChildren(
      h('div', { class: 'page-head' }, h('h1', null, 'BOLOs'), h('label', { class: 'check' }, active, 'Active only'), h('span', { class: 'spacer' }),
        CAD.can('bolos.edit') ? CAD.button('New BOLO', () => form({}, again), { kind: 'primary', icon: 'plus' }) : null),
      list.length ? h('div', { class: 'rec-cards' }, list.map((b) => card(b, again))) : CAD.empty('No BOLOs right now.'));
    if (params && params.new && CAD.can('bolos.edit')) form({ kind: params.kind, personId: params.personId, plate: params.plate }, again);
  };

  CAD.page('bolos', { title: 'BOLOs', icon: 'bolo', ability: 'people.view', order: 60, render });
})();
