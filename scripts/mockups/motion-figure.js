// Draws one frame of the animated exercise figure the way MotionFigureView does in the app: jointed
// body parts from motion-shapes.js placed on a skeleton from motion-data.js, muscles in their role
// colours. Scene coordinates have y up and the floor at y = 0; the caller's <svg> gets a matching viewBox.
const MF_NS = 'http://www.w3.org/2000/svg';
const MF_JOINTS = ['hip', 'shoulder', 'head', 'elbow', 'hand', 'knee', 'ankle', 'toe', 'farElbow', 'farHand', 'farKnee', 'farAnkle', 'farToe', 'farShoulder', 'farHip'];
let motionCount = 0;

// 0 at the start pose, 1 at the end pose, easing in and out, back and forth.
const motionPhase = (seconds, duration) => 0.5 - 0.5 * Math.cos(2 * Math.PI * (seconds / duration % 1));

function motionSkeleton(move, phase) {
  const steps = move.frames.length - 1, at = Math.min(Math.max(phase, 0), 1) * steps;
  const i = Math.min(Math.floor(at), steps - 1), t = at - i, a = move.frames[i], b = move.frames[i + 1];
  const s = {};
  MF_JOINTS.forEach((name, j) => { s[name] = [a[j][0] + (b[j][0] - a[j][0]) * t, a[j][1] + (b[j][1] - a[j][1]) * t]; });
  return s;
}

// The viewBox that fits the whole movement with some room around it.
function motionViewBox(move, pad = 14) {
  const [x0, y0, x1, y1] = move.bounds;
  return [x0 - pad, -(y1 + pad), x1 - x0 + pad * 2, y1 - y0 + pad * 1.4];
}

