/* SVG diagrams for the build guide. Geometry comes from GUIDE_DIAGRAM where it matters:
   membranes, button board, screw map and Nano pins are true to the CAD. Schematics are drawn by hand. */
(function () {
  'use strict';
  const C = {
    ink: '#1d2330', sub: '#5d6677', faint: '#b8c0cc', grid: '#e6eaf0', paper: '#ffffff',
    red: '#e0313b', blue: '#2f6fe4', green: '#1f9d55', amber: '#f2a33a', purple: '#8b5cf6', teal: '#0ea5a4',
    pcb: '#1d6b3f', pcbLight: '#d9efe2', black: '#22252b', gnd: '#2b2f36', v5: '#e0313b',
  };
  const esc = s => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;');
  const svg = (w, h, body, cls = '') =>
    `<svg class="diagram ${cls}" viewBox="0 0 ${w} ${h}" xmlns="http://www.w3.org/2000/svg" role="img">${DEFS}${body}</svg>`;
  const DEFS = `<defs>
    <marker id="arr" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">
      <path d="M0,0 L10,5 L0,10 z" fill="${C.ink}"/></marker>
    <marker id="arrS" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
      <path d="M0,0 L10,5 L0,10 z" fill="${C.sub}"/></marker>
    <pattern id="hatch" width="6" height="6" patternUnits="userSpaceOnUse" patternTransform="rotate(45)">
      <rect width="6" height="6" fill="#eef1f5"/><line x1="0" y1="0" x2="0" y2="6" stroke="#c3cad4" stroke-width="2"/></pattern>
    <pattern id="bed" width="8" height="8" patternUnits="userSpaceOnUse" patternTransform="rotate(45)">
      <rect width="8" height="8" fill="#2a2f3a"/><line x1="0" y1="0" x2="0" y2="8" stroke="#3b4252" stroke-width="3"/></pattern>
    <filter id="sh" x="-10%" y="-10%" width="120%" height="130%"><feDropShadow dx="0" dy="2" stdDeviation="2.5" flood-opacity=".18"/></filter>
  </defs>`;
  const t = (x, y, s, o = {}) => `<text x="${x}" y="${y}" font-size="${o.size || 13}" fill="${o.fill || C.ink}" text-anchor="${o.anchor || 'start'}" font-weight="${o.weight || 400}" ${o.extra || ''}>${esc(s)}</text>`;
  const smooth = pts => {                      // Catmull-Rom through the points, as cubic Beziers
    let d = `M${pts[0][0].toFixed(1)},${pts[0][1].toFixed(1)}`;
    for (let i = 0; i < pts.length - 1; i++) {
      const p0 = pts[Math.max(0, i - 1)], p1 = pts[i], p2 = pts[i + 1], p3 = pts[Math.min(pts.length - 1, i + 2)];
      const c1 = [p1[0] + (p2[0] - p0[0]) / 6, p1[1] + (p2[1] - p0[1]) / 6], c2 = [p2[0] - (p3[0] - p1[0]) / 6, p2[1] - (p3[1] - p1[1]) / 6];
      d += ` C${c1.map(v => v.toFixed(1))} ${c2.map(v => v.toFixed(1))} ${p2.map(v => v.toFixed(1))}`;
    }
    return d;
  };
  const polyPath = (pts, f) => 'M' + pts.map(p => f(p).map(v => v.toFixed(1)).join(',')).join('L') + 'Z';

  // ---------- 1. print orientation ----------
  function printBeds() {
    const card = (x, title, sub, shape, note) => `
      <g transform="translate(${x},0)">
        <rect x="0" y="0" width="290" height="250" rx="14" fill="#f7f8fa" stroke="${C.grid}"/>
        ${t(18, 30, title, { size: 15, weight: 700 })}${t(18, 50, sub, { size: 12, fill: C.sub })}
        ${shape}
        <rect x="20" y="196" width="250" height="16" rx="3" fill="url(#bed)"/>
        ${t(145, 234, note, { size: 12, fill: C.sub, anchor: 'middle' })}
      </g>`;
    const front = `<path d="M40 196 L250 196 L250 160 L244 160 L244 190 L46 190 L46 160 L40 160 Z" fill="${C.black}"/>
      <path d="M40 196 L46 190 M250 196 L244 190" stroke="#666" />
      <rect x="70" y="150" width="6" height="40" fill="${C.black}"/><rect x="120" y="165" width="5" height="25" fill="${C.black}"/>
      <rect x="170" y="150" width="6" height="40" fill="${C.black}"/><rect x="214" y="158" width="5" height="32" fill="${C.black}"/>
      <path d="M92 190 l6 -6 h14 l6 6" fill="#f7f8fa" stroke="${C.black}"/>
      <path d="M150 92 v40" stroke="${C.red}" stroke-width="2.5" marker-end="url(#arr)"/>
      ${t(158, 104, 'face on the bed', { size: 12, fill: C.red, weight: 600 })}
      ${t(158, 120, '45° bezels: no supports', { size: 11, fill: C.sub })}`;
    const bracket = `<rect x="55" y="186" width="180" height="10" fill="#8b929c"/>
      <rect x="85" y="183" width="40" height="3" fill="#f7f8fa"/><rect x="165" y="183" width="40" height="3" fill="#f7f8fa"/>
      <path d="M105 140 v38 M185 140 v38" stroke="${C.sub}" stroke-dasharray="3 3" marker-end="url(#arrS)"/>
      ${t(145, 128, 'tape recesses face up', { size: 12, fill: C.sub, anchor: 'middle' })}
      ${t(145, 100, 'glass side down', { size: 12, fill: C.red, weight: 600, anchor: 'middle' })}`;
    const back = `<path d="M40 196 L250 196 L250 128 Q250 122 244 122 L244 190 L46 190 L46 150 Q46 145 40 146 Z" fill="${C.black}"/>
      <path d="M46 150 L244 122" stroke="${C.faint}" stroke-dasharray="4 4"/>
      <rect x="90" y="176" width="6" height="14" fill="${C.black}"/><rect x="150" y="170" width="6" height="20" fill="${C.black}"/>
      <rect x="196" y="160" width="6" height="30" fill="${C.black}"/>
      ${t(145, 92, 'floor on the bed', { size: 12, fill: C.red, weight: 600, anchor: 'middle' })}
      ${t(145, 110, 'wedge: 35.2 → 28 mm', { size: 11, fill: C.sub, anchor: 'middle' })}`;
    return svg(930, 256,
      card(0, 'Front shell', 'modern_front_3.5in_3btn.stl', front, 'shipped face down: just slice it') +
      card(320, 'Glass bracket', 'modern_glass_clamp_driver_bracket.stl', bracket, '78 × 77 × 1.2 mm plate') +
      card(640, 'Back shell', 'modern_back_pm11_nano20k_nano_port.stl', back, '45° tops on every port opening'));
  }

  // ---------- 2. Nano wings ----------
  function nanoWings() {
    const pins = i => 70 + i * 13;
    let top = `<rect x="150" y="50" width="120" height="276" rx="6" fill="${C.black}"/>
      <rect x="186" y="40" width="48" height="26" rx="3" fill="#c9ccd2"/>${t(210, 34, 'USB-C', { size: 11, anchor: 'middle', fill: C.sub })}
      <rect x="175" y="300" width="70" height="34" rx="3" fill="#c9ccd2"/>${t(210, 350, 'HDMI', { size: 11, anchor: 'middle', fill: C.sub })}
      <rect x="180" y="150" width="60" height="60" rx="4" fill="#3a3e47"/>${t(210, 185, 'GW2AR', { size: 10, anchor: 'middle', fill: '#9aa3b2' })}`;
    for (let i = 0; i < 20; i++) {
      const y = pins(i);
      top += `<rect x="154" y="${y - 3}" width="10" height="6" fill="#111"/><rect x="256" y="${y - 3}" width="10" height="6" fill="#111"/>
        <line x1="154" y1="${y}" x2="104" y2="${y}" stroke="#d4af37" stroke-width="2"/>
        <line x1="266" y1="${y}" x2="316" y2="${y}" stroke="#d4af37" stroke-width="2"/>`;
    }
    top += `<rect x="40" y="62" width="64" height="${20 * 13}" rx="3" fill="${C.red}" opacity=".88"/>
      <rect x="316" y="62" width="64" height="${20 * 13}" rx="3" fill="${C.red}" opacity=".88"/>
      ${t(72, 200, 'Dupont', { size: 11, anchor: 'middle', fill: '#fff', extra: 'transform="rotate(-90 72 200)"' })}
      ${t(348, 200, 'Dupont', { size: 11, anchor: 'middle', fill: '#fff', extra: 'transform="rotate(90 348 200)"' })}
      ${t(130, 64, '1', { size: 10, fill: C.sub, anchor: 'middle' })}${t(290, 64, '1', { size: 10, fill: C.sub, anchor: 'middle' })}
      ${t(72, 352, 'J6', { size: 14, weight: 700, anchor: 'middle' })}${t(348, 352, 'J5', { size: 14, weight: 700, anchor: 'middle' })}
      ${t(210, 384, 'Component side, USB-C up (as it sits in the case)', { size: 12, fill: C.sub, anchor: 'middle' })}`;
    // side section across the board
    const side = `<g transform="translate(470,60)">
      ${t(0, 0, 'Section across the board', { size: 14, weight: 700 })}
      <rect x="80" y="120" width="240" height="12" fill="${C.black}"/>${t(200, 112, 'Nano 20K', { size: 11, fill: C.sub, anchor: 'middle' })}
      <rect x="92" y="96" width="22" height="24" fill="#111"/><rect x="286" y="96" width="22" height="24" fill="#111"/>
      <path d="M103 132 v12" stroke="#d4af37" stroke-width="3"/><path d="M297 132 v12" stroke="#d4af37" stroke-width="3"/>
      <path d="M103 120 v-14 h-60" fill="none" stroke="#d4af37" stroke-width="3"/>
      <path d="M297 120 v-14 h60" fill="none" stroke="#d4af37" stroke-width="3"/>
      <rect x="-30" y="98" width="70" height="16" rx="2" fill="${C.red}"/><rect x="360" y="98" width="70" height="16" rx="2" fill="${C.red}"/>
      <path d="M-30 106 h-30" stroke="${C.blue}" stroke-width="3"/><path d="M430 106 h30" stroke="${C.blue}" stroke-width="3"/>
      <path d="M115 150 l-10 -4" stroke="${C.sub}"/>${t(30, 180, 'legs trimmed to ~1.5 mm', { size: 11, fill: C.sub })}
      <path d="M95 175 L103 146" stroke="${C.sub}" marker-end="url(#arrS)"/>
      <rect x="120" y="132" width="26" height="6" fill="${C.amber}"/><rect x="254" y="132" width="26" height="6" fill="${C.amber}"/>
      <path d="M200 205 L150 140 M200 205 L262 140" stroke="${C.sub}" fill="none" marker-end="url(#arrS)"/>
      ${t(200, 222, 'foam pads on 4 corner lands', { size: 11, fill: C.sub, anchor: 'middle' })}
      ${t(200, 70, 'pins point outward, parallel to the board', { size: 12, fill: C.red, weight: 600, anchor: 'middle' })}
      <path d="M140 76 L60 100 M260 76 L340 100" stroke="${C.red}" fill="none" marker-end="url(#arr)"/>
      ${t(-60, 260, 'Up in this section is toward the screen: the component side faces the front.', { size: 11, fill: C.sub })}
    </g>`;
    return svg(960, 400, top + side);
  }

  // ---------- 3. membranes (true scale, seen from the front) ----------
  function membranes(D) {
    const pts = [].concat(...Object.values(D.membranes).map(m => [].concat(...m.outline)), Object.values(D.buttons));
    const lo = [Math.min(...pts.map(p => p[0])) - 6, Math.min(...pts.map(p => p[1])) - 6];
    const hi = [Math.max(...pts.map(p => p[0])) + 6, Math.max(...pts.map(p => p[1])) + 6];
    const s = Math.min(560 / (hi[0] - lo[0]), 320 / (hi[1] - lo[1]));
    const f = p => [40 + (p[0] - lo[0]) * s, 96 + (hi[1] - p[1]) * s];
    let body = `<rect x="0" y="0" width="960" height="430" fill="${C.paper}"/>`;
    // pads under all six PCB positions
    const gen = { R: 'A', B: 'B', A: 'C', L: 'X', X: 'Y', Y: 'Z' };
    for (const [k, p] of Object.entries(D.buttons)) {
      const [x, y] = f(p), used = ['R', 'B', 'A'].includes(k);
      body += `<circle cx="${x}" cy="${y}" r="${4.1 * s}" fill="${used ? '#fff3f3' : '#f4f5f7'}" stroke="${used ? C.red : C.faint}" stroke-dasharray="${used ? '' : '4 4'}"/>`;
    }
    const m = D.membranes;
    for (const [k, p] of Object.entries(m)) {
      const half = k === 'R_half';
      for (const poly of p.outline)
        body += `<path d="${polyPath(poly, f)}" fill="${half ? 'rgba(242,163,58,.28)' : 'rgba(80,86,96,.18)'}" stroke="${half ? '#d9861a' : '#4d535d'}" stroke-width="2"/>`;
      for (const h of p.holes) { const [x, y] = f(h); body += `<circle cx="${x}" cy="${y}" r="${0.8 * s}" fill="#fff" stroke="${C.sub}"/>`; }
      for (const c of p.centres) { const [x, y] = f(c); body += `<circle cx="${x}" cy="${y}" r="${3.2 * s}" fill="none" stroke="${C.ink}" stroke-width="1.5" stroke-dasharray="2 3"/>`; }
      if (p.cut_line) {
        const [a, b] = p.cut_line.map(f);
        body += `<line x1="${a[0]}" y1="${a[1]}" x2="${b[0]}" y2="${b[1]}" stroke="${C.red}" stroke-width="2.5" stroke-dasharray="7 5"/>`;
        body += t(a[0] - 8, a[1] + 18, 'cut edge', { size: 12, fill: C.red, weight: 600, anchor: 'end' });
      }
    }
    for (const [k, p] of Object.entries(D.buttons)) {
      const [x, y] = f(p), used = ['R', 'B', 'A'].includes(k);
      body += t(x, y + 5, used ? gen[k] : gen[k], { size: 15, weight: 700, anchor: 'middle', fill: used ? C.red : C.faint });
      body += t(x, y + 4.1 * s + 15, `pad ${k}`, { size: 10.5, anchor: 'middle', fill: used ? C.sub : C.faint });
    }
    // scale bar
    body += `<path d="M40 400 h${10 * s}" stroke="${C.ink}" stroke-width="2"/><path d="M40 394 v12 M${40 + 10 * s} 394 v12" stroke="${C.ink}"/>`;
    body += t(40 + 5 * s, 388, '10 mm', { size: 11, anchor: 'middle' });
    body += t(30, 34, 'Seen from the front, true scale', { size: 15, weight: 700 });
    body += t(30, 54, 'Grey: intact stock A/B membrane on B–C. Orange: half membrane on A.', { size: 12, fill: C.sub });
    body += t(30, 72, 'Dashed pads (X Y Z) stay unwired and are closed in the face.', { size: 12, fill: C.sub });
    // inset: how to cut
    const ba = m.BA, c0 = ba.centres[0], c1 = ba.centres[1];
    const ang = Math.atan2(c1[1] - c0[1], c1[0] - c0[0]), mid = [(c0[0] + c1[0]) / 2, (c0[1] + c1[1]) / 2];
    const s2 = 6, gx = 790, gy = 250;
    const g = p => { const dx = p[0] - mid[0], dy = p[1] - mid[1];
      return [gx + (dx * Math.cos(-ang) - dy * Math.sin(-ang)) * s2, gy - (dx * Math.sin(-ang) + dy * Math.cos(-ang)) * s2]; };
    let inset = `<rect x="640" y="110" width="300" height="270" rx="12" fill="#f7f8fa" stroke="${C.grid}"/>`;
    inset += t(660, 136, 'Making the half', { size: 14, weight: 700 });
    for (const poly of ba.outline) inset += `<path d="${polyPath(poly, g)}" fill="rgba(80,86,96,.16)" stroke="#4d535d" stroke-width="1.6"/>`;
    for (const cc of ba.centres) { const [x, y] = g(cc); inset += `<circle cx="${x}" cy="${y}" r="${3.2 * s2}" fill="none" stroke="${C.ink}" stroke-dasharray="2 3"/>`; }
    inset += `<line x1="${gx}" y1="${gy - 70}" x2="${gx}" y2="${gy + 70}" stroke="${C.red}" stroke-width="2.5" stroke-dasharray="7 5"/>`;
    const [lx] = g(c0);
    inset += `<path d="M${lx} ${gy + 84} H${gx}" stroke="${C.sub}" marker-start="url(#arrS)" marker-end="url(#arrS)"/>`;
    inset += t((lx + gx) / 2, gy + 100, '8.2 mm', { size: 11, anchor: 'middle', fill: C.sub });
    inset += t(gx + 8, gy - 56, '✂ through the rib', { size: 12, fill: C.red, weight: 600 });
    inset += t(660, 364, 'Keep the half with a locating ear.', { size: 11.5, fill: C.sub });
    return svg(960, 430, body + inset);
  }

  // ---------- 4. button board: pads, screws, header (seen from the front) ----------
  const HEADER_FN = [
    ['Up', 'J6.8', 'dpad'], ['Down', 'J6.9', 'dpad'], ['Left', 'J6.10', 'dpad'], ['Right', 'J6.11', 'dpad'],
    ['Start', 'J5.3', 'sys'], ['Mode', 'J5.13', 'sys'], ['C', 'J5.18', 'face'], ['B', 'J5.12', 'face'],
    ['(Y)', '—', 'off'], ['(Z)', '—', 'off'], ['(X)', '—', 'off'], ['A', 'J5.6', 'face'], ['GND', 'J5.15', 'gnd']];
  const PAD_LABEL = ['Up', 'Down', 'Left', 'Right', 'Start', 'Select', 'pad A', 'pad B', 'pad X', 'pad Y', 'pad L', 'pad R', 'Ground'];
  const GROUP_COL = { dpad: C.blue, sys: C.purple, face: C.red, off: C.faint, gnd: C.gnd };

  function buttonBoard(D, P) {
    const s = 7, ox = 340, oy = -2;
    const f = p => [ox + p[0] * s, (oy - p[1]) * s + 70];
    const [x0, x1, v0, v1] = D.pcb_bbox;
    const [ax, ay] = f([x0, v1]), [bx, by] = f([x1, v0]);
    let b = `<rect x="${ax}" y="${ay}" width="${bx - ax}" height="${by - ay}" rx="14" fill="${C.pcbLight}" stroke="${C.pcb}" stroke-width="2"/>`;
    const centre = n => { const q = P[n].bounds; return [(q[0][0] + q[1][0]) / 2, (q[0][1] + q[1][1]) / 2]; };
    const [dx, dy] = f(centre('dpad'));
    b += `<path d="M${dx - 26} ${dy - 9} h17 v-17 h18 v17 h17 v18 h-17 v17 h-18 v-17 h-17 z" fill="#fff" stroke="${C.blue}" stroke-width="2"/>`;
    for (const n of ['select', 'start']) {
      const [x, y] = f(centre(n));
      b += `<rect x="${x - 26}" y="${y - 9}" width="52" height="18" rx="9" fill="#fff" stroke="${C.purple}" stroke-width="2" transform="rotate(-25 ${x} ${y})"/>`;
      b += t(x, y + 32, n === 'select' ? 'Select → Mode' : 'Start', { size: 11, anchor: 'middle', fill: C.purple });
    }
    const gen = { R: 'A', B: 'B', A: 'C', L: 'X', X: 'Y', Y: 'Z' };
    for (const [k, p] of Object.entries(D.buttons)) {
      const [x, y] = f(p), used = ['R', 'B', 'A'].includes(k);
      b += `<circle cx="${x}" cy="${y}" r="${4 * s}" fill="#fff" stroke="${used ? C.red : C.faint}" stroke-width="2" stroke-dasharray="${used ? '' : '5 4'}"/>`;
      b += t(x, y - 2, gen[k], { size: 16, weight: 700, anchor: 'middle', fill: used ? C.red : C.faint });
      b += t(x, y + 14, 'pad ' + k, { size: 10, anchor: 'middle', fill: used ? C.sub : C.faint });
    }
    for (const sc of D.pcb_screws) {
      const [x, y] = f(sc), skip = D.pcb_screws_to_leave_out.some(q => Math.hypot(q[0] - sc[0], q[1] - sc[1]) < 0.5);
      b += skip
        ? `<circle cx="${x}" cy="${y}" r="9" fill="#fff" stroke="${C.red}" stroke-width="2"/><path d="M${x - 6} ${y - 6} l12 12 M${x + 6} ${y - 6} l-12 12" stroke="${C.red}" stroke-width="2.5"/>`
        : `<circle cx="${x}" cy="${y}" r="9" fill="#c9ccd2" stroke="#5d6677"/><path d="M${x - 5} ${y} h10 M${x} ${y - 5} v10" stroke="#5d6677" stroke-width="2"/>`;
    }
    const sk = f(D.pcb_screws_to_leave_out[0]);
    b += t(sk[0] - 16, sk[1] - 22, 'leave this screw out', { size: 12, fill: C.red, weight: 600, anchor: 'end' });
    b += t(sk[0] - 16, sk[1] - 7, '(under the Dupont housings)', { size: 11, fill: C.sub, anchor: 'end' });
    const H = D.button_header;
    for (let i = 0; i < H.n; i++) {
      const [x, y] = f([H.x0 + 2.54 * i, H.v]);
      const g = HEADER_FN[i][2];
      b += `<rect x="${x - 7}" y="${y - 7}" width="14" height="14" rx="2" fill="${g === 'off' ? '#fff' : GROUP_COL[g]}" stroke="${GROUP_COL[g]}" stroke-width="1.5"/>`;
      b += t(x, y - 13, String(i + 1), { size: 9, anchor: 'middle', fill: C.sub, weight: 600 });
    }
    const [hx, hy] = f([H.x0 + 2.54 * 6, H.v]);
    b += t(hx, hy + 26, '13-pin header (on the back)', { size: 11.5, anchor: 'middle', weight: 600, fill: C.sub });
    b += t(30, 30, 'Six-button PCB, seen from the front', { size: 15, weight: 700 });
    b += t(30, 50, 'Outline approximate (photo fit); pads, screws and header from the CAD.', { size: 12, fill: C.sub });
    const legend = [['M1.7 × 5 screw (5)', '#c9ccd2'], ['A B C used', C.red], ['X Y Z unwired', C.faint]];
    legend.forEach(([l, c], i) => { b += `<circle cx="${700}" cy="${470 + i * 20}" r="6" fill="${c}"/>` + t(712, 474 + i * 20, l, { size: 12 }); });
    return svg(960, 540, b);
  }

  // ---------- 5. button wiring: header → Nano ----------
  function buttonWiring() {
    const W = 960, nanoX = 480, top = 110, dy = 19, row = 54;
    const py = i => top + 18 + i * dy;
    const col = g => ({ ...GROUP_COL, v5: C.amber, aud: C.teal })[g];
    let b = `<rect x="${nanoX - 70}" y="${top}" width="140" height="${20 * dy + 20}" rx="8" fill="${C.black}"/>
      <rect x="${nanoX - 22}" y="${top - 14}" width="44" height="22" rx="3" fill="#c9ccd2"/>
      ${t(nanoX, top - 22, 'USB-C', { size: 11, anchor: 'middle', fill: C.sub })}`;
    const used = {};
    HEADER_FN.forEach(([fn, pin, g]) => { if (pin !== '—') used[pin] = [fn, g]; });
    Object.assign(used, { 'J5.1': ['5V', 'v5'], 'J5.2': ['GND', 'gnd'], 'J6.12': ['det', 'aud'], 'J6.13': ['R', 'aud'],
                          'J6.14': ['L', 'aud'], 'J6.20': ['GND', 'gnd'] });
    for (const side of ['J6', 'J5']) {
      const sx = side === 'J6' ? -1 : 1;
      for (let i = 0; i < 20; i++) {
        const y = py(i), x = nanoX + sx * row, u = used[`${side}.${i + 1}`];
        b += `<circle cx="${x}" cy="${y}" r="5.5" fill="${u ? col(u[1]) : '#4a505b'}" stroke="#0f1115"/>`;
        b += t(nanoX + sx * 30, y + 4, String(i + 1), { size: 9.5, anchor: 'middle', fill: '#8f98a8' });
      }
      b += t(nanoX + sx * row, top + 20 * dy + 44, side, { size: 15, anchor: 'middle', weight: 700 });
    }
    b += t(nanoX, top + 20 * dy + 44, 'Nano 20K', { size: 12, anchor: 'middle', fill: C.sub, weight: 600 });
    // stubs for the power and audio pins (wired in their own diagrams)
    for (const [pin, lab] of [['J5.1', '5 V from the PM11 (via diode)'], ['J5.2', 'GND from the PM11']]) {
      const y = py(+pin.split('.')[1] - 1), u = used[pin];
      b += `<path d="M${nanoX + row + 6} ${y} H${nanoX + row + 40}" stroke="${col(u[1])}" stroke-width="2.5" stroke-dasharray="4 3"/>` +
        t(nanoX + row + 46, y + 4, lab, { size: 11, fill: C.sub });
    }
    for (const [pin, lab] of [['J6.12', 'jack detect'], ['J6.13', 'jack R'], ['J6.14', 'jack L'], ['J6.20', 'jack GND']]) {
      const y = py(+pin.split('.')[1] - 1), u = used[pin];
      b += `<path d="M${nanoX - row - 6} ${y} H${nanoX - row - 26}" stroke="${col(u[1])}" stroke-width="2.5" stroke-dasharray="4 3"/>` +
        t(nanoX - row - 30, y + 4, lab, { size: 10.5, fill: C.sub, anchor: 'end' });
    }
    // header at the bottom, seen from the front: pin 1 on the left
    const hy = 690, hx = i => 200 + i * 45;
    b += `<rect x="${hx(0) - 22}" y="${hy - 16}" width="${12 * 45 + 44}" height="32" rx="6" fill="#111"/>`;
    const j5 = HEADER_FN.map((r, i) => [i, r]).filter(([, r]) => r[1].startsWith('J5'))
      .sort((p, q) => +q[1][1].split('.')[1] - +p[1][1].split('.')[1]);          // lowest pin gets the innermost lane
    const lane = Object.fromEntries(j5.map(([i], k) => [i, k]));
    HEADER_FN.forEach(([fn, pin, g], i) => {
      const x = hx(i);
      b += `<rect x="${x - 8}" y="${hy - 8}" width="16" height="16" rx="2" fill="${g === 'off' ? '#2a2d33' : col(g)}"/>`;
      b += t(x, hy + 34, String(i + 1), { size: 11, anchor: 'middle', fill: C.sub, weight: 700 });
      b += t(x, hy + 50, fn, { size: 11.5, anchor: 'middle', fill: g === 'off' ? C.faint : C.ink, weight: 700 });
      b += t(x, hy + 65, PAD_LABEL[i], { size: 9.5, anchor: 'middle', fill: C.faint });
      if (pin === '—') return;
      const [side, n] = pin.split('.'), y = py(+n - 1);
      let d;
      if (side === 'J6') {                               // straight up the left, then in to the pin
        const ex = nanoX - row - 6;
        d = `M${x} ${hy - 16} V${y + 18} Q${x} ${y} ${x + 18} ${y} H${ex}`;
      } else {                                           // under the board to a lane on the right, then up
        const k = lane[i], lx = nanoX + 100 + k * 16, ly = top + 20 * dy + 80 + k * 9, ex = nanoX + row + 6;
        d = `M${x} ${hy - 16} V${ly + 14} Q${x} ${ly} ${x + (lx > x ? 14 : -14)} ${ly} H${lx - (lx > x ? 14 : -14)} Q${lx} ${ly} ${lx} ${ly - 14} V${y + 14} Q${lx} ${y} ${lx - 14} ${y} H${ex}`;
      }
      b += `<path d="${d}" fill="none" stroke="${col(g)}" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"/>`;
    });
    b += t(hx(0) - 30, hy + 4, 'Button PCB', { size: 13, anchor: 'end', weight: 700 });
    b += t(hx(0) - 30, hy + 20, 'header', { size: 12, anchor: 'end', fill: C.sub });
    b += t(30, 30, 'Button wiring, seen from the front through the case', { size: 15, weight: 700 });
    b += t(30, 50, 'Face down on the bench everything is mirrored: header pin 1 is then on your right.', { size: 12, fill: C.sub });
    const legend = [['D-pad', C.blue], ['Start / Mode', C.purple], ['A B C', C.red], ['Ground', C.gnd], ['Power', C.amber], ['Audio', C.teal]];
    legend.forEach(([l, c], i) => { b += `<rect x="${780}" y="${126 + i * 22}" width="22" height="5" rx="2" fill="${c}"/>` + t(810, 132 + i * 22, l, { size: 12 }); });
    return svg(W, 780, b);
  }

  // ---------- 6. S-fold section ----------
  function sFold() {
    const sv = 5.6, sd = 24, O = [300, 92];
    const P = (d, v) => [O[0] + d * sd, O[1] + (80 - v) * sv];
    const rect = (d0, d1, v0, v1, fill, extra = '') => {
      const [a, b] = P(d0, v1), [c, e] = P(d1, v0);
      return `<rect x="${a}" y="${b}" width="${c - a}" height="${e - b}" fill="${fill}" ${extra}/>`;
    };
    let b = '';
    b += rect(0, 2.35, 63.6, 84, '#2a2c31') + rect(0, 2.35, -6, 11.1, '#2a2c31');   // face plate, open at the window
    b += rect(2.35, 5.65, 3.15, 67.05, '#0b0d12') + rect(2.38, 2.9, 11.1, 63.6, '#2747b8', 'opacity=".9"');
    b += rect(5.65, 6.75, 3.15, 4.3, '#d7dbe2');                                  // panel ledge on the FPC side
    b += rect(6.95, 8.15, 8.55, 67.35, '#8b929c');                                // bracket (section through the notch)
    b += rect(7.75, 8.75, 25, 60, C.amber, 'opacity=".9"');                       // foam tape in its recess
    b += rect(8.75, 10.35, 19.55, 65.55, C.blue);                                 // PCB800850
    b += rect(10.35, 12.55, 22, 58, '#22252b');                                   // its parts
    b += rect(10.3, 13.65, 60.55, 67.55, '#c9ccd2');                              // mini-HDMI
    b += rect(10.0, 14.0, 67.6, 81.5, 'url(#hatch)', `stroke="${C.faint}" stroke-dasharray="4 3"`);
    b += rect(10.6, 11.6, 19.6, 21.6, '#e6e8ec', `stroke="${C.sub}"`);            // FPC connector
    const flex = [[5.9, 4.0], [5.9, 1.2], [6.6, -0.6], [7.8, -0.7], [8.55, 1.0], [8.55, 13.0], [9.1, 15.6], [9.85, 15.2],
                  [10.1, 12.5], [10.1, 2.0], [10.8, -0.5], [11.7, 0.4], [12.0, 3.0], [12.0, 15.0], [11.6, 18.2], [11.1, 19.8]].map(p => P(...p));
    b += `<path d="${smooth(flex)}" fill="none" stroke="#e8a316" stroke-width="5" stroke-linecap="round"/>`;
    b += `<path d="${smooth(flex)}" fill="none" stroke="#ffd166" stroke-width="1.6"/>`;
    const lab = (d0, v0, d1, v1, str, o = {}) => {
      const [a, c] = P(d0, v0), [x, y] = P(d1, v1);
      return `<path d="M${a} ${c} L${x} ${y}" stroke="${C.sub}" fill="none"/><circle cx="${a}" cy="${c}" r="2.5" fill="${C.sub}"/>` +
        t(x + (o.left ? -6 : 6), y + 4, str, { size: 12, anchor: o.left ? 'end' : 'start', ...o });
    };
    b += lab(1.2, 76, -3.5, 79, 'face plate', { left: true });
    b += lab(1.2, 40, -3.5, 44, 'window (bevelled opening)', { left: true });
    b += lab(4.2, 30, -3.5, 26, 'glass panel', { left: true });
    b += lab(6.2, 3.7, -3.5, 8, 'panel ledge (1.1 mm)', { left: true });
    b += lab(7.5, 64, 17, 74, 'bracket · 4 × M2 × 5');
    b += lab(8.2, 45, 17, 52, '1 mm foam tape in 0.4 mm recesses');
    b += lab(9.6, 30, 17, 36, 'PCB800850, parts toward the back');
    b += lab(12, 64, 17, 64, 'mini-HDMI socket');
    b += lab(12, 75, 17, 84, '14 mm free for the plug');
    b += lab(11.1, 20.6, 17, 22, 'FPC connector');
    b += lab(12.0, 9, 17, 10, 'S-fold: gentle bends, no creases', { fill: '#b9770e', weight: 700 });
    b += lab(7.2, 5, -3.5, -6, 'through the bracket notch', { left: true });
    b += `<path d="M${P(0, -14)} L${P(14.5, -14)}" stroke="${C.ink}" marker-end="url(#arr)"/>` + t(P(14.5, -14)[0] + 8, P(0, -14)[1] + 4, 'toward the back', { size: 11, fill: C.sub });
    b += t(30, 30, 'Screen stack, side section through the flex', { size: 15, weight: 700 });
    b += t(30, 50, 'Depth exaggerated ×4. The top of the case is up.', { size: 12, fill: C.sub });
    return svg(960, 640, b);
  }

  // ---------- 7. power ----------
  function power() {
    let b = '';
    const box = (x, y, w, h, title, sub, fill = '#f7f8fa') => `<rect x="${x}" y="${y}" width="${w}" height="${h}" rx="12" fill="${fill}" stroke="${C.grid}" filter="url(#sh)"/>` +
      t(x + 16, y + 26, title, { size: 14, weight: 700 }) + (sub ? t(x + 16, y + 44, sub, { size: 11.5, fill: C.sub }) : '');
    b += box(30, 80, 250, 280, 'PM11 battery module', '1200 mAh LiPo · 5 V / 1.2 A boost');
    const hdr = (x, y) => {
      let s = `<rect x="${x}" y="${y}" width="140" height="62" rx="6" fill="#111"/>`;
      const lab = ['VBAT', '3V3', '5V', '5V'];
      for (let i = 0; i < 4; i++) {
        const cx = x + 20 + i * 33, use = i >= 2;
        s += `<circle cx="${cx}" cy="${y + 18}" r="6" fill="${use ? C.v5 : '#555'}"/><circle cx="${cx}" cy="${y + 44}" r="6" fill="${use ? C.gnd : '#555'}" stroke="${use ? '#9aa3b2' : 'none'}"/>`;
        s += t(cx, y + 80, lab[i], { size: 10, anchor: 'middle', fill: use ? C.ink : C.faint, weight: use ? 700 : 400 });
      }
      return s;
    };
    b += hdr(70, 140);
    b += t(56, 160, '+', { size: 14, fill: C.v5, weight: 700 }) + t(56, 188, '−', { size: 14, weight: 700 });
    b += `<rect x="70" y="262" width="70" height="30" rx="5" fill="#c9ccd2"/>` + t(105, 308, 'USB-C charge', { size: 10.5, anchor: 'middle', fill: C.sub });
    b += `<rect x="160" y="265" width="60" height="24" rx="4" fill="#9aa3b2"/><rect x="${172}" y="269" width="18" height="16" rx="2" fill="#fff"/>` + t(190, 308, 'ON / OFF', { size: 10.5, anchor: 'middle', fill: C.sub });
    b += t(46, 336, 'both on the bottom edge', { size: 11, fill: C.sub });
    // Nano
    b += box(650, 50, 270, 140, 'Tang Nano 20K', 'J5.1 = 5 V · J5.2 = GND');
    b += `<circle cx="690" cy="130" r="7" fill="${C.v5}"/>${t(704, 134, 'J5.1  5V', { size: 12, weight: 600 })}<circle cx="690" cy="158" r="7" fill="${C.gnd}"/>${t(704, 162, 'J5.2  GND', { size: 12, weight: 600 })}`;
    // PCB800850
    b += box(650, 250, 270, 140, 'PCB800850 screen driver', 'USB-C power: VBUS / GND pads');
    b += `<circle cx="690" cy="330" r="7" fill="${C.v5}"/>${t(704, 334, 'VBUS', { size: 12, weight: 600 })}<circle cx="690" cy="358" r="7" fill="${C.gnd}"/>${t(704, 362, 'GND', { size: 12, weight: 600 })}`;
    // wires pair 1 (column 3) → diode → Nano
    const p1 = [156, 158], g1 = [156, 184], p2 = [189, 158], g2 = [189, 184];
    b += `<path d="M${p1[0]} ${p1[1]} C 300 60, 360 130, 430 130" stroke="${C.v5}" stroke-width="3" fill="none"/>`;
    b += `<g transform="translate(430,130)"><rect x="0" y="-12" width="70" height="24" rx="4" fill="#222"/><rect x="52" y="-12" width="7" height="24" fill="#cfd5df"/>
      <path d="M18 -8 L18 8 L40 0 Z M40 -8 V8" fill="${C.amber}" stroke="${C.amber}" stroke-width="1.5"/></g>`;
    b += t(465, 108, '1N5817', { size: 12, anchor: 'middle', weight: 700 }) + t(465, 162, 'stripe toward the Nano', { size: 10.5, anchor: 'middle', fill: C.sub });
    b += `<path d="M500 130 H683" stroke="${C.v5}" stroke-width="3"/>`;
    b += `<path d="M${g1[0]} ${g1[1]} C 320 200, 420 170, 683 158" stroke="${C.gnd}" stroke-width="3" fill="none"/>`;
    // pair 2 → JST → driver
    b += `<path d="M${p2[0]} ${p2[1]} C 330 250, 400 330, 470 330" stroke="${C.v5}" stroke-width="3" fill="none"/>`;
    b += `<path d="M${g2[0]} ${g2[1]} C 320 300, 400 358, 470 358" stroke="${C.gnd}" stroke-width="3" fill="none"/>`;
    b += `<rect x="470" y="316" width="34" height="56" rx="4" fill="#f4f4f0" stroke="#9aa3b2"/><rect x="506" y="316" width="34" height="56" rx="4" fill="#f4f4f0" stroke="#9aa3b2"/>`;
    b += t(505, 300, 'JST-PH 2-pin', { size: 12, anchor: 'middle', weight: 700 }) + t(505, 392, 'pull the halves apart here', { size: 10.5, anchor: 'middle', fill: C.sub });
    b += `<path d="M540 330 H683" stroke="${C.v5}" stroke-width="3"/><path d="M540 358 H683" stroke="${C.gnd}" stroke-width="3"/>`;
    b += t(300, 64, 'Dupont pair 1', { size: 11.5, fill: C.sub }) + t(300, 250, 'Dupont pair 2', { size: 11.5, fill: C.sub });
    b += t(30, 30, 'Power: two plug-on Dupont pairs, no soldering on the battery', { size: 15, weight: 700 });
    b += `<rect x="30" y="410" width="890" height="54" rx="10" fill="#fff5f5" stroke="#f3c2c5"/>`;
    b += t(50, 433, 'Switch the PM11 OFF while the Nano is plugged into a computer.', { size: 13, weight: 700, fill: C.red });
    b += t(50, 452, 'The diode stops USB back-feeding, but the module is not a UPS: don’t plug or unplug the charger mid-game.', { size: 12, fill: C.sub });
    return svg(960, 480, b);
  }

  // ---------- 8. audio ----------
  function audio() {
    let b = '';
    const R = (x, y, lab) => `<path d="M${x} ${y} h10 l4 -7 l7 14 l7 -14 l7 14 l7 -14 l7 14 l4 -7 h10" fill="none" stroke="${C.ink}" stroke-width="2"/>` + t(x + 32, y - 14, lab, { size: 11.5, anchor: 'middle', weight: 600 });
    const Cap = (x, y, lab) => `<path d="M${x} ${y} v22 M${x - 13} ${y + 22} h26 M${x - 13} ${y + 30} h26 M${x} ${y + 30} v22" stroke="${C.ink}" stroke-width="2" fill="none"/>` + t(x - 18, y + 30, lab, { size: 11.5, weight: 600, anchor: 'end' });
    const Ecap = (x, y, lab) => `<path d="M${x} ${y} h18 M${x + 18} ${y - 13} v26 M${x + 28} ${y - 13} q-6 13 0 26 M${x + 25} ${y} h18" stroke="${C.ink}" stroke-width="2" fill="none"/>` + t(x + 11, y - 17, '+', { size: 12, weight: 700, anchor: 'middle' }) + t(x + 23, y - 30, lab, { size: 11.5, anchor: 'middle', weight: 600 });
    const Rv = (x, y, lab) => `<path d="M${x} ${y} v10 l-7 4 l14 7 l-14 7 l14 7 l-14 7 l7 4 v10" fill="none" stroke="${C.ink}" stroke-width="2"/>` + t(x + 14, y + 34, lab, { size: 11.5, weight: 600 });
    const gnd = (x, y) => `<path d="M${x - 12} ${y} h24 M${x - 7} ${y + 5} h14 M${x - 3} ${y + 10} h6" stroke="${C.ink}" stroke-width="2"/>`;
    const chan = (y, pin, hdr, jack, lab) => {
      let s = t(40, y + 4, `Nano pin ${pin}`, { size: 12, weight: 700 }) + t(40, y + 20, `${hdr} · ${lab}`, { size: 11, fill: C.sub });
      s += `<circle cx="170" cy="${y}" r="5" fill="${C.teal}"/><path d="M170 ${y} H200" stroke="${C.ink}" stroke-width="2"/>`;
      s += R(200, y, '330 Ω') + `<path d="M263 ${y} H340" stroke="${C.ink}" stroke-width="2"/><circle cx="310" cy="${y}" r="3.5" fill="${C.ink}"/>`;
      s += Cap(310, y, '33 nF') + gnd(310, y + 52);
      s += Ecap(340, y, '100 µF') + `<path d="M383 ${y} H480" stroke="${C.ink}" stroke-width="2"/><circle cx="440" cy="${y}" r="3.5" fill="${C.ink}"/>`;
      s += Rv(440, y, '4.7 k') + gnd(440, y + 52);
      s += `<path d="M480 ${y} H600" stroke="${C.ink}" stroke-width="2"/>` + t(604, y + 4, jack, { size: 12.5, weight: 700, fill: C.teal });
      return s;
    };
    b += chan(110, 31, 'J6.14', 'jack TIP (L)', 'left');
    b += chan(230, 30, 'J6.13', 'jack RING (R)', 'right');
    // jack symbol
    b += `<rect x="720" y="80" width="200" height="230" rx="12" fill="#f7f8fa" stroke="${C.grid}"/>` + t(736, 104, 'PJ-307 switching jack', { size: 13, weight: 700 });
    const jp = [['TIP', 134], ['TIP-NORMAL', 166, 'not connected'], ['RING', 198], ['RING-NORMAL', 230, '→ Nano pin 29 (J6.12)'], ['SLEEVE', 262, '→ GND (J6.20)']];
    for (const [n, y, note] of jp) b += `<circle cx="744" cy="${y}" r="5" fill="${C.teal}"/>` + t(756, y + 4, n, { size: 12, weight: 600 }) + (note ? t(756, y + 19, note, { size: 10.5, fill: C.sub }) : '');
    b += `<path d="M680 110 C 700 110, 716 134, 739 134" stroke="${C.teal}" stroke-width="2" fill="none"/><path d="M700 230 C 710 230, 720 198, 739 198" stroke="${C.teal}" stroke-width="2" fill="none"/>`;
    // speaker
    b += `<rect x="30" y="330" width="420" height="96" rx="12" fill="#f7f8fa" stroke="${C.grid}"/>`;
    b += `<g transform="translate(70,378)"><rect x="-10" y="-14" width="14" height="28" fill="${C.ink}"/><path d="M4 -14 L26 -30 V30 L4 14 Z" fill="${C.ink}"/></g>`;
    b += t(116, 366, 'Ø28 mm 8 Ω speaker', { size: 13, weight: 700 }) + t(116, 386, 'solder to the Nano’s SPEAKER pads (onboard MAX98357A)', { size: 11.5, fill: C.sub });
    b += t(116, 404, 'no amplifier board; 5 V already comes from the PM11', { size: 11.5, fill: C.sub });
    b += `<rect x="480" y="330" width="440" height="96" rx="12" fill="#eefbfa" stroke="#bfe8e6"/>`;
    b += t(498, 356, 'Auto-mute', { size: 13, weight: 700, fill: C.teal });
    b += t(498, 376, 'No plug: RING-NORMAL pulls pin 29 low → speaker plays.', { size: 11.5 });
    b += t(498, 394, 'Headphones in: the contact opens, pin 29 goes high →', { size: 11.5 });
    b += t(498, 410, 'firmware shuts the speaker amp down.', { size: 11.5 });
    b += t(30, 30, 'Audio: 1-bit line-out filter on a 20 × 12 mm perfboard', { size: 15, weight: 700 });
    b += t(30, 50, 'The 100 µF + lead faces the resistor. Find TIP/TIP-NORMAL and RING/RING-NORMAL with a meter: makers differ.', { size: 12, fill: C.sub });
    return svg(960, 450, b);
  }

  // ---------- 9. screw map (seen from the back, as you close the case) ----------
  function screws(D, P) {
    const s = 2.25, H = 84;
    const panel = (ox, title, sub, body) => {
      const f = p => [ox + 45 * s - p[0] * s, 92 + (H - p[1]) * s];             // seen from the back: x mirrored
      let g = '';
      for (const poly of D.outline) g += `<path d="${polyPath(poly, f)}" fill="#f2f4f7" stroke="${C.ink}" stroke-width="2"/>`;
      g += body(f);
      g += t(ox + 45 * s, 70, title, { size: 13.5, weight: 700, anchor: 'middle' }) + t(ox + 45 * s, 460, sub, { size: 11, anchor: 'middle', fill: C.sub });
      return g;
    };
    const dot = (f, p, col, r = 7) => { const [x, y] = f(p); return `<circle cx="${x}" cy="${y}" r="${r}" fill="${col}" stroke="#fff" stroke-width="2"/>`; };
    const rectMM = (f, x0, y0, x1, y1, extra) => { const [a, b] = f([x1, y1]), [c, d] = f([x0, y0]); return `<rect x="${a}" y="${b}" width="${c - a}" height="${d - b}" ${extra}/>`; };
    let b = panel(30, 'Closed case', 'USB-C + microSD at the top', f => {
      const sp = P.speaker.bounds, c = f([(sp[0][0] + sp[1][0]) / 2, (sp[0][1] + sp[1][1]) / 2]);
      let g = `<circle cx="${c[0]}" cy="${c[1]}" r="${12 * s}" fill="url(#hatch)" stroke="${C.faint}"/>`;
      g += t(c[0], c[1] + 16 * s, 'grille', { size: 10, anchor: 'middle', fill: C.sub });
      for (const p of D.case_screws) g += dot(f, p, C.ink, 8);
      return g;
    });
    b += panel(290, 'Open front shell', 'face down on the bench', f => {
      const a = D.screen_active, [x0, x1, v0, v1] = D.pcb_bbox;
      let g = rectMM(f, a[0], a[1], a[2], a[3], `fill="#e5e9f0" stroke="${C.faint}"`);
      g += rectMM(f, x0, v0, x1, v1, `fill="${C.pcbLight}" stroke="${C.pcb}" rx="6"`);
      for (const p of D.bracket_posts) g += dot(f, p, '#8b929c');
      for (const p of D.pcb_screws) {
        const skip = D.pcb_screws_to_leave_out.some(q => Math.hypot(q[0] - p[0], q[1] - p[1]) < 0.5), [x, y] = f(p);
        g += skip ? `<circle cx="${x}" cy="${y}" r="7" fill="#fff" stroke="${C.red}" stroke-width="2"/><path d="M${x - 4} ${y - 4} l8 8 M${x + 4} ${y - 4} l-8 8" stroke="${C.red}" stroke-width="2"/>`
                  : dot(f, p, C.pcb);
      }
      return g;
    });
    const rows = [
      [C.ink, 'Case', '6 × M2.3 × 8', 'back shell into the front shell'],
      ['#8b929c', 'Glass bracket', '4 × M2 × 5', 'two above the glass, lower-left, right wall'],
      [C.pcb, 'Button PCB', '5 × M1.7 × 5', 'skip the one marked ✕ (under the header)'],
      [C.amber, 'PM11', '2 × M3 × 4', 'through its two free holes'],
    ];
    let y = 120;
    b += t(590, 86, 'Screws: all from the Taiss kit', { size: 15, weight: 700 });
    for (const [c, a, n, d] of rows) {
      b += `<circle cx="600" cy="${y - 4}" r="8" fill="${c}"/>` + t(618, y, a, { size: 13, weight: 700 }) + t(740, y, n, { size: 13, weight: 700, fill: C.red }) + t(618, y + 18, d, { size: 11.5, fill: C.sub });
      y += 56;
    }
    b += `<rect x="590" y="${y + 4}" width="340" height="64" rx="10" fill="#fff4e5" stroke="#f6d39b"/>`;
    b += t(606, y + 28, 'Self-tapping into plastic: stop at snug.', { size: 12.5, weight: 700, fill: '#9a5b00' });
    b += t(606, y + 48, 'Over-torquing strips the pilots.', { size: 12, fill: C.sub });
    b += t(30, 30, 'Screw map, seen from the back (as you assemble)', { size: 15, weight: 700 });
    return svg(960, 480, b);
  }

  window.GuideDiagrams = { printBeds, nanoWings, membranes, buttonBoard, buttonWiring, sFold, power, audio, screws, HEADER_FN };
})();
