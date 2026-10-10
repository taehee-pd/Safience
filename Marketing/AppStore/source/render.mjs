// Renders each frame in WebKit: node render.mjs [frames file], frames.json (the iPad's) when none is given.
// A frames file is a list of frames, or {w, h, out, params, frames, also}: the picture's size, the folder
// in Marketing/AppStore it goes in, what every frame shares, and other sizes to scale it to ({out, w, h}).
// Playwright from PLAYWRIGHT (a path to its index.mjs) or an installed `playwright` package.
const { webkit } = await import(process.env.PLAYWRIGHT ?? 'playwright');
import { readFileSync, mkdirSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
const here = new URL('.', import.meta.url).pathname;
const data = JSON.parse(readFileSync(here + (process.argv[2] ?? 'frames.json'), 'utf8'));
const { w = 2064, h = 2752, out = '', params = {}, frames, also = [] } = Array.isArray(data) ? { frames: data } : data;
const folder = (name) => { const dir = here + '../' + (name ? name + '/' : ''); mkdirSync(dir, { recursive: true }); return dir; };
const browser = await webkit.launch();
const page = await browser.newPage({ viewport: { width: w, height: h }, deviceScaleFactor: 1 });
for (const f of frames) {
  const p = { ...params, ...f.params, w, h };
  await page.goto('file://' + here + 'frame.html?' + new URLSearchParams(p));
  await page.waitForFunction(() => [...document.images].every(i => i.complete && i.naturalWidth > 0));
  await page.evaluate(() => Promise.all([...document.images].map(i => i.decode().catch(() => {}))));
  await page.waitForTimeout(500);
  const r = await page.evaluate(() => { const b = document.querySelector('.screen').getBoundingClientRect(); return [b.width, b.height, b.top, b.bottom]; });
  const [, , sw, sh] = (p.hole ?? '118,124,2064,2752').split(',').map(Number);
  console.log(f.name, 'screen', r[0].toFixed(1) + ' x ' + r[1].toFixed(1), 'ratio', (r[0] / r[1]).toFixed(4), '(screen: ' + (sw / sh).toFixed(4) + ')',
    'shown', Math.round(100 * Math.min(1, (h - r[2]) / r[1])) + '%', 'below', Math.round(h - r[3]) + 'px');
  const file = folder(out) + f.name + '.png';
  await page.screenshot({ path: file });
  // Opaque: App Store Connect rejects a screenshot with any transparency, and a pixel on
  // the device's edge can come out of the compositor a shade short of it.
  execFileSync('python3', ['-c', "import sys; from PIL import Image; Image.open(sys.argv[1]).convert('RGB').save(sys.argv[1])", file]);
  // Smaller iPhones: the same picture scaled, as Apple's sizes are within a pixel of one shape.
  for (const a of also) execFileSync('sips', ['-z', String(a.h), String(a.w), file, '--out', folder(a.out) + f.name + '.png'], { stdio: 'ignore' });
}
await browser.close();