// opts: load ('barbell' …), glow (0…1, how hard the worked muscles are working right now), effort (muscle => 0…1).
function drawMotion(svg, move, phase, fill, opts = {}) {
  if (!svg.querySelector('defs')) svg.insertAdjacentHTML('afterbegin', `<defs>
    <radialGradient id="mfShade" cx=".4" cy=".3" r=".8">
      <stop offset="0" stop-color="#fff" stop-opacity=".22"/><stop offset=".55" stop-color="#fff" stop-opacity="0"/>
      <stop offset="1" stop-color="#000" stop-opacity=".16"/></radialGradient></defs>`);
  const s = motionSkeleton(move, phase);
  const root = document.createElementNS(MF_NS, 'g');
  root.setAttribute('transform', 'scale(1 -1)');
  const el = (parent, tag, attrs) => {
    const node = document.createElementNS(MF_NS, tag);
    Object.entries(attrs).forEach(([k, v]) => node.setAttribute(k, v));
    parent.append(node);
    return node;
  };
  const line = (parent, a, b, width, color) => el(parent, 'line', { x1: a[0], y1: a[1], x2: b[0], y2: b[1], stroke: color, 'stroke-width': width, 'stroke-linecap': 'round' });
  const dot = (parent, p, r, color) => el(parent, 'circle', { cx: p[0], cy: p[1], r, fill: color });

  // Floor, benches, bars.
  const [x0, , x1] = move.bounds;
  // The floor sits where the soles are, a little under the ankle-to-toe line the skeleton stands on.
  const floor = move.view === 'front' ? -8.5 : -3.2;
  line(root, [x0 - 40, floor], [x1 + 40, floor], 1.6, 'var(--line2)');
  move.fixtures.forEach(f => {
    if (f[0] === 'block') el(root, 'rect', { x: f[1], y: f[2] + (f[2] === 0 ? floor : 0), width: f[3], height: f[4] - (f[2] === 0 ? floor : 0), rx: 3, fill: 'var(--fill)', stroke: 'var(--line2)', 'stroke-width': 1 });
    if (f[0] === 'line') line(root, [f[1], f[2]], [f[3], f[4]], 4, 'var(--line2)');
  });
  if (move.fixtures.some(f => f[0] === 'footPlate')) {
    const dx = s.toe[0] - s.ankle[0], dy = s.toe[1] - s.ankle[1], n = Math.max(Math.hypot(dx, dy), .001);
    const c = [s.toe[0] + dx / n * 3, s.toe[1] + dy / n * 3];
    line(root, [c[0] - dy / n * 15, c[1] + dx / n * 15], [c[0] + dy / n * 15, c[1] - dx / n * 15], 5, 'var(--line2)');
  }
  if (opts.load === 'cable' && move.pulley) {
    line(root, move.pulley, s.hand, 1.2, 'var(--ink3)');
    dot(root, move.pulley, 3, 'var(--ink3)');
    if (move.view === 'front') {
      const other = [-move.pulley[0], move.pulley[1]];
      line(root, other, s.farHand, 1.2, 'var(--ink3)');
      dot(root, other, 3, 'var(--ink3)');
    }
  }

  const shapes = MOTION_SHAPES[move.view] || MOTION_SHAPES.side;
  // One body part from joint a to joint b. `flip` puts the front of the part on its other side.
  const part = (parent, name, a, b, flip) => {
    const shape = shapes[name];
    const dx = b[0] - a[0], dy = b[1] - a[1], length = Math.max(Math.hypot(dx, dy), .001);
    const ux = dx / length, uy = dy / length, stretch = length / shape.length;
    const nx = flip ? uy : -uy, ny = flip ? -ux : ux;
    const g = el(parent, 'g', { transform: `matrix(${ux * stretch} ${uy * stretch} ${nx} ${ny} ${a[0]} ${a[1]})` });
    const clip = 'mfClip' + motionCount++;
    g.insertAdjacentHTML('beforeend', `<clipPath id="${clip}"><path d="${shape.outline}"/></clipPath>`);
    el(g, 'path', { d: shape.outline, fill: 'var(--body)' });
    const inner = el(g, 'g', { 'clip-path': `url(#${clip})` });
    shape.regions.forEach(([m, d, detail]) => {
      const color = m ? fill(m) : 'var(--tissue)';
      const k = m && opts.effort ? opts.effort(m) * (opts.glow || 0) : 0;
      if (k > 0 && !detail) el(inner, 'path', { d, fill: 'none', stroke: color, 'stroke-width': 3.4, 'stroke-opacity': .3 * k, 'stroke-linejoin': 'round' });
      el(inner, 'path', { d, fill: color });
      if (m && !detail) el(inner, 'path', { d, fill: 'url(#mfShade)' });
      if (k > 0) el(inner, 'path', { d, fill: '#fff', 'fill-opacity': .12 * k });
      el(inner, 'path', { d, fill: 'none', stroke: 'var(--body)', 'stroke-width': detail ? .35 : .7, 'stroke-linejoin': 'round' });
    });
    shape.lines.forEach(d => el(inner, 'path', { d, fill: 'none', stroke: 'var(--muscle)', 'stroke-width': .6, 'stroke-linecap': 'round' }));
    el(inner, 'path', { d: shape.outline, fill: 'none', stroke: 'var(--body)', 'stroke-width': 1.5, 'stroke-linejoin': 'round' });
  };
  const up = move.faceUp;
  const mid = (a, b) => [(a[0] + b[0]) / 2, (a[1] + b[1]) / 2];
  if (move.view === 'front') {
    // Both sides face the viewer; the far side is the near side mirrored.
    const neck = mid(s.shoulder, s.farShoulder), pelvis = mid(s.hip, s.farHip);
    [[s.hip, 8.4], [s.farHip, 8.4], [s.knee, 5.4], [s.farKnee, 5.4], [s.shoulder, 7.6], [s.farShoulder, 7.6], [s.elbow, 4.4], [s.farElbow, 4.4]]
      .forEach(([p, r]) => dot(root, p, r, 'var(--body)'));
    [[s.hip, s.knee, s.ankle, false], [s.farHip, s.farKnee, s.farAnkle, true]].forEach(([hip, knee, ankle, flip]) => {
      part(root, 'shin', knee, ankle, flip); part(root, 'thigh', hip, knee, flip);
    });
    part(root, 'torso', neck, pelvis, false);
    part(root, 'head', s.head, neck, false);
    [[s.shoulder, s.elbow, s.hand, false], [s.farShoulder, s.farElbow, s.farHand, true]].forEach(([shoulder, elbow, hand, flip]) => {
      part(root, 'forearm', elbow, hand, flip); part(root, 'upperArm', shoulder, elbow, flip);
    });
  } else {
    const arm = (parent, shoulder, elbow, hand) => { part(parent, 'forearm', elbow, hand, up); part(parent, 'upperArm', shoulder, elbow, up); };
    const leg = (parent, hip, knee, ankle, toe) => { part(parent, 'foot', ankle, toe, up); part(parent, 'shin', knee, ankle, up); part(parent, 'thigh', hip, knee, up); };
    // The far arm and leg first, held back so the near side reads clearly.
    const far = el(root, 'g', { opacity: .55 });
    arm(far, s.farShoulder, s.farElbow, s.farHand);
    leg(far, s.farHip, s.farKnee, s.farAnkle, s.farToe);
    part(root, 'head', s.head, s.shoulder, up);
    part(root, 'torso', s.shoulder, s.hip, up);
    leg(root, s.hip, s.knee, s.ankle, s.toe);
    arm(root, s.shoulder, s.elbow, s.hand);
  }

  const weight = 'var(--ink2)';
  if (opts.load === 'barbell') {
    const p = move.loadAtHip ? s.hip : s.hand;
    // The plate as a ring, so the body shows through it.
    el(root, 'circle', { cx: p[0], cy: p[1], r: 19, fill: weight, 'fill-opacity': .1, stroke: weight, 'stroke-width': 2.4 });
    el(root, 'circle', { cx: p[0], cy: p[1], r: 13.5, fill: 'none', stroke: weight, 'stroke-width': .7, 'stroke-opacity': .6 });
    dot(root, p, 3.4, weight); dot(root, p, 1.3, 'var(--card)');
  } else if (opts.load === 'dumbbell') {
    (move.view === 'front' ? [s.hand, s.farHand] : [s.hand]).forEach(p => { dot(root, p, 6, weight); dot(root, p, 2, 'var(--ink3)'); });
  } else if (opts.load === 'kettlebell') {
    dot(root, [s.hand[0], s.hand[1] - 7], 7, weight);
  }
  return root;
}
