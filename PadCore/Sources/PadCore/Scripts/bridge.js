// The app's side of every page, but a hands-off one (HandsOff.swift).
//
// It runs at document start in the app's own content world, in the main
// frame only. The page can't see its variables or call it; what the page
// sees is only what a Mac's WebKit would show it: wheel events with the
// pointer's position and the keys held, Tab and the arrows when the system
// would otherwise keep them, and a stylesheet.
//
// The app calls in through window.__safience (Page.swift): wheel() for every
// step of a trackpad scroll or pinch, key() for a relayed key, unsaved()
// before a tab is frozen, state() for Diagnostics. It hears back through the
// "safience" message handler: where the focus is, whether there is a
// password field, whether WebKit's own wheel events are arriving, the
// cursor the page asks for under the pointer, and the icons it names.
(() => {
  'use strict';
  if (window.__safience) return;

  const config = window.__safienceConfig || {};
  delete window.__safienceConfig;

  // A second guard behind the app's own: it never puts this script on a
  // hands-off host, and if it ever did, the script would do nothing there.
  const handsOff = config.handsOff || ['accounts.google.com'];
  const host = location.hostname.toLowerCase().replace(/\.+$/, '');
  if (handsOff.some((h) => host === h || host.endsWith('.' + h))) return;

  const post = (message) => {
    try { window.webkit.messageHandlers.safience.postMessage(message); } catch (_) {}
  };

  // MARK: Style

  function addStyle(css) {
    if (!css) return;
    const style = document.createElement('style');
    style.textContent = css;
    const place = () => (document.head || document.documentElement).prepend(style);
    if (document.documentElement) {
      place();
    } else {
      new MutationObserver((_, observer) => {
        if (!document.documentElement) return;
        observer.disconnect();
        place();
      }).observe(document, { childList: true });
    }
  }
  addStyle(config.css);

  // MARK: Where the pointer is

  // A point in the web view, in points from its top left, as the place on
  // the page under it. The visual viewport says how many CSS pixels a point
  // is (WebKit may have scaled a wide desktop page down to fit) and where
  // the visible part sits; clientX and clientY are measured from the layout
  // viewport, as on a Mac.
  function clientPoint(x, y, viewWidth) {
    const vv = window.visualViewport;
    const width = vv ? vv.width : window.innerWidth;
    const scale = viewWidth > 0 ? width / viewWidth : 1;
    return {
      x: (vv ? vv.offsetLeft : 0) + x * scale,
      y: (vv ? vv.offsetTop : 0) + y * scale,
    };
  }

  // The element under a point, through open shadow roots and into frames of
  // the same origin, with the point in that element's own document. A frame
  // from another origin can't be reached from here, so the event goes to the
  // frame's element; a hands-off frame, such as Google's sign-in button, is
  // always another origin.
  function hitTest(cx, cy) {
    let doc = document;
    let view = window;
    let x = cx;
    let y = cy;
    let element = doc.elementFromPoint(x, y);
    for (let depth = 0; element && depth < 8; depth++) {
      while (element.shadowRoot) {
        const inner = element.shadowRoot.elementFromPoint(x, y);
        if (!inner || inner === element) break;
        element = inner;
      }
      if (element.tagName !== 'IFRAME' && element.tagName !== 'FRAME') break;
      let inner = null;
      try { inner = element.contentDocument; } catch (_) {}
      if (!inner) break;
      const box = element.getBoundingClientRect();
      x -= box.left + element.clientLeft;
      y -= box.top + element.clientTop;
      doc = inner;
      view = element.contentWindow;
      element = doc.elementFromPoint(x, y);
    }
    return { element: element || doc.documentElement, x, y, view };
  }

  // MARK: Wheel

  // When WebKit's own wheel events last arrived: a plain one (two-finger
  // scroll) and one with ctrlKey (a pinch, should WebKit ever send them).
  // While they arrive, the bridge's own would be the same scroll twice, so
  // it stands aside (see WheelMode.auto).
  const recent = { plain: -1e9, ctrl: -1e9 };
  const counts = { trusted: 0, bridged: 0 };
  let reported = -1e9;
  window.addEventListener('wheel', (event) => {
    if (!event.isTrusted) return;
    const now = performance.now();
    recent[event.ctrlKey ? 'ctrl' : 'plain'] = now;
    counts.trusted += 1;
    if (now - reported > 250) {
      reported = now;
      post({ kind: 'wheel', trusted: counts.trusted });
    }
  }, { capture: true, passive: true });

  const quiet = 150;

  // m: { x, y, width, dx, dy, ctrl, alt, shift, meta, guard, force }
  // guard 'scroll' stands aside for WebKit's plain wheel events, 'pinch' for
  // its ctrl ones. Returns 'native' when it stood aside, 'handled' when the
  // page took the event, 'scrolled' when it didn't and the bridge scrolled
  // what a browser would, 'ignored' when there was nothing to scroll.
  function wheel(m) {
    const now = performance.now();
    if (!m.force && now - recent[m.guard === 'pinch' ? 'ctrl' : 'plain'] < quiet) return 'native';
    const point = clientPoint(m.x, m.y, m.width);
    const hit = hitTest(point.x, point.y);
    const Wheel = hit.view.WheelEvent || WheelEvent;
    const event = new Wheel('wheel', {
      bubbles: true,
      cancelable: true,
      composed: true,
      view: hit.view,
      detail: 0,
      clientX: hit.x,
      clientY: hit.y,
      screenX: point.x + (window.screenX || 0),
      screenY: point.y + (window.screenY || 0),
      deltaX: m.dx || 0,
      deltaY: m.dy || 0,
      deltaZ: 0,
      deltaMode: 0,
      ctrlKey: !!m.ctrl,
      altKey: !!m.alt,
      shiftKey: !!m.shift,
      metaKey: !!m.meta,
    });
    counts.bridged += 1;
    if (!hit.element.dispatchEvent(event)) return 'handled';
    // A wheel with ctrlKey zooms in a desktop browser; the page didn't take
    // it, and the page's zoom stays where it is (ZoomLock).
    if (m.ctrl) return 'ignored';
    return scrollFrom(hit.element, m.dx || 0, m.dy || 0) ? 'scrolled' : 'ignored';
  }

  // MARK: Scrolling, as a browser does when the page doesn't take the wheel

  function parentOf(node) {
    if (node.parentElement) return node.parentElement;
    const root = node.getRootNode && node.getRootNode();
    return root && root.host ? root.host : null;
  }

  function canScroll(element, axis, delta) {
    if (!delta) return false;
    const style = element.ownerDocument.defaultView.getComputedStyle(element);
    const overflow = axis === 'y' ? style.overflowY : style.overflowX;
    if (!/^(auto|scroll|overlay)$/.test(overflow)) return false;
    if (axis === 'y') {
      if (element.scrollHeight <= element.clientHeight + 1) return false;
      return delta > 0 ? element.scrollTop + element.clientHeight < element.scrollHeight - 1 : element.scrollTop > 0;
    }
    if (element.scrollWidth <= element.clientWidth + 1) return false;
    return delta > 0 ? element.scrollLeft + element.clientWidth < element.scrollWidth - 1 : element.scrollLeft > 0;
  }

  // Whether the element is a scroller that keeps a scroll from carrying on
  // to the ones around it (overscroll-behavior: contain or none).
  function contains(element, axis) {
    const style = element.ownerDocument.defaultView.getComputedStyle(element);
    const overflow = axis === 'y' ? style.overflowY : style.overflowX;
    if (!/^(auto|scroll|overlay)$/.test(overflow)) return false;
    const behaviour = axis === 'y' ? style.overscrollBehaviorY : style.overscrollBehaviorX;
    return behaviour === 'contain' || behaviour === 'none';
  }

  // At once, whatever scroll-behavior the page set: each wheel step is a
  // small move of its own, and smooth scrolling every one of them lags.
  function move(target, left, top) {
    try {
      target.scrollBy({ left, top, behavior: 'instant' });
    } catch (_) {
      target.scrollBy(left, top);
    }
  }

  function documentCanScroll(doc, axis, delta) {
    if (!delta) return false;
    const view = doc.defaultView;
    const root = doc.scrollingElement || doc.documentElement;
    const rootStyle = view.getComputedStyle(doc.documentElement);
    const bodyStyle = doc.body ? view.getComputedStyle(doc.body) : null;
    const hidden = (style) => style && (axis === 'y' ? style.overflowY : style.overflowX) === 'hidden';
    if (hidden(rootStyle) || (hidden(bodyStyle) && !/^(auto|scroll)$/.test(axis === 'y' ? rootStyle.overflowY : rootStyle.overflowX))) return false;
    if (axis === 'y') {
      const max = root.scrollHeight - view.innerHeight;
      return delta > 0 ? view.scrollY < max - 1 : view.scrollY > 0;
    }
    const max = root.scrollWidth - view.innerWidth;
    return delta > 0 ? view.scrollX < max - 1 : view.scrollX > 0;
  }

  // Scrolls the nearest element under the pointer that can still go that
  // way, each axis on its own, then the document: scroll chaining, as in
  // every desktop browser. True when anything moved.
  function scrollFrom(start, dx, dy) {
    let leftX = dx;
    let leftY = dy;
    let moved = false;
    const doc = start.ownerDocument;
    for (let element = start; element && (leftX || leftY); element = parentOf(element)) {
      if (element === doc.documentElement || element === doc.body || element === doc.scrollingElement) break;
      const x = canScroll(element, 'x', leftX) ? leftX : 0;
      const y = canScroll(element, 'y', leftY) ? leftY : 0;
      if (x || y) {
        move(element, x, y);
        moved = true;
      }
      if (x || contains(element, 'x')) leftX = 0;
      if (y || contains(element, 'y')) leftY = 0;
    }
    const x = documentCanScroll(doc, 'x', leftX) ? leftX : 0;
    const y = documentCanScroll(doc, 'y', leftY) ? leftY : 0;
    if (x || y) {
      move(doc.defaultView, x, y);
      moved = true;
    }
    return moved;
  }

  // MARK: Keys

  function deepActive() {
    let element = document.activeElement;
    for (let depth = 0; element && depth < 8; depth++) {
      if (element.shadowRoot && element.shadowRoot.activeElement) {
        element = element.shadowRoot.activeElement;
        continue;
      }
      if (element.tagName === 'IFRAME' || element.tagName === 'FRAME') {
        let inner = null;
        try { inner = element.contentDocument; } catch (_) {}
        if (inner && inner.activeElement) {
          element = inner.activeElement;
          continue;
        }
      }
      break;
    }
    return element;
  }

  const textTypes = /^(|text|search|url|tel|email|password|number|date|datetime-local|month|time|week)$/;

  function editable(element) {
    if (!element) return false;
    if (element.isContentEditable) return true;
    if (element.tagName === 'TEXTAREA') return !element.readOnly && !element.disabled;
    if (element.tagName === 'INPUT') {
      return textTypes.test((element.getAttribute('type') || '').toLowerCase()) && !element.readOnly && !element.disabled;
    }
    return false;
  }

  // A field someone can see. Pages that handle their own keys often keep the
  // focus in a field of a pixel or two, or a transparent one, to catch typing
  // and the clipboard; the arrows are the page's there, not the cursor's.
  function shown(element) {
    const box = element.getBoundingClientRect();
    const style = element.ownerDocument.defaultView.getComputedStyle(element);
    return box.width >= 4 && box.height >= 4 && style.visibility !== 'hidden' && Number(style.opacity) > 0.05;
  }

  const tabbable = 'a[href], area[href], button, input, select, textarea, iframe, summary, [tabindex], [contenteditable]';

  function focusables(doc) {
    const view = doc.defaultView;
    const all = Array.from(doc.querySelectorAll(tabbable)).filter((element) => {
      if (element.tabIndex < 0 || element.disabled) return false;
      if (element.tagName === 'INPUT' && (element.getAttribute('type') || '').toLowerCase() === 'hidden') return false;
      if (element.closest('[inert]')) return false;
      const style = view.getComputedStyle(element);
      if (style.visibility === 'hidden' || style.display === 'none') return false;
      return element.getClientRects().length > 0;
    });
    const ordered = all.filter((e) => e.tabIndex > 0).sort((a, b) => a.tabIndex - b.tabIndex);
    return ordered.concat(all.filter((e) => e.tabIndex === 0));
  }

  // What Tab does when the page lets it: the next field in tab order, round
  // to the first after the last, its text selected as a browser selects it.
  function moveFocus(from, backwards) {
    const doc = (from && from.ownerDocument) || document;
    const list = focusables(doc);
    if (!list.length) return false;
    const at = list.indexOf(from);
    const next = at < 0
      ? list[backwards ? list.length - 1 : 0]
      : list[(at + (backwards ? -1 : 1) + list.length) % list.length];
    next.focus();
    if (next.tagName === 'INPUT' && textTypes.test((next.getAttribute('type') || '').toLowerCase())) {
      try { next.select(); } catch (_) {}
    }
    return true;
  }

  const legacyCodes = { Tab: 9, ArrowLeft: 37, ArrowUp: 38, ArrowRight: 39, ArrowDown: 40 };

  function keyEvent(view, type, m) {
    const Keyboard = view.KeyboardEvent || KeyboardEvent;
    const event = new Keyboard(type, {
      key: m.key,
      code: m.code || m.key,
      bubbles: true,
      cancelable: true,
      composed: true,
      view,
      shiftKey: !!m.shift,
      altKey: !!m.alt,
      ctrlKey: !!m.ctrl,
      metaKey: !!m.meta,
    });
    // keyCode and which can't be given to the constructor; older code
    // still reads them.
    const code = legacyCodes[m.key] || 0;
    for (const name of ['keyCode', 'which']) {
      try { Object.defineProperty(event, name, { get: () => code }); } catch (_) {}
    }
    return event;
  }

  // m: { key: 'Tab' | 'ArrowUp' | ..., code, shift, alt, ctrl, meta }
  // The key goes to the focused element as keydown and keyup. When the page
  // doesn't take it, it does what a browser would: Tab moves the focus, an
  // arrow outside a text field scrolls. Returns 'handled' or 'default'.
  function key(m) {
    const target = deepActive() || document.body || document.documentElement;
    const view = target.ownerDocument.defaultView;
    const proceed = target.dispatchEvent(keyEvent(view, 'keydown', m));
    if (proceed) {
      if (m.key === 'Tab') {
        moveFocus(target, !!m.shift);
      } else if (!editable(target)) {
        const step = m.alt ? view.innerHeight * 0.875 : 40;
        const dx = m.key === 'ArrowLeft' ? -step : m.key === 'ArrowRight' ? step : 0;
        const dy = m.key === 'ArrowUp' ? -step : m.key === 'ArrowDown' ? step : 0;
        scrollFrom(target, dx, dy);
      }
    }
    target.dispatchEvent(keyEvent(view, 'keyup', m));
    reportFocus();
    return proceed ? 'default' : 'handled';
  }

  // MARK: Reports

  let editing = null;
  function reportFocus() {
    const element = deepActive();
    const now = !!element && editable(element) && shown(element);
    if (now === editing) return;
    editing = now;
    post({ kind: 'focus', editing: now });
  }
  document.addEventListener('focusin', () => setTimeout(reportFocus, 0), true);
  document.addEventListener('focusout', () => setTimeout(reportFocus, 0), true);

  // A password field makes a sign-in page wherever it is (SignIn.swift).
  let password = null;
  let pending = 0;
  function checkPassword() {
    pending = 0;
    const present = !!document.querySelector('input[type="password" i]');
    if (present === password) return;
    password = present;
    post({ kind: 'password', present });
  }
  function soon() {
    if (!pending) pending = setTimeout(checkPassword, 400);
  }
  function watch() {
    checkPassword();
    new MutationObserver(soon).observe(document.documentElement, {
      childList: true, subtree: true, attributes: true, attributeFilter: ['type'],
    });
  }
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', watch, { once: true });
  } else {
    watch();
  }

  // MARK: The cursor the page asks for

  // WebKit on iPad shows the system pointer whatever cursor a page sets,
  // but for the text beam over text. A page's own cursor image (Figma
  // draws even its arrow) is drawn by the app instead (Pointer.swift):
  // here the cursor under the pointer is read, its image drawn once to a
  // PNG, and the app told whenever it changes. 'none' hides the pointer;
  // any other keyword leaves the system's.
  const largestCursor = 128;

  // `cursor` as getComputedStyle gives it: images, each a url() or an
  // image-set() with an optional hotspot, then a keyword, comma separated:
  // url("data:…") 4 4, auto. A data URL can hold brackets and quotes, so
  // the value is read a character at a time rather than split.
  function parseCursor(value) {
    const text = String(value || '');
    const images = [];
    let i = 0;
    const space = () => { while (i < text.length && /\s/.test(text[i])) i++; };
    const starts = (word) => text.slice(i, i + word.length).toLowerCase() === word;
    const quoted = () => {
      const quote = text[i++];
      let out = '';
      while (i < text.length && text[i] !== quote) {
        if (text[i] === '\\' && i + 1 < text.length) i++;
        out += text[i++];
      }
      i++;
      return out;
    };
    const url = () => {
      space();
      let out = '';
      if (text[i] === '"' || text[i] === "'") {
        out = quoted();
      } else {
        while (i < text.length && text[i] !== ')') out += text[i++];
        out = out.trim();
      }
      space();
      if (text[i] === ')') i++;
      return out;
    };
    for (;;) {
      space();
      const candidates = [];
      if (starts('url(')) {
        i += 4;
        candidates.push({ url: url(), density: 1 });
      } else if (starts('image-set(') || starts('-webkit-image-set(')) {
        i += starts('image-set(') ? 10 : 18;
        while (i < text.length) {
          space();
          let source = null;
          if (starts('url(')) {
            i += 4;
            source = url();
          } else if (text[i] === '"' || text[i] === "'") {
            source = quoted();
          }
          // The rest of this choice: its density (2x, 2dppx, 192dpi), a type().
          let rest = '';
          let depth = 0;
          while (i < text.length && !(depth === 0 && (text[i] === ',' || text[i] === ')'))) {
            if (text[i] === '(') depth++;
            if (text[i] === ')') depth--;
            rest += text[i++];
          }
          const found = /(\d*\.?\d+)(x|dppx|dpi|dpcm)\b/i.exec(rest);
          let density = 1;
          if (found) {
            const n = Number(found[1]);
            const unit = found[2].toLowerCase();
            density = unit === 'dpi' ? n / 96 : unit === 'dpcm' ? n * 2.54 / 96 : n;
          }
          if (source && density > 0) candidates.push({ url: source, density });
          if (text[i] === ',') {
            i++;
            continue;
          }
          if (text[i] === ')') i++;
          break;
        }
      } else {
        break;
      }
      space();
      const hotspot = /^(-?\d*\.?\d+)(?:px)?\s+(-?\d*\.?\d+)(?:px)?/.exec(text.slice(i, i + 64));
      let x = 0;
      let y = 0;
      if (hotspot) {
        x = Number(hotspot[1]);
        y = Number(hotspot[2]);
        i += hotspot[0].length;
      }
      if (candidates.length) images.push({ candidates, x, y });
      space();
      if (text[i] !== ',') break;
      i++;
    }
    const keyword = text.slice(i).replace(/^[\s,]+/, '').trim().toLowerCase() || 'auto';
    return { images, keyword };
  }

  // Of an image set, the one at the screen's density or the nearest above
  // it, as a browser picks.
  function pick(candidates) {
    const want = window.devicePixelRatio || 1;
    const sorted = candidates.slice().sort((a, b) => a.density - b.density);
    return sorted.find((c) => c.density >= want) || sorted[sorted.length - 1];
  }

  // One image of a cursor, drawn to a PNG at the screen's density, so the
  // app gets a picture it can show whatever the page gave (an SVG, an image
  // set). Null when it can't be: it didn't load, it is bigger than a cursor
  // may be, or it comes from another site that doesn't let it be read.
  function drawCursor(image) {
    const choice = pick(image.candidates);
    return new Promise((resolve) => {
      const picture = new Image();
      if (/^https?:/i.test(choice.url)) picture.crossOrigin = 'anonymous';
      picture.onload = () => {
        const width = (picture.naturalWidth || 32) / choice.density;
        const height = (picture.naturalHeight || 32) / choice.density;
        if (!(width > 0 && height > 0) || width > largestCursor || height > largestCursor) {
          resolve(null);
          return;
        }
        const scale = Math.min(Math.max(window.devicePixelRatio || 1, 1), 3);
        const canvas = document.createElement('canvas');
        canvas.width = Math.max(1, Math.round(width * scale));
        canvas.height = Math.max(1, Math.round(height * scale));
        try {
          canvas.getContext('2d').drawImage(picture, 0, 0, canvas.width, canvas.height);
          resolve({
            image: canvas.toDataURL('image/png'),
            width,
            height,
            scale,
            x: Math.min(Math.max(image.x, 0), width),
            y: Math.min(Math.max(image.y, 0), height),
          });
        } catch (_) {
          resolve(null);
        }
      };
      picture.onerror = () => resolve(null);
      picture.src = choice.url;
    });
  }

  // What the app hears for a cursor value: the first of its images that
  // can be drawn, with an id of its own, or else its keyword.
  // Ids start from a number of this document's own, so a document's id is
  // never another's: one from the back-forward cache comes back with ids
  // the app may still have pictures for, and must not get another page's.
  let nextCursor = Math.floor(Math.random() * 2 ** 30) * 2 ** 20 + 1;
  async function resolveCursor(value) {
    const parsed = parseCursor(value);
    for (const image of parsed.images) {
      const drawn = await drawCursor(image);
      if (drawn) return Object.assign({ id: nextCursor++ }, drawn);
    }
    return { keyword: parsed.keyword };
  }

  // Each value is looked at once; its picture goes to the app once, and
  // after that its id stands for it. Both are forgotten together past 64
  // values (the set of pictures sent would otherwise only grow), so an id
  // sent alone is always one of the last 65 pictures sent, which the app
  // always keeps (Pointer.show).
  const cursorReports = new Map();
  const sentPictures = new Set();
  let cursorValue = null;
  function showCursor(value) {
    if (value === cursorValue) return;
    cursorValue = value;
    let report = cursorReports.get(value);
    if (!report) {
      if (cursorReports.size > 64) {
        cursorReports.clear();
        sentPictures.clear();
      }
      report = resolveCursor(value);
      cursorReports.set(value, report);
    }
    Promise.resolve(report).then((done) => {
      cursorReports.set(value, done);
      if (cursorValue !== value) return;
      if (done.id && sentPictures.has(done.id)) {
        post({ kind: 'cursor', id: done.id });
        return;
      }
      if (done.id) sentPictures.add(done.id);
      post(Object.assign({ kind: 'cursor' }, done));
    });
  }

  // What is under the pointer, read once a frame at most: the innermost
  // element, through open shadow roots.
  let cursorElement = null;
  let cursorFrame = 0;
  function checkCursor() {
    cursorFrame = 0;
    const element = cursorElement;
    if (!element || !element.isConnected) return;
    let value = 'auto';
    try {
      value = element.ownerDocument.defaultView.getComputedStyle(element).cursor || 'auto';
    } catch (_) {}
    showCursor(value);
  }
  function checkSoon() {
    if (!cursorFrame) cursorFrame = requestAnimationFrame(checkCursor);
  }
  function pointerOver(event) {
    // A finger on the glass has no cursor; a trackpad or a mouse does.
    if (event.pointerType && event.pointerType !== 'mouse') return;
    const path = event.composedPath ? event.composedPath() : [];
    const first = path.length ? path[0] : event.target;
    cursorElement = first && first.nodeType === 1 ? first : event.target;
    checkSoon();
  }
  if (config.cursor !== false) {
    for (const type of ['pointerover', 'pointermove', 'pointerdown', 'pointerup']) {
      window.addEventListener(type, pointerOver, { capture: true, passive: true });
    }
    window.addEventListener('pointerout', (event) => {
      if (event.pointerType && event.pointerType !== 'mouse') return;
      if (event.relatedTarget) return;
      cursorElement = null;
      showCursor('auto');
    }, { capture: true, passive: true });
    // A page changes its cursor without the pointer moving too: a key picks
    // another tool in Figma. So it is read again after a key, and every so
    // often while the pointer is over the page.
    for (const type of ['keydown', 'keyup']) {
      window.addEventListener(type, () => { if (cursorElement) checkSoon(); }, { capture: true, passive: true });
    }
    setInterval(() => { if (cursorElement) checkSoon(); }, 400);
  }

  // MARK: The site's icon

  // The icons the page names, best first, for its pinned tab and its
  // bookmarks (SiteIcons.swift fetches the first that loads). Apple's touch
  // icons are the big ones; a plain icon can be 16 pixels; /favicon.ico is
  // the one every site had before <link> did. An SVG can't be shown by the
  // app, and a mask icon is a single colour, so neither is named.
  function siteIcons() {
    const found = [];
    for (const link of document.querySelectorAll('link[rel][href]')) {
      const rel = String(link.rel || '').toLowerCase().split(/\s+/);
      const touch = rel.includes('apple-touch-icon') || rel.includes('apple-touch-icon-precomposed');
      if (!touch && !rel.includes('icon')) continue;
      if (rel.includes('mask-icon')) continue;
      const href = link.href;
      const type = String(link.type || '').toLowerCase();
      if (!/^(https?:|data:image\/)/i.test(href) || type.includes('svg') || /^data:image\/svg/i.test(href) ||
          /\.svg([?#]|$)/i.test(href)) continue;
      const sizes = String(link.getAttribute('sizes') || '').toLowerCase().split(/\s+/)
        .map((size) => parseInt(size, 10) || 0);
      found.push({ href, score: (touch ? 1000 : 0) + Math.min(Math.max(0, ...sizes), 512) });
    }
    found.sort((a, b) => b.score - a.score);
    const urls = found.map((icon) => icon.href);
    if (/^https?:$/.test(location.protocol)) urls.push(location.origin + '/favicon.ico');
    return Array.from(new Set(urls)).slice(0, 6);
  }
  let iconsSent = '';
  function reportIcons() {
    const urls = siteIcons();
    const key = urls.join(' ');
    if (!urls.length || key === iconsSent) return;
    iconsSent = key;
    post({ kind: 'icons', urls });
  }
  window.addEventListener('load', () => setTimeout(reportIcons, 300), { once: true });

  // Whether freezing the tab would lose something typed and not sent: a
  // field whose text is not the one the page put there.
  const untyped = /^(button|checkbox|color|file|hidden|image|radio|range|reset|submit)$/;
  function unsaved() {
    for (const field of document.querySelectorAll('input, textarea')) {
      if (field.tagName === 'INPUT' && untyped.test((field.getAttribute('type') || '').toLowerCase())) continue;
      if (field.value && field.value !== field.defaultValue) return true;
    }
    return false;
  }

  function state() {
    return {
      userAgent: navigator.userAgent,
      platform: navigator.platform,
      trusted: counts.trusted,
      bridged: counts.bridged,
      editing: !!editing,
      password: !!password,
      adapter: config.adapter || '',
    };
  }

  post({ kind: 'hello', userAgent: navigator.userAgent, adapter: config.adapter || '' });

  Object.defineProperty(window, '__safience', {
    value: Object.freeze({ wheel, key, unsaved, state, clientPoint, hitTest, parseCursor, siteIcons }),
  });
})();
