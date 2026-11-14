// Records the contracting-muscle animation as GIFs: one per muscle and one per example exercise.
//   node scripts/mockups/muscle-gifs.js <output folder> [light|dark]
// Needs ffmpeg. Each page of cards is stepped frame by frame, then cut into one GIF per card.
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');
const { chromium } = require('playwright');

const out = path.resolve(process.argv[2] || 'muscle-gifs');
const mode = process.argv[3] || 'light';
const FPS = 20, PERIOD = 2.2, DENSITY = 1.5, W = 540, H = 620, COLUMNS = 6;

(async () => {
  fs.mkdirSync(out, { recursive: true });
  const browser = await chromium.launch();
  const page = await browser.newPage({ deviceScaleFactor: DENSITY, viewport: { width: W * COLUMNS, height: H } });
  for (const set of ['muscles', 'exercises']) {
    const frames = fs.mkdtempSync(path.join(os.tmpdir(), 'muscle-gifs-'));
    await page.goto(`file://${path.join(__dirname, 'muscle-gifs.html')}?set=${set}&mode=${mode}`);
    await page.evaluate(() => document.fonts.ready);
    const cards = await page.evaluate(() => window.cards);
    const count = Math.round(FPS * PERIOD);
    for (let i = 0; i < count; i++) {
      await page.evaluate(t => window.frame(t), i / FPS);
      await page.screenshot({ path: path.join(frames, `f${String(i).padStart(3, '0')}.png`), fullPage: true });
    }
    cards.forEach((id, index) => {
      const x = (index % COLUMNS) * W * DENSITY, y = Math.floor(index / COLUMNS) * H * DENSITY;
      const name = mode === 'dark' ? `${id}-dark.gif` : `${id}.gif`;
      execFileSync('ffmpeg', ['-y', '-loglevel', 'error', '-framerate', String(FPS), '-i', path.join(frames, 'f%03d.png'), '-vf',
        `crop=${W * DENSITY}:${H * DENSITY}:${x}:${y},split[a][b];[a]palettegen=max_colors=96:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle`,
        path.join(out, name)]);
    });
    fs.rmSync(frames, { recursive: true });
  }
  await browser.close();
})();
