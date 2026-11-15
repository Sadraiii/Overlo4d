// Draws one frame of the animated exercise figure the way MotionFigureView does in the app: the
// pieces from motion-shapes.js bent along a skeleton from motion-data.js, muscles in their role
// colours. Scene coordinates have y up and the floor at y = 0; the caller's <svg> gets a matching viewBox.
const MF_NS = 'http://www.w3.org/2000/svg';
const MF_JOINTS = ['hip', 'shoulder', 'head', 'elbow', 'hand', 'knee', 'ankle', 'toe', 'farElbow', 'farHand', 'farKnee', 'farAnkle', 'farToe', 'farShoulder', 'farHip'];
// Bone lengths as drawn (MotionBody in Overlo4dCore), and how much of the body on each side of a joint bends with it.
const MF_BODY = { torso: 50, head: 15.5, upperArm: 30, forearm: 30, thigh: 42, shin: 40, foot: 12 };
const MF_BEND = { hip: 16, knee: 7, elbow: 6 };
let motionCount = 0;

// 0 at the start pose, 1 at the end pose and back: a short hold at each end, and in between the
// smooth start and stop of a reaching movement (minimum jerk).
const MF_HOLD = 0.06;
function motionPhase(seconds, duration) {
  const cycle = ((seconds / duration) % 1 + 1) % 1, half = cycle < 0.5 ? cycle * 2 : (1 - cycle) * 2;
  const t = Math.min(Math.max((half - MF_HOLD) / (1 - 2 * MF_HOLD), 0), 1);
  return t * t * t * (10 + t * (6 * t - 15));
}

// The joints at a phase: a smooth curve through the frames that were written out.
function motionSkeleton(move, phase) {
  const frames = move.frames, steps = frames.length - 1, at = Math.min(Math.max(phase, 0), 1) * steps;
  const i = Math.min(Math.floor(at), steps - 1), t = at - i;
  const s = {};
  MF_JOINTS.forEach((name, j) => {
    s[name] = [0, 1].map(axis => {
      const b = frames[i][j][axis], c = frames[i + 1][j][axis];
      // Past either end the curve carries straight on.
      const a = i > 0 ? frames[i - 1][j][axis] : 2 * b - c, d = i + 2 <= steps ? frames[i + 2][j][axis] : 2 * c - b;
      return b + t * ((c - a) + t * ((2 * a - 5 * b + 4 * c - d) + t * (3 * (b - c) + d - a))) / 2;
    });
  });
  return s;
}

// The viewBox that fits the whole movement with some room around it.
function motionViewBox(move, pad = 14) {
  const [x0, y0, x1, y1] = move.bounds;
  return [x0 - pad, -(y1 + pad), x1 - x0 + pad * 2, y1 - y0 + pad * 1.4];
}

