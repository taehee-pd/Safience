// Does Figma zoom on a synthetic ctrl+wheel event?
//
// The iPad app's pinch bridge rests on this: it turns a trackpad pinch into
// wheel events with ctrlKey set, made by a script rather than the system
// (isTrusted is false), the way Chrome reports a pinch on a Mac. If Figma
// zooms on those, the bridge works; if it ignored untrusted events, nothing
// the app could send would zoom it.
//
// Run it in Safari on a Mac (where the app's WebKit comes from):
//   1. Safari › Settings › Advanced › "Show features for web developers".
//   2. Open a Figma design file at figma.com, click once on the canvas.
//   3. Develop › Show JavaScript Console, paste all of this, press Return.
// The same works on the iPad itself: connect it to the Mac, open the file in
// the app, and pick the app's page under Develop › (your iPad).
//
// It sends a pinch to twice the size in ten steps at the middle of the
// canvas, the way Chrome sends one, reads the zoom, then sends the same pinch
// back. PASS: the zoom went up by at least a tenth. How far it went is the
// page's own business (Figma in Safari goes half as far as Chrome's pinch
// asks), so it also prints `strength`, 1 when the zoom follows the pinch, and
// `pinchFactor`, what the site's adapter needs for it to follow (Adapters.swift).
// It reads the zoom from Figma's plugin API when the console has it, else
// from the zoom percentage in Figma's toolbar; when it can read neither, look
// at the canvas: it zooms in, then back out.
(async () => {
  const pause = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
  const frame = () => new Promise((resolve) => requestAnimationFrame(() => resolve()));

  const canvases = Array.from(document.querySelectorAll('canvas'))
    .map((canvas) => ({ canvas, box: canvas.getBoundingClientRect() }))
    .filter(({ box }) => box.width > 100 && box.height > 100)
    .sort((a, b) => b.box.width * b.box.height - a.box.width * a.box.height);
  if (!canvases.length) {
    const verdict = { pass: false, reason: 'No canvas on this page: open a design file first.' };
    console.log('FAIL', verdict.reason);
    return verdict;
  }
  const box = canvases[0].box;
  const x = Math.round(box.left + box.width / 2);
  const y = Math.round(box.top + box.height / 2);
  // What is under the pointer there, as the bridge picks it (bridge.js hitTest).
  const target = document.elementFromPoint(x, y) || canvases[0].canvas;

  function zoom() {
    try {
      const api = window.figma && window.figma.viewport;
      if (api && typeof api.zoom === 'number') return { value: api.zoom, from: 'plugin API' };
    } catch (_) {}
    for (const element of document.querySelectorAll('button, [role="button"], span, div')) {
      if (element.children.length) continue;
      const match = /^(\d{1,5})%$/.exec((element.textContent || '').trim());
      if (match) return { value: Number(match[1]) / 100, from: 'toolbar' };
    }
    return { value: null, from: 'nothing readable' };
  }

  async function pinch(scale, steps = 10) {
    const step = Math.pow(scale, 1 / steps);
    let taken = 0;
    for (let i = 0; i < steps; i++) {
      const event = new WheelEvent('wheel', {
        bubbles: true, cancelable: true, composed: true, view: window,
        clientX: x, clientY: y, screenX: x, screenY: y,
        deltaX: 0, deltaY: -100 * Math.log(step), deltaZ: 0, deltaMode: 0,
        ctrlKey: true,
      });
      if (!target.dispatchEvent(event)) taken += 1;
      await frame();
    }
    return taken;
  }

  const before = zoom();
  const taken = await pinch(2);
  await pause(500);
  const after = zoom();
  await pinch(0.5);
  await pause(300);

  const ratio = before.value && after.value ? after.value / before.value : null;
  const strength = ratio ? Math.log(ratio) / Math.log(2) : null;
  const verdict = {
    pass: ratio ? ratio >= 1.1 : null,
    before: before.value,
    after: after.value,
    strength: strength === null ? null : Math.round(strength * 100) / 100,
    pinchFactor: strength > 0 ? Math.round(100 / strength) : null,
    readFrom: after.from,
    eventsTakenByThePage: taken,
    target: target.tagName.toLowerCase() + (target.className && typeof target.className === 'string' ? '.' + target.className.split(' ')[0] : ''),
  };
  if (verdict.pass === null) {
    console.log('LOOK: the zoom could not be read. Did the canvas zoom in and back out? Events the page took:', taken, verdict);
  } else {
    console.log(verdict.pass ? 'PASS: Figma zooms on a synthetic ctrl+wheel.' : 'FAIL: the zoom did not change.', verdict);
  }
  return verdict;
})();
