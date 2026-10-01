#!/usr/bin/env node
// Runs Tests/bridge.html in a real browser engine and adds what a page can't
// test by itself: events the browser marks as trusted, as WebKit's own wheel
// events are. Also runs Validation/figma-ctrl-wheel.js against a stand-in for
// Figma, so the console test is known to work before anyone pastes it.
//
//   node Tests/bridge.mjs              Chromium
//   node Tests/bridge.mjs webkit       Playwright's WebKit, closest to Safari
//
// Needs Playwright (npm i -D playwright, or PLAYWRIGHT=/path/to/playwright
// for one installed elsewhere). Nothing here ships in the app.
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const engine = process.argv[2] || 'chromium';
const playwright = await import(process.env.PLAYWRIGHT || 'playwright');

const types = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.mjs': 'text/javascript' };
const server = http.createServer((request, response) => {
  const file = path.join(root, decodeURIComponent(new URL(request.url, 'http://x').pathname));
  if (!file.startsWith(root) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) {
    response.writeHead(404).end();
    return;
  }
  response.writeHead(200, { 'content-type': types[path.extname(file)] || 'application/octet-stream' });
  fs.createReadStream(file).pipe(response);
});
await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
const base = `http://127.0.0.1:${server.address().port}`;

const results = [];
const check = (name, ok, detail = '') => results.push({ name, ok: !!ok, detail: String(detail) });
const browser = await playwright[engine].launch();
try {
  const page = await browser.newPage({ viewport: { width: 1200, height: 800 } });
  page.on('pageerror', (error) => check('no errors on the page', false, error.message));
  await page.goto(`${base}/Tests/bridge.html`);
  await page.waitForFunction(() => /^(PASSED|FAILED)/.test(document.title), null, { timeout: 20000 });
  results.push(...await page.evaluate(() => window.__results));

  // WebKit's own wheel events, trusted, and the bridge standing aside for
  // them. Each bridged step starts from the top of the page, since the
  // trusted wheel scrolls it; (200, 150) is then the middle of the canvas.
  const width = await page.evaluate(() => (window.visualViewport ? window.visualViewport.width : innerWidth));
  const bridged = (m) => page.evaluate(([w, m]) => {
    window.scrollTo(0, 0);
    return window.__safience.wheel(Object.assign({ width: w, dx: 0, dy: 0, guard: 'scroll' }, m));
  }, [width, m]);
  await page.evaluate(() => window.scrollTo(0, 0));
  const counted = await page.evaluate(() => window.__safience.state().trusted);
  await page.mouse.move(1100, 500);
  await page.mouse.wheel(0, 100);
  // The browser hands the event to the page on its own time.
  await page.waitForFunction((n) => window.__safience.state().trusted > n, counted);
  const during = await bridged({ x: 1100, y: 500, dy: 50 });
  check('while the system sends wheel events, the bridge stands aside', during === 'native', during);
  const pinch = await bridged({ x: 200, y: 150, dy: -5, ctrl: true, guard: 'pinch' });
  check('a pinch is not held back by a scroll', pinch === 'handled', pinch);
  const forced = await bridged({ x: 200, y: 150, dy: 5, force: true });
  check('"always" sends it anyway', forced === 'handled', forced);
  await page.waitForTimeout(300);
  const after = await bridged({ x: 200, y: 150, dy: 5 });
  check('once they stop, the bridge sends again', after === 'handled', after);
  const trusted = await page.evaluate(() => window.__safience.state().trusted);
  check('the system\'s wheel events are counted', trusted > 0, trusted);
  const told = await page.evaluate(() => window.__messages.some((m) => m.kind === 'wheel' && m.trusted > 0));
  check('and reported to the app', told);

  // The console test from Validation/, against a stand-in that zooms the way Figma does.
  const mock = await browser.newPage({ viewport: { width: 1200, height: 800 } });
  await mock.goto(`${base}/Tests/figma-mock.html`);
  const snippet = fs.readFileSync(path.join(root, 'Validation/figma-ctrl-wheel.js'), 'utf8');
  const verdict = await mock.evaluate(snippet);
  check('the Figma console test passes on a page that zooms on ctrl+wheel', verdict && verdict.pass === true, JSON.stringify(verdict));
  await mock.evaluate(() => { window.__ignoreWheel = true; });
  const refused = await mock.evaluate(snippet);
  check('and fails on one that doesn\'t', refused && refused.pass === false, JSON.stringify(refused));
  const plain = await browser.newPage({ viewport: { width: 1200, height: 800 } });
  await plain.goto(`${base}/Tests/figma-mock.html?noapi`);
  const fromToolbar = await plain.evaluate(snippet);
  check('without the plugin API it reads the toolbar\'s percentage', fromToolbar && fromToolbar.pass === true && fromToolbar.readFrom === 'toolbar',
    JSON.stringify(fromToolbar));
} finally {
  await browser.close();
  server.close();
}

let failed = 0;
for (const result of results) {
  if (!result.ok) failed += 1;
  console.log(`${result.ok ? 'PASS' : 'FAIL'} ${result.name}${result.ok || !result.detail ? '' : `  (${result.detail})`}`);
}
console.log(`\n${engine}: ${results.length - failed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
