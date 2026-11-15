// Records the animated exercise figure as one GIF per exercise, with the muscle roles from ExerciseLibrary.swift.
//   node scripts/mockups/exercise-gifs.js <output folder> [light|dark] [name filter]
// Needs ffmpeg, and scripts/mockups/motion-data.js up to date (scripts/motion/dump.sh).
const fs = require('fs');
const os = require('os');
const path = require('path');
const vm = require('vm');
const { execFileSync } = require('child_process');
const { chromium } = require('playwright');

const out = path.resolve(process.argv[2] || 'exercise-gifs');
const mode = process.argv[3] || 'light';
const filter = (process.argv[4] || '').toLowerCase();
// A GIF frame lasts a whole number of hundredths of a second, and browsers slow anything under 2 to
// a tenth of a second, so 3 hundredths (33 frames a second) is the smoothest that plays everywhere.
const FPS = 100 / 3, DENSITY = 1.5, W = 440, H = 470, COLUMNS = 6, PER_PAGE = 12;

const sandbox = {};
vm.runInNewContext(fs.readFileSync(path.join(__dirname, 'motion-data.js'), 'utf8') + '\nthis.MOTION = MOTION;', sandbox);
const list = names => (names || '').split(',').map(n => n.trim().replace('.', '')).filter(Boolean);
const exercises = [];
for (const line of fs.readFileSync(path.join(__dirname, '../../Sources/Overlo4d/Gym/ExerciseLibrary.swift'), 'utf8').split('\n')) {
  const found = line.match(/^\s*e\("([^"]+)",\s*[^,]+,\s*[^,]+,\s*\[([^\]]*)\](?:,\s*\[([^\]]*)\])?/);
  if (!found || !sandbox.MOTION.exercises[found[1]] || !found[1].toLowerCase().includes(filter)) continue;
  const [move, load] = sandbox.MOTION.exercises[found[1]];
  const id = found[1].toLowerCase().replace(/'/g, '').replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
  exercises.push({ id, title: found[1], move, load, p: list(found[2]), s: list(found[3]), t: list((line.match(/tertiary:\s*\[([^\]]*)\]/) || [])[1]),
    duration: sandbox.MOTION.moves[move].duration });
}

(async () => {
  fs.mkdirSync(out, { recursive: true });
  const browser = await chromium.launch();
  const page = await browser.newPage({ deviceScaleFactor: DENSITY, viewport: { width: W * COLUMNS, height: H } });
  await page.goto(`file://${path.join(__dirname, 'exercise-gifs.html')}?mode=${mode}`);
  await page.evaluate(() => document.fonts.ready);
  // One loop is as long as the movement, so exercises are recorded together with others of the same length.
  for (const duration of [...new Set(exercises.map(e => e.duration))]) {
    const group = exercises.filter(e => e.duration === duration);
    for (let start = 0; start < group.length; start += PER_PAGE) {
      const cards = group.slice(start, start + PER_PAGE);
      const frames = fs.mkdtempSync(path.join(os.tmpdir(), 'exercise-gifs-'));
      await page.evaluate(c => window.setup(c), cards);
      // The last frame stops one step short of the first, so the loop has no seam.
      const count = Math.round(FPS * duration);
      for (let i = 0; i < count; i++) {
        await page.evaluate(t => window.frame(t), i * duration / count);
        await page.screenshot({ path: path.join(frames, `f${String(i).padStart(3, '0')}.png`), fullPage: true });
      }
      // Every card is cut from the same frames in one pass, each with its own palette of 128 colours
      // made from the whole loop, so a colour never changes from one frame to the next.
      const graph = [`[0:v]split=${cards.length}${cards.map((_, i) => `[c${i}]`).join('')}`];
      cards.forEach((card, i) => {
        const x = (i % COLUMNS) * W * DENSITY, y = Math.floor(i / COLUMNS) * H * DENSITY;
        graph.push(`[c${i}]crop=${W * DENSITY}:${H * DENSITY}:${x}:${y},split[a${i}][b${i}]`,
          `[a${i}]palettegen=max_colors=128:stats_mode=full[p${i}]`, `[b${i}][p${i}]paletteuse=dither=none:diff_mode=rectangle[o${i}]`);
      });
      execFileSync('ffmpeg', ['-y', '-loglevel', 'error', '-framerate', '100/3', '-i', path.join(frames, 'f%03d.png'), '-filter_complex', graph.join(';'),
        ...cards.flatMap((card, i) => ['-map', `[o${i}]`, path.join(out, `${card.id}.gif`)])]);
      fs.rmSync(frames, { recursive: true });
    }
  }
  await browser.close();
  console.log(`${exercises.length} GIFs in ${out}`);
})();
