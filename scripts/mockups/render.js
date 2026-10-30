// Renders the README mockups to docs/images with Playwright's Chromium.
//   node scripts/mockups/render.js
const path = require('path');
const { chromium } = require('playwright');

const here = __dirname;
const out = path.join(here, '../../docs/images');

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ deviceScaleFactor: 3, viewport: { width: 1400, height: 1000 } });

  await page.goto('file://' + path.join(here, 'screens.html'));
  await page.evaluate(() => document.fonts.ready);
  for (const phone of await page.$$('.phone')) {
    const id = await phone.getAttribute('id');
    await phone.screenshot({ path: path.join(out, `screen-${id}.png`) });
  }

  // Widgets: one image of all of them.
  await page.goto('file://' + path.join(here, 'widgets.html'));
  await page.evaluate(() => document.fonts.ready);
  await page.setViewportSize({ width: 2200, height: 1000 });
  await page.screenshot({ path: path.join(out, 'widgets.png'), fullPage: true });

  await browser.close();
})();
