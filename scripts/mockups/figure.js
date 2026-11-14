// Draws a body figure the way AnatomyFigure does in the app: the silhouette in the skin colour,
// muscles clipped to it with skin-coloured gaps, soft shading and fibre lines, then the contour
// lines. With opts.effort and opts.time it draws one frame of the contracting-muscle animation.
const FIG_NS = 'http://www.w3.org/2000/svg';
const FIG_PERIOD = 2.2;
const FIG_FIBRES = { chest: -62, frontDelts: 18, sideDelts: 10, rearDelts: -15, traps: 70, upperBack: -55, lats: 38, biceps: 6, triceps: 6,
  forearms: 8, abs: 0, lowerBack: 0, calves: 0, obliques: -38, quads: 8, hamstrings: 4, adductors: -22, glutes: -48 };
let figureCount = 0;

function figureDefs(svg) {
  if (svg.querySelector('defs')) return;
  svg.insertAdjacentHTML('afterbegin', `<defs>
    <radialGradient id="figShade" cx=".4" cy=".3" r=".8">
      <stop offset="0" stop-color="#fff" stop-opacity=".22"/><stop offset=".55" stop-color="#fff" stop-opacity="0"/>
      <stop offset="1" stop-color="#000" stop-opacity=".16"/></radialGradient>
    <linearGradient id="figBody" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0" stop-color="#000" stop-opacity=".05"/><stop offset=".5" stop-color="#000" stop-opacity="0"/>
      <stop offset="1" stop-color="#000" stop-opacity=".05"/></linearGradient>
  </defs>`);
}

// Bounding boxes from the path numbers (control points included, which is close enough here).
function figureBounds(d) {
  const n = d.match(/-?\d+(\.\d+)?/g).map(Number);
  let x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9;
  for (let i = 0; i < n.length; i += 2) { x0 = Math.min(x0, n[i]); x1 = Math.max(x1, n[i]); y0 = Math.min(y0, n[i + 1]); y1 = Math.max(y1, n[i + 1]); }
  return { x: x0, y: y0, w: x1 - x0, h: y1 - y0, cx: (x0 + x1) / 2, cy: (y0 + y1) / 2 };
}
['front', 'back'].forEach(view => {
  const regions = ANATOMY[view];
  regions.forEach(r => { r.bounds = figureBounds(r[1]); });
  regions.forEach(r => {
    const b = r.bounds;
    const parent = r[2] && regions.find(o => !o[2] && o[0] === r[0] && b.cx >= o.bounds.x && b.cx <= o.bounds.x + o.bounds.w && b.cy >= o.bounds.y && b.cy <= o.bounds.y + o.bounds.h);
    r.anchor = parent ? [parent.bounds.cx, parent.bounds.cy] : [b.cx, b.cy];
  });
});

function figureFibres(muscle, back, b) {
  if (muscle === 'traps' && back && Math.abs(b.cx - 100) < 1) return null;
  let degrees = FIG_FIBRES[muscle];
  if (back && muscle === 'traps') degrees = 58;
  if (back && muscle === 'adductors') degrees = -10;
  const radians = degrees * (b.cx < 100 ? -1 : 1) * Math.PI / 180;
  const dx = Math.sin(radians), dy = -Math.cos(radians), reach = Math.hypot(b.w, b.h) / 2 + 2;
  let d = '';
  for (let o = -reach; o <= reach; o += 2.6) {
    const x = b.cx - dy * o, y = b.cy + dx * o;
    d += `M${(x - dx * reach).toFixed(1)},${(y - dy * reach).toFixed(1)} L${(x + dx * reach).toFixed(1)},${(y + dy * reach).toFixed(1)} `;
  }
  return d;
}

const figureSmooth = v => { const t = Math.min(Math.max(v, 0), 1); return t * t * (3 - 2 * t); };
// 0…effort over one cycle: a quick squeeze, a short hold, a slower release.
function figureTension(time, effort) {
  if (!effort) return 0;
  const cycles = (time - (1 - effort) * 0.35) / FIG_PERIOD, phase = cycles - Math.floor(cycles);
  return effort * figureSmooth(phase / 0.3) * (1 - figureSmooth((phase - 0.5) / 0.4));
}

