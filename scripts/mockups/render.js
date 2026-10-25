// Renders the README mockups and banner to docs/images with Playwright's Chromium.
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
  // Transparent page so the rounded screen corners stay clear.
  await page.addStyleTag({ content: 'body { background: transparent !important; }' });
  for (const phone of await page.$$('.phone')) {
    const id = await phone.getAttribute('id');
    await phone.screenshot({ path: path.join(out, `screen-${id}.png`), omitBackground: true });
  }

  const banner = await browser.newPage({ deviceScaleFactor: 2, viewport: { width: 1280, height: 640 } });
  await banner.goto('file://' + path.join(here, 'banner.html'));
  await banner.evaluate(() => document.fonts.ready);
  await banner.screenshot({ path: path.join(out, 'banner.png') });

  await browser.close();
})();
