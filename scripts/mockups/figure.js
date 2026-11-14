// Draws a body figure the way AnatomyFigure does in the app: the silhouette in the skin colour,
// muscles clipped to it with skin-coloured gaps and soft shading, then the contour lines.
const FIG_NS = 'http://www.w3.org/2000/svg';
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
  };
  g.insertAdjacentHTML('beforeend', `<clipPath id="${id}"><path d="${ANATOMY.outline}"/></clipPath>`);
  el(g, ANATOMY.outline, { fill: 'var(--body)' });
  el(g, ANATOMY.outline, { fill: 'url(#figBody)' });
  const inner = document.createElementNS(FIG_NS, 'g');
  inner.setAttribute('clip-path', `url(#${id})`);
  g.append(inner);
  ANATOMY[view].forEach(([m, d, detail]) => {
    const faded = opts.selected && m !== opts.selected;
    el(inner, d, { fill: fill(m), stroke: 'var(--body)', 'stroke-width': detail ? .7 : 1.5, opacity: faded ? .35 : 1 });
    if (!detail && !faded) el(inner, d, { fill: 'url(#figShade)' });
  });
  ANATOMY[view + 'Lines'].forEach(d => el(inner, d, { fill: 'none', stroke: 'var(--muscle)', 'stroke-width': 1.1 }));
  // A rim of skin around the body, so no muscle touches the edge.
  el(inner, ANATOMY.outline, { fill: 'none', stroke: 'var(--body)', 'stroke-width': 3.2 });
  if (opts.selected) ANATOMY[view].forEach(([m, d, detail]) => {
    if (m === opts.selected && !detail) el(inner, d, { fill: 'none', stroke: 'var(--ink)', 'stroke-width': 1.4 });
  });
  return g;
}
