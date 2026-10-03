// Renders each frame in WebKit at 2064 by 2752: node render.mjs. Captures go in raw/,
// frames come out next to this folder, in Marketing/AppStore; frames.json says which capture and which line each frame has.
// Playwright from PLAYWRIGHT (a path to its index.mjs) or an installed `playwright` package.
const { webkit } = await import(process.env.PLAYWRIGHT ?? 'playwright');
import { readFileSync } from 'node:fs';
const here = new URL('.', import.meta.url).pathname;
const frames = JSON.parse(readFileSync(here + 'frames.json', 'utf8'));
const browser = await webkit.launch();
const page = await browser.newPage({ viewport: { width: 2064, height: 2752 }, deviceScaleFactor: 1 });
for (const f of frames) {
  await page.goto('file://' + here + 'frame.html?' + new URLSearchParams(f.params));
  await page.waitForFunction(() => [...document.images].every(i => i.complete && i.naturalWidth > 0));
  await page.evaluate(() => Promise.all([...document.images].map(i => i.decode().catch(() => {}))));
  await page.waitForTimeout(500);
  const r = await page.evaluate(() => { const b = document.getElementById('shot').getBoundingClientRect(); return [b.width, b.height, b.bottom]; });
  console.log(f.name, 'screen', r[0].toFixed(1) + ' x ' + r[1].toFixed(1), 'ratio', (r[0] / r[1]).toFixed(4), '(13-inch: ' + (2064 / 2752).toFixed(4) + ')', 'shown', Math.round(100 * Math.min(1, (2752 - (r[2] - r[1])) / r[1])) + '%');
  await page.screenshot({ path: here + '../' + f.name + '.png' });
}
await browser.close();