// opts: selected (muscle name), fibres (bool, for figures drawn large), effort (muscle => 0…1) with time (s).
function drawFigure(svg, view, fill, opts = {}) {
  figureDefs(svg);
  const id = 'figClip' + figureCount++;
  const g = document.createElementNS(FIG_NS, 'g');
  const el = (parent, d, attrs) => {
    const p = document.createElementNS(FIG_NS, 'path');
    p.setAttribute('d', d);
    p.setAttribute('stroke-linejoin', 'round');
    p.setAttribute('stroke-linecap', 'round');
    Object.entries(attrs).forEach(([k, v]) => p.setAttribute(k, v));
    parent.append(p);
    return p;
  };
  g.insertAdjacentHTML('beforeend', `<clipPath id="${id}"><path d="${ANATOMY.outline}"/></clipPath>`);
  el(g, ANATOMY.outline, { fill: 'var(--body)' });
  el(g, ANATOMY.outline, { fill: 'url(#figBody)' });
  const inner = document.createElementNS(FIG_NS, 'g');
  inner.setAttribute('clip-path', `url(#${id})`);
  g.append(inner);
  const tension = r => (opts.effort && opts.time !== undefined && r[0] && (!opts.selected || opts.selected === r[0])) ? figureTension(opts.time, opts.effort(r[0])) : 0;
  const paint = (r, index, k) => {
    const [m, d, detail] = r;
    const layer = document.createElementNS(FIG_NS, 'g');
    inner.append(layer);
    const color = m ? fill(m) : 'var(--tissue, var(--body))';
    if (k > 0) {
      const s = 1 + 0.05 * k, [ax, ay] = r.anchor;
      layer.setAttribute('transform', `translate(${ax} ${ay}) scale(${s}) translate(${-ax} ${-ay})`);
      if (!detail) {
        el(layer, d, { fill: 'none', stroke: color, 'stroke-width': 9, 'stroke-opacity': .2 * k });
        el(layer, d, { fill: 'none', stroke: color, 'stroke-width': 5, 'stroke-opacity': .3 * k });
      }
    }
    const faded = opts.selected && m !== opts.selected;
    el(layer, d, { fill: color, opacity: faded ? .35 : 1 });
    if (!detail && !faded && m) {
      el(layer, d, { fill: 'url(#figShade)' });
      const lines = opts.fibres && figureFibres(m, view === 'back', r.bounds);
      if (lines) {
        const clip = `${id}r${index}`;
        layer.insertAdjacentHTML('beforeend', `<clipPath id="${clip}"><path d="${d}"/></clipPath>`);
        const lit = color !== 'var(--muscle)';
        el(layer, lines, { fill: 'none', 'clip-path': `url(#${clip})`, stroke: lit ? '#fff' : '#000', 'stroke-opacity': lit ? .13 : .05, 'stroke-width': .5 });
      }
    }
    if (k > 0) el(layer, d, { fill: '#fff', 'fill-opacity': .1 * k });
    el(layer, d, { fill: 'none', stroke: 'var(--body)', 'stroke-width': detail ? .7 : 1.5 });
  };
  const regions = ANATOMY[view], ks = regions.map(tension);
  regions.forEach((r, i) => { if (!ks[i]) paint(r, i, 0); });
  ANATOMY[view + 'Lines'].forEach(d => el(inner, d, { fill: 'none', stroke: 'var(--muscle)', 'stroke-width': 1.1 }));
  regions.forEach((r, i) => { if (ks[i]) paint(r, i, ks[i]); });
  // A rim of skin around the body, so no muscle touches the edge.
  el(inner, ANATOMY.outline, { fill: 'none', stroke: 'var(--body)', 'stroke-width': 3.2 });
  if (opts.selected) regions.forEach(([m, d, detail]) => {
    if (m === opts.selected && !detail) el(inner, d, { fill: 'none', stroke: 'var(--ink)', 'stroke-width': 1.5 });
  });
  return g;
}
