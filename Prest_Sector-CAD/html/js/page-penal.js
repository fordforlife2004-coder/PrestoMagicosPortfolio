'use strict';
// The penal code, for everyone: every charge with its class, fine and jail time, searchable.

(() => {
  const { h } = CAD;
  const R = CAD.rec;

  const render = (root, params) => {
    const titles = CAD.list(CAD.state.config.penal);
    const input = CAD.input({ placeholder: 'Search by charge or code', value: (params && params.query) || '' });
    const body = h('div', { class: 'stack' });
    const draw = () => {
      const q = input.value.trim().toLowerCase();
      const sections = titles.map((t) => {
        const charges = CAD.list(t.charges).filter((c) => !q || c.code.toLowerCase().includes(q) || c.name.toLowerCase().includes(q));
        if (!charges.length) return null;
        return h('section', { class: 'card' }, h('div', { class: 'card-head' }, h('h2', null, t.title),
          h('span', { class: 'muted rec-small' }, `${charges.length} charge${charges.length === 1 ? '' : 's'}`)),
        CAD.table([
          { label: 'Code', render: (c) => h('span', { class: 'mono' }, c.code) },
          { label: 'Charge', render: (c) => c.name },
          { label: 'Class', render: (c) => CAD.badge(c.class, R.classColor(c.class)) },
          { label: 'Fine', class: 'num', render: (c) => CAD.fmt.money(c.fine) },
          { label: 'Jail', class: 'num', render: (c) => (c.jail ? CAD.fmt.months(c.jail) : '—') },
        ], charges));
      }).filter(Boolean);
      body.replaceChildren(...(sections.length ? sections : [CAD.empty('No charge matches.')]));
    };
    input.addEventListener('input', CAD.debounce(draw, 120));
    root.append(h('div', { class: 'page-head' }, h('h1', null, 'Penal code'), h('div', { class: 'search-box' }, CAD.icon('search', 16), input)), body);
    draw();
  };

  CAD.page('penal', { title: 'Penal code', icon: 'book', ability: null, order: 95, render });
})();