// A run of bones through `joints` that bend into each other (MotionChain in Overlo4dCore). `lengths`
// are the bones as drawn; `bends` says, for each joint between two bones, how far on each side of
// it the body curves. Returns the place of a point drawn x along bone k and y across it: on a
// straight bone that is just the bone's own frame; near a joint the point follows a curve that
// leaves one bone and joins the next, so whatever is drawn across a joint bends instead of
// breaking. On the inside of a bend the two sides meet in a crease and neither goes past it.
// `flip` puts the front (+y) on the other side.
function motionChain(joints, lengths, bends, flip) {
  const bones = lengths.map((length, k) => {
    const a = joints[k], b = joints[k + 1], dx = b[0] - a[0], dy = b[1] - a[1], size = Math.max(Math.hypot(dx, dy), .001);
    return { a, length, ux: dx / size, uy: dy / size, stretch: size / length };
  });
  // The bend where bone j starts: its curve runs from the joint less `a` to the joint plus `c`,
  // and the crease is the line across the middle of that curve.
  const folds = bones.map((after, j) => {
    if (j === 0) return null;
    const before = bones[j - 1], r = bends[j - 1];
    const ax = before.ux * before.stretch * r, ay = before.uy * before.stretch * r, cx = after.ux * after.stretch * r, cy = after.uy * after.stretch * r;
    const size = Math.hypot(ax + cx, ay + cy);
    return { r, ax, ay, cx, cy, creased: size > 1e-6, x: joints[j][0] + (cx - ax) / 8, y: joints[j][1] + (cy - ay) / 8, ex: (ax + cx) / size, ey: (ay + cy) / size };
  });
  // How far a point can lie from (x, y) in the direction (nx, ny) and still be on its own side of
  // the crease at joint j: `side` is -1 for what comes before the joint, 1 for what comes after.
  const reach = (j, x, y, nx, ny, far, side) => {
    const fold = folds[j];
    if (!fold.creased) return far;
    const over = ((x + nx * far - fold.x) * fold.ex + (y + ny * far - fold.y) * fold.ey) * side;
    const lean = (nx * fold.ex + ny * fold.ey) * side;
    return over < 0 && lean < 0 ? Math.max(far - over / lean, 0) : far;
  };
  const straight = (k, x, y) => {
    const bone = bones[k], sign = (flip ? -y : y) < 0 ? -1 : 1, nx = -bone.uy * sign, ny = bone.ux * sign;
    const px = bone.a[0] + bone.ux * bone.stretch * x, py = bone.a[1] + bone.uy * bone.stretch * x;
    let far = Math.abs(y);
    if (k > 0) far = reach(k, px, py, nx, ny, far, 1);
    if (k < bones.length - 1) far = reach(k + 1, px, py, nx, ny, far, -1);
    return [px + nx * far, py + ny * far];
  };
  return (k, x, y) => {
    let j = 0, past = 0;
    if (k > 0 && x < folds[k].r) { j = k; past = x; }
    else if (k < bones.length - 1 && x > bones[k].length - folds[k + 1].r) { j = k + 1; past = x - bones[k].length; }
    if (!j) return straight(k, x, y);
    const { r, ax, ay, cx, cy } = folds[j], onBefore = bones[j - 1].length + past;
    if (past <= -r) return straight(j - 1, onBefore, y);
    if (past >= r) return straight(j, past, y);
    // The curve leaves the first bone and arrives on the second straight, turning most at the joint:
    // joint - (1 - t)^3 a + t^3 c. t is chosen so that along a straight limb nothing moves at all,
    // which means solving 2u^3 + 1.5u = past / r for u = t - 1/2.
    const q = past / r, root = Math.sqrt(q * q / 16 + 1 / 64), t = .5 + Math.cbrt(q / 4 + root) + Math.cbrt(q / 4 - root), m = 1 - t;
    let tx = m * m * ax + t * t * cx, ty = m * m * ay + t * t * cy;
    const size = Math.hypot(tx, ty);
    if (size < 1e-6) return straight(j - 1, onBefore, y);
    tx /= size; ty /= size;
    const px = joints[j][0] - m * m * m * ax + t * t * t * cx, py = joints[j][1] - m * m * m * ay + t * t * t * cy;
    const sign = (flip ? -y : y) < 0 ? -1 : 1, nx = -ty * sign, ny = tx * sign;
    let far = Math.abs(y);
    // Nothing reaches past the centre of the turn, where the body would fold back through itself.
    const turn = 2 * m * t * (ax * cy - ay * cx) / (3 * size * size * size) * sign;
    if (turn * far > 1) far = 1 / turn;
    far = reach(j, px, py, nx, ny, far, t < .5 ? -1 : 1);
    return [px + nx * far, py + ny * far];
  };
}

