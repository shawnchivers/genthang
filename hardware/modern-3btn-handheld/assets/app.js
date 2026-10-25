/* Page wiring for the build guide: baked renders + labels, SVG diagrams, theme swatches, lazy 3D viewer. */
(function () {
  'use strict';
  const $ = (s, el = document) => el.querySelector(s);
  const $$ = (s, el = document) => [...el.querySelectorAll(s)];
  const SC = window.SCENE, LABELS = window.LABELS || {}, GD = window.GUIDE_DIAGRAM, DG = window.GuideDiagrams;
  const BOUNDS = Object.fromEntries(Object.entries(GD.bounds).map(([k, v]) => [k, { bounds: v }]));

  // ---------- baked renders with label overlays ----------
  const TITLES = {
    exploded: 'Exploded view', print: 'The three printed parts', nano: 'Nano 20K with wing headers',
    membranes: 'Membranes and caps, front face down', buttons: 'Button PCB on the front shell', screen: 'Glass, bracket and driver',
    section: 'Section through the stack', inside: 'Inside the back shell', wiring: 'Jumper housings', close: 'Closing the case',
    done: 'Finished',
  };
  for (const fig of $$('figure[data-render]')) {
    const key = fig.dataset.render;
    const labels = (LABELS[key] || []).map(l =>
      `<span class="lbl ${l.side}" style="left:${(l.x * 100).toFixed(2)}%;top:${(l.y * 100).toFixed(2)}%"><i></i><em>${l.text}</em></span>`).join('');
    fig.innerHTML = `<div class="frame"><img loading="lazy" src="renders/${key}.png" alt="${TITLES[key] || key}">${labels}</div>
      <figcaption><span>${TITLES[key] || ''}</span><button class="btn tiny" data-open3d="${key}">View in 3D ↗</button></figcaption>`;
  }

  // ---------- diagrams ----------
  const D = GD.diagram;
  const make = {
    printBeds: () => DG.printBeds(), nanoWings: () => DG.nanoWings(), membranes: () => DG.membranes(D),
    buttonBoard: () => DG.buttonBoard(D, BOUNDS), buttonWiring: () => DG.buttonWiring(D), sFold: () => DG.sFold(),
    power: () => DG.power(), audio: () => DG.audio(), screws: () => DG.screws(D, BOUNDS),
  };
  for (const el of $$('[data-diagram]')) {
    try { el.innerHTML = make[el.dataset.diagram](); } catch (e) { el.textContent = 'Diagram failed: ' + e.message; console.error(e); }
  }

  // ---------- pin table ----------
  const pinRows = DG.HEADER_FN.map(([fn, pin, g], i) => {
    const pad = ['Up', 'Down', 'Left', 'Right', 'Start', 'Select', 'A', 'B', 'X', 'Y', 'L', 'R', 'GND'][i];
    const fpga = { 'J6.8': 27, 'J6.9': 28, 'J6.10': 25, 'J6.11': 26, 'J5.3': 76, 'J5.13': 86, 'J5.18': 71, 'J5.12': 49,
                   'J5.6': 41, 'J5.15': 'GND' }[pin] || '—';
    return `<tr class="${g}"><td>${i + 1}</td><td>${pad}</td><td><b>${fn}</b></td><td>${fpga}</td><td><code>${pin}</code></td></tr>`;
  }).join('');
  $('#pin-table').innerHTML = `<table><thead><tr><th>Header pos.</th><th>PCB pad</th><th>Function</th><th>FPGA pin</th><th>Nano pin</th></tr></thead>
    <tbody>${pinRows}</tbody></table>`;

  // ---------- hero theme swatches (baked per theme) ----------
  const sw = $('#swatches');
  for (const [k, th] of Object.entries(SC.themes)) {
    const b = document.createElement('button');
    b.className = 'swatch' + (k === 'midnight' ? ' on' : '');
    b.title = th.label;
    b.style.setProperty('--shell', th.shell[0]); b.style.setProperty('--btn', th.button);
    b.innerHTML = `<span></span><em>${th.label}</em>`;
    b.onclick = () => {
      $$('.swatch').forEach(x => x.classList.remove('on')); b.classList.add('on');
      $('#hero-img').src = `renders/hero-${k}.png`; $('#hero-img-back').src = `renders/hero-back-${k}.png`;
      currentTheme = k; if (viewer) viewer.setTheme(k);
      $('#theme').value = k;
    };
    sw.appendChild(b);
  }
  let currentTheme = 'midnight';

  // ---------- scroll progress + active nav ----------
  const prog = $('#progress');
  const navs = $$('.navlinks a');
  const onScroll = () => {
    const h = document.documentElement;
    prog.style.width = (100 * h.scrollTop / (h.scrollHeight - h.clientHeight)) + '%';
    let cur = null;
    for (const a of navs) { const s = $(a.getAttribute('href')); if (s && s.getBoundingClientRect().top < 140) cur = a; }
    navs.forEach(a => a.classList.toggle('on', a === cur));
  };
  addEventListener('scroll', onScroll, { passive: true }); onScroll();

  // ---------- 3D viewer (models.js is 3 MB: load on first use) ----------
  let viewer = null, loading = null;
  const modal = $('#viewer');
  const STATE_BTNS = ['hero', 'hero-back', 'exploded', 'buttons', 'membranes', 'screen', 'section', 'inside', 'wiring', 'close'];
  const NICE = { hero: 'Front', 'hero-back': 'Back', exploded: 'Exploded', buttons: 'Button PCB', membranes: 'Membranes',
                 screen: 'Screen', section: 'Section', inside: 'Inside', wiring: 'Wiring', close: 'Closing' };
  $('#viewer-states').innerHTML = STATE_BTNS.map(k => `<button data-state="${k}">${NICE[k]}</button>`).join('');
  $('#theme').innerHTML = Object.entries(SC.themes).map(([k, t]) => `<option value="${k}">${t.label}</option>`).join('');

  function loadScript(src) {
    return new Promise((ok, bad) => { const s = document.createElement('script'); s.src = src; s.onload = ok; s.onerror = bad; document.head.appendChild(s); });
  }
  function hasGL() { try { return !!document.createElement('canvas').getContext('webgl2'); } catch (e) { return false; } }
  function goto(key) {
    const st = SC.states[key] || SC.states.hero;
    viewer.setState(st);
    $('#explode').value = st.explode || 0;
    $$('#viewer-states button').forEach(b => b.classList.toggle('on', b.dataset.state === key));
    current = key;
  }
  let current = 'hero';
  async function open3d(key) {
    modal.hidden = false; document.body.classList.add('modal-open');
    if (!hasGL()) { $('#gl-loading').textContent = 'This browser has WebGL 2 turned off, so the renders above are the 3D views.'; return; }
    if (!viewer) {
      loading = loading || Promise.all([loadScript('assets/models.js'), loadScript('assets/viewer.js')]);
      await loading;
      viewer = new window.GuideViewer($('#gl'), window.GUIDE, { labelLayer: $('#gl-labels'), initial: SC.states[key] });
      viewer.setTheme(currentTheme);
      $('#theme').value = currentTheme;
      $('#gl-loading').hidden = true;
    }
    goto(key);
  }
  document.addEventListener('click', e => {
    const b = e.target.closest('[data-open3d]');
    if (b) { e.preventDefault(); open3d(b.dataset.open3d); }
    const s = e.target.closest('#viewer-states button');
    if (s && viewer) goto(s.dataset.state);
  });
  const close = () => { modal.hidden = true; document.body.classList.remove('modal-open'); };
  $('#close3d').onclick = close;
  addEventListener('keydown', e => { if (e.key === 'Escape' && !modal.hidden) close(); });
  $('#explode').oninput = e => {
    if (!viewer) return;
    const st = Object.assign({}, SC.states[current], { explode: +e.target.value });
    viewer.setState(st, false);
    viewer.user = viewer._keepUser || viewer.user;
  };
  $('#explode').onpointerdown = () => { if (viewer) viewer._keepUser = viewer.user; };
  $('#theme').onchange = e => { currentTheme = e.target.value; if (viewer) viewer.setTheme(currentTheme); };
})();
