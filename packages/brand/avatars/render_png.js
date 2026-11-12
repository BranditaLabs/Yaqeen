// Renders every SVG in <svgDir> to a 512×512 PNG with a transparent corner in <pngDir>.
// Needs Playwright + Chromium (preinstalled in CI images; PLAYWRIGHT_BROWSERS_PATH or a local install).
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

(async () => {
  const [svgDir, pngDir] = process.argv.slice(2);
  fs.mkdirSync(pngDir, { recursive: true });
  const exe = process.env.CHROMIUM_PATH || undefined;
  const browser = await chromium.launch(exe ? { executablePath: exe } : {});
  const page = await browser.newPage({ viewport: { width: 512, height: 512 } });
  for (const f of fs.readdirSync(svgDir).filter((n) => n.endsWith('.svg')).sort()) {
    const svg = fs.readFileSync(path.join(svgDir, f), 'utf8');
    await page.setContent(`<html><body style="margin:0;background:transparent">${svg}</body></html>`);
    await page.locator('svg').screenshot({ path: path.join(pngDir, f.replace('.svg', '.png')), omitBackground: true });
  }
  await browser.close();
})();