// opts: load ('barbell' …), glow (0…1, how hard the worked muscles are working right now), effort (muscle => 0…1).
function drawMotion(svg, move, phase, fill, opts = {}) {
  if (!svg.querySelector('defs')) svg.insertAdjacentHTML('afterbegin', `<defs>
    <radialGradient id="mfShade">
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
  // One piece, drawn along bone k of a chain. A far piece is faded toward the card, so the near side reads clearly.
  const piece = (name, chain, k, far) => {
    const shape = shapes[name];
    const path = (pts, closed) => {
      let d = '';
      for (let i = 0; i < pts.length; i += 2) {
        const p = chain(k, pts[i], pts[i + 1]);
        d += (i ? 'L' : 'M') + p[0].toFixed(2) + ' ' + p[1].toFixed(2);
      }
      return closed ? d + 'Z' : d;
    };
    // Where the light falls on each muscle: a point of its own, so it stays put as the piece bends.
    shape.lights = shape.lights || shape.regions.map(([, pts]) => {
      let ax = Infinity, ay = Infinity, bx = -Infinity, by = -Infinity;
      for (let i = 0; i < pts.length; i += 2) { ax = Math.min(ax, pts[i]); bx = Math.max(bx, pts[i]); ay = Math.min(ay, pts[i + 1]); by = Math.max(by, pts[i + 1]); }
      return [ax + (bx - ax) * .4, ay + (by - ay) * .3, Math.max(bx - ax, by - ay) * .8];
    });
    const g = el(root, 'g', {}), outline = path(shape.outline, true), clip = 'mfClip' + motionCount++;
    g.insertAdjacentHTML('beforeend', `<clipPath id="${clip}"><path d="${outline}"/></clipPath>`);
    // Skin a little beyond the piece, so that where it lies over another piece their muscles don't touch.
    el(g, 'path', { d: outline, fill: 'var(--body)', stroke: 'var(--body)', 'stroke-width': 1.4, 'stroke-linejoin': 'round' });
    // Everything else is clipped to the piece, so muscles can run to its edge.
    const inner = el(g, 'g', { 'clip-path': `url(#${clip})`, 'stroke-linejoin': 'round', 'stroke-linecap': 'round', fill: 'none' });
    shape.regions.forEach(([m, pts, detail], index) => {
      const d = path(pts, true), color = m ? fill(m) : 'var(--tissue)';
      const tension = m && opts.effort ? opts.effort(m) * (opts.glow || 0) : 0;
      // A soft glow in the muscle's own colour: wider rings are fainter.
      if (tension > 0 && !detail) [4.4, 3, 1.6].forEach(width => el(inner, 'path', { d, stroke: color, 'stroke-width': width, 'stroke-opacity': .13 * tension }));
      el(inner, 'path', { d, fill: color });
      if (m && !detail) {
        // Light from one side, so each muscle belly reads as rounded.
        const [lx, ly, radius] = shape.lights[index], c = chain(k, lx, ly), shade = 'mfShade' + motionCount++;
        inner.insertAdjacentHTML('beforeend', `<radialGradient id="${shade}" href="#mfShade" gradientUnits="userSpaceOnUse" cx="${c[0].toFixed(2)}" cy="${c[1].toFixed(2)}" r="${radius.toFixed(2)}"/>`);
        el(inner, 'path', { d, fill: `url(#${shade})` });
      }
      if (tension > 0) el(inner, 'path', { d, fill: '#fff', 'fill-opacity': .12 * tension });
      el(inner, 'path', { d, stroke: 'var(--body)', 'stroke-width': detail ? .35 : .7 });
    });
    shape.lines.forEach(pts => el(inner, 'path', { d: path(pts, false), stroke: 'var(--muscle)', 'stroke-width': .6 }));
    // A rim of skin around the piece (half of this width falls inside the clip).
    el(inner, 'path', { d: outline, stroke: 'var(--body)', 'stroke-width': 1.5 });
    if (far) el(g, 'path', { d: outline, fill: 'var(--card)', 'fill-opacity': .38, stroke: 'var(--card)', 'stroke-opacity': .38, 'stroke-width': 1.4, 'stroke-linejoin': 'round' });
  };
  const rigid = (name, a, b, flip, far) => piece(name, motionChain([a, b], [MF_BODY[name]], [], flip), 0, far);
  const mid = (a, b) => [(a[0] + b[0]) / 2, (a[1] + b[1]) / 2];
  if (move.view === 'front') {
    // Both sides face the viewer; the far side is the near side mirrored.
    const neck = mid(s.shoulder, s.farShoulder), pelvis = mid(s.hip, s.farHip);
    // Discs under the hips and shoulders close the gaps where the limbs turn against the torso.
    [[s.hip, 8.4], [s.farHip, 8.4], [s.shoulder, 7.6], [s.farShoulder, 7.6]].forEach(([p, r]) => dot(root, p, r, 'var(--body)'));
    [[s.hip, s.knee, s.ankle, false], [s.farHip, s.farKnee, s.farAnkle, true]].forEach(([hip, knee, ankle, flip]) => {
      const leg = motionChain([hip, knee, ankle], [MF_BODY.thigh, MF_BODY.shin], [MF_BEND.knee], flip);
      piece('shin', leg, 1); piece('thigh', leg, 0);
    });
    rigid('torso', neck, pelvis, false);
    rigid('head', s.head, neck, false);
    [[s.shoulder, s.elbow, s.hand, false], [s.farShoulder, s.farElbow, s.farHand, true]].forEach(([shoulder, elbow, hand, flip]) => {
      const arm = motionChain([shoulder, elbow, hand], [MF_BODY.upperArm, MF_BODY.forearm], [MF_BEND.elbow], flip);
      piece('forearm', arm, 1); piece('upperArm', arm, 0);
    });
  } else {
    // Lying face up, the front of the body is on the other side of every piece.
    const up = move.faceUp;
    const arm = (shoulder, elbow, hand, far) => {
      const chain = motionChain([shoulder, elbow, hand], [MF_BODY.upperArm, MF_BODY.forearm], [MF_BEND.elbow], up);
      piece('forearm', chain, 1, far); piece('upperArm', chain, 0, far);
    };
    // The trunk and a leg are one run of bones, so the hip bends like the knee does.
    const trunk = (hip, knee, ankle) => motionChain([s.shoulder, hip, knee, ankle], [MF_BODY.torso, MF_BODY.thigh, MF_BODY.shin], [MF_BEND.hip, MF_BEND.knee], up);
    const leg = (chain, ankle, toe, far) => { rigid('foot', ankle, toe, up, far); piece('shin', chain, 2, far); piece('thigh', chain, 1, far); };
    const near = trunk(s.hip, s.knee, s.ankle);
    arm(s.farShoulder, s.farElbow, s.farHand, true);
    leg(trunk(s.farHip, s.farKnee, s.farAnkle), s.farAnkle, s.farToe, true);
    rigid('head', s.head, s.shoulder, up);
    piece('torso', near, 0);
    leg(near, s.ankle, s.toe);
    arm(s.shoulder, s.elbow, s.hand);
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
