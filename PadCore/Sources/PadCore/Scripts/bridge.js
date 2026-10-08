// The app's side of every page, but a hands-off one (HandsOff.swift).
//
// It runs at document start in the app's own content world, in the main
// frame only. The page can't see its variables or call it; what the page
// sees is only what a Mac's WebKit would show it: wheel events with the
// pointer's position and the keys held, Tab and the arrows when the system
// would otherwise keep them, and a stylesheet.
//
// The app calls in through window.__safience (Page.swift): wheel() for every
// step of a trackpad scroll or pinch, key() for a relayed key, pointer() and
// type() for the iPhone's desktop view, which moves a cursor of its own,
// unsaved() before a tab is frozen, state() for Diagnostics. It hears back through the
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
      if (element.hasAttribute('contenteditable') && !element.isContentEditable && element.tabIndex === 0
          && !/^(a|area|button|input|select|textarea|iframe|summary)$/i.test(element.tagName)) return false;
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
    let at = list.indexOf(from);
    if (at < 0 && from) {
      // Not in the list: in a shadow root, or something focused by script.
      // Its place is where it sits in the document, its host's for a shadow
      // root, so the next is the first field after that, not the page's first.
      let mark = from;
      while (mark && mark.getRootNode() !== doc) mark = mark.getRootNode().host || null;
      if (mark) {
        const after = list.findIndex((e) => e !== mark && (mark.compareDocumentPosition(e) & Node.DOCUMENT_POSITION_FOLLOWING));
        at = backwards
          ? (after < 0 ? list.length : after)
          : (after < 0 ? list.length - 1 : after - 1);
      }
    }
    const next = at < 0
      ? list[backwards ? list.length - 1 : 0]
      : list[(at + (backwards ? -1 : 1) + list.length) % list.length];
    next.focus();
    if (next.tagName === 'INPUT' && textTypes.test((next.getAttribute('type') || '').toLowerCase())) {
      try { next.select(); } catch (_) {}
    }
    return true;
  }

  const legacyCodes = { Tab: 9, Enter: 13, Escape: 27, Backspace: 8, Delete: 46,
    ArrowLeft: 37, ArrowUp: 38, ArrowRight: 39, ArrowDown: 40 };

  // A typed character's code and keyCode, as a US keyboard's: KeyA and 65 for
  // "a", Digit1 and 49 for "1"; 0 and the character for anything else.
  function charCodes(key) {
    if (/^[a-z]$/i.test(key)) return { code: 'Key' + key.toUpperCase(), legacy: key.toUpperCase().charCodeAt(0) };
    if (/^[0-9]$/.test(key)) return { code: 'Digit' + key, legacy: key.charCodeAt(0) };
    if (key === ' ') return { code: 'Space', legacy: 32 };
    return { code: key, legacy: 0 };
  }

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
    const code = legacyCodes[m.key] || (Array.from(m.key).length === 1 ? charCodes(m.key).legacy : 0);
    for (const name of ['keyCode', 'which']) {
      try { Object.defineProperty(event, name, { get: () => code }); } catch (_) {}
    }
    return event;
  }

  // m: { key: 'Tab' | 'ArrowUp' | 'Enter' | 'a' | ..., code, shift, alt, ctrl, meta }
  // The key goes to the focused element as keydown and keyup. When the page
  // doesn't take it, it does what a browser would: Tab moves the focus, an
  // arrow outside a text field scrolls, and in a field Return, Backspace and
  // a character edit it. Returns 'handled' or 'default'.
  function key(m) {
    const target = deepActive() || document.body || document.documentElement;
    const view = target.ownerDocument.defaultView;
    const doc = target.ownerDocument;
    const proceed = target.dispatchEvent(keyEvent(view, 'keydown', m));
    // One character, whatever its length in JavaScript's units: an emoji is two.
    const printable = Array.from(m.key).length === 1;
    if (proceed && (printable || m.key === 'Enter')) {
      target.dispatchEvent(keyEvent(view, 'keypress', m));
    }
    if (proceed) {
      if (m.key === 'Tab') {
        moveFocus(target, !!m.shift);
      } else if (editable(target) && printable && !m.ctrl && !m.meta) {
        doc.execCommand('insertText', false, m.key);
      } else if (editable(target) && (m.key === 'Backspace' || m.key === 'Delete')) {
        doc.execCommand(m.key === 'Backspace' ? 'delete' : 'forwardDelete', false);
      } else if (editable(target) && m.key === 'Enter') {
        // A field sends its form, as Return does; a text area and
        // anything content-editable take a new line.
        if (target.tagName === 'INPUT') {
          if (target.form && target.form.requestSubmit) target.form.requestSubmit();
        } else {
          doc.execCommand(target.tagName === 'TEXTAREA' ? 'insertLineBreak' : 'insertParagraph', false);
        }
      } else if (!editable(target) && m.key.startsWith('Arrow')) {
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

  // MARK: The iPhone's desktop view

  // The phone has no pointer. In its desktop view the app moves a cursor of
  // its own over the page, as a trackpad would, and its moves, presses and
  // clicks come here to reach the page as a Mac's mouse does: pointer
  // events, then mouse events, then click. Script events, which a page can
  // tell from a real mouse's (isTrusted), and a few pages ignore.
  let over = null;
  let pressed = null;
  let mouseless = false;

  function lineage(node) {
    const list = [];
    for (let at = node; at; at = parentOf(at)) {
      if (at.nodeType === 1) list.push(at);
    }
    return list;
  }

  function mouseEvent(view, kind, type, hit, point, m, related) {
    const init = {
      bubbles: !/enter|leave/.test(type),
      cancelable: !/enter|leave/.test(type),
      composed: true,
      view,
      detail: m.detail || 0,
      clientX: hit.x,
      clientY: hit.y,
      screenX: point.x + (window.screenX || 0),
      screenY: point.y + (window.screenY || 0),
      button: m.button || 0,
      buttons: m.buttons || 0,
      relatedTarget: related || null,
      ctrlKey: !!m.ctrl, altKey: !!m.alt, shiftKey: !!m.shift, metaKey: !!m.meta,
    };
    if (kind === 'pointer') {
      const Pointer = view.PointerEvent || PointerEvent;
      return new Pointer(type, Object.assign(init, {
        pointerId: 1, pointerType: 'mouse', isPrimary: true, width: 1, height: 1,
        pressure: init.buttons ? 0.5 : 0,
      }));
    }
    const Mouse = view.MouseEvent || MouseEvent;
    return new Mouse(type, init);
  }

  // :hover, for the cursor the app moves. A page's hover styles answer
  // only the engine's own pointer, which a phone hasn't got, so each of
  // its :hover rules is copied once with :hover as an attribute, which the
  // elements under the cursor get. The copies sit in a style element of
  // the bridge's own, after the page's; media queries asking for a pointer
  // that hovers are answered yes there, as a Mac answers them. A style
  // sheet from another origin can't be read, so its hover styles stay
  // off; a shadow root's aren't copied.
  const hoverMark = 'data-safience-hover';
  const hoverCopies = new WeakMap();
  let hovered = [];

  function hoverMedia(prelude) {
    return prelude
      .replace(/\(\s*(any-)?hover\s*:\s*hover\s*\)/gi, '(min-width: 0px)')
      .replace(/\(\s*(any-)?pointer\s*:\s*fine\s*\)/gi, '(min-width: 0px)')
      .replace(/\(\s*(any-)?hover\s*:\s*none\s*\)/gi, '(max-width: 0px)')
      .replace(/\(\s*(any-)?pointer\s*:\s*coarse\s*\)/gi, '(max-width: 0px)');
  }

  function copyHoverRules(rules, out) {
    for (const rule of Array.from(rules)) {
      if (rule.styleSheet) {
        try { copyHoverRules(rule.styleSheet.cssRules, out); } catch (_) {}
        continue;
      }
      const inner = rule.cssRules;
      const nested = [];
      if (inner && inner.length) copyHoverRules(inner, nested);
      if (rule.selectorText !== undefined) {
        if (rule.selectorText.includes(':hover')) {
          out.push(rule.selectorText.replace(/:hover\b/g, '[' + hoverMark + ']') + '{' + rule.style.cssText + '}');
        }
        if (nested.length) out.push(rule.selectorText + '{' + nested.join('') + '}');
      } else if (nested.length) {
        const text = rule.cssText;
        out.push(hoverMedia(text.slice(0, text.indexOf('{'))) + '{' + nested.join('') + '}');
      }
    }
  }

  // The copies for a document, made again for a sheet only when its
  // number of rules changed: the page added some, as script-made styles do.
  function copyHover(doc) {
    let state = hoverCopies.get(doc);
    if (!state) {
      state = { style: null, counts: new Map(), texts: new Map() };
      hoverCopies.set(doc, state);
    }
    const sheets = Array.from(doc.styleSheets).concat(Array.from(doc.adoptedStyleSheets || []));
    let changed = false;
    for (const sheet of sheets) {
      if (state.style && sheet.ownerNode === state.style) continue;
      let rules;
      try { rules = sheet.cssRules; } catch (_) { continue; }
      if (!rules || state.counts.get(sheet) === rules.length) continue;
      state.counts.set(sheet, rules.length);
      const out = [];
      try { copyHoverRules(rules, out); } catch (_) {}
      state.texts.set(sheet, out.join('\n'));
      changed = true;
    }
    for (const sheet of Array.from(state.texts.keys())) {
      if (!sheets.includes(sheet)) {
        state.texts.delete(sheet);
        state.counts.delete(sheet);
        changed = true;
      }
    }
    const text = Array.from(state.texts.values()).filter(Boolean).join('\n');
    if (!text) return;
    if (!state.style) {
      state.style = doc.createElement('style');
      state.style.setAttribute('data-safience', 'hover');
    }
    if (changed || state.style.textContent !== text) state.style.textContent = text;
    if (!state.style.isConnected) (doc.head || doc.documentElement).appendChild(state.style);
  }

  function markHover(lineup) {
    for (const element of hovered) {
      if (!lineup.includes(element)) element.removeAttribute(hoverMark);
    }
    const docs = new Set();
    for (const element of lineup) {
      if (!element.hasAttribute(hoverMark)) element.setAttribute(hoverMark, '');
      docs.add(element.ownerDocument);
    }
    hovered = lineup;
    for (const doc of docs) copyHover(doc);
  }

  // Over, out, enter and leave as the cursor goes from one element to the
  // next, so hover menus open and close; and the hover styles with them.
  function crossTo(element, hit, point, m) {
    if (element === over) return;
    const view = hit.view;
    const before = over && over.isConnected ? lineage(over) : [];
    const after = lineage(element);
    if (before.length) {
      const old = before[0];
      old.dispatchEvent(mouseEvent(old.ownerDocument.defaultView, 'pointer', 'pointerout', hit, point, m, element));
      old.dispatchEvent(mouseEvent(old.ownerDocument.defaultView, 'mouse', 'mouseout', hit, point, m, element));
      for (const left of before.filter((e) => !after.includes(e))) {
        left.dispatchEvent(mouseEvent(left.ownerDocument.defaultView, 'pointer', 'pointerleave', hit, point, m, element));
        left.dispatchEvent(mouseEvent(left.ownerDocument.defaultView, 'mouse', 'mouseleave', hit, point, m, element));
      }
    }
    element.dispatchEvent(mouseEvent(view, 'pointer', 'pointerover', hit, point, m, before[0]));
    element.dispatchEvent(mouseEvent(view, 'mouse', 'mouseover', hit, point, m, before[0]));
    for (const entered of after.filter((e) => !before.includes(e)).reverse()) {
      entered.dispatchEvent(mouseEvent(entered.ownerDocument.defaultView, 'pointer', 'pointerenter', hit, point, m, before[0]));
      entered.dispatchEvent(mouseEvent(entered.ownerDocument.defaultView, 'mouse', 'mouseenter', hit, point, m, before[0]));
    }
    over = element;
    markHover(after);
  }

  // What a press gives the focus to, as a browser does: the field or the
  // control under it, or nothing, and a field's caret where it was pressed.
  function focusFor(element, hit) {
    const focusable = element.closest(tabbable + ', [tabindex]');
    const active = deepActive();
    if (focusable && !focusable.disabled) {
      if (focusable !== active) focusable.focus({ preventScroll: true });
      if (focusable.isContentEditable && hit.view.document.caretRangeFromPoint) {
        const range = hit.view.document.caretRangeFromPoint(hit.x, hit.y);
        const selection = hit.view.getSelection();
        if (range && selection) {
          selection.removeAllRanges();
          selection.addRange(range);
        }
      }
    } else if (active && active !== document.body && active.blur) {
      active.blur();
    }
  }

  function commonAncestor(a, b) {
    const others = lineage(b);
    return lineage(a).find((e) => others.includes(e)) || null;
  }

  // m: { type: 'move' | 'down' | 'up' | 'click' | 'context', x, y, width,
  //      button, buttons, detail, shift, alt, ctrl, meta }
  // x and y are in the web view's points, as for wheel(). A click is a press
  // and a release in place; a second or third (detail 2, 3) adds dblclick on
  // the second. 'context' is a press of the right button. Returns 'handled'
  // when the page cancelled the press, 'default' otherwise.
  function pointer(m) {
    const point = clientPoint(m.x, m.y, m.width);
    const hit = hitTest(point.x, point.y);
    const target = hit.element;
    const view = hit.view;
    const send = (kind, type, init) => target.dispatchEvent(mouseEvent(view, kind, type, hit, point, init));
    crossTo(target, hit, point, m);
    if (m.type === 'move') {
      send('pointer', 'pointermove', m);
      if (!mouseless) send('mouse', 'mousemove', m);
      return 'default';
    }
    if (m.type === 'click') {
      const outcome = pointer(Object.assign({}, m, { type: 'down' }));
      pointer(Object.assign({}, m, { type: 'up' }));
      return outcome;
    }
    if (m.type === 'context') {
      const right = { button: 2, buttons: 2, detail: 1 };
      const outcome = pointer(Object.assign({}, m, right, { type: 'down' }));
      target.dispatchEvent(mouseEvent(view, 'mouse', 'contextmenu', hit, point, Object.assign({}, m, right)));
      pointer(Object.assign({}, m, right, { type: 'up', buttons: 0 }));
      return outcome;
    }
    const button = m.button || 0;
    if (m.type === 'down') {
      const held = Object.assign({}, m, { button, buttons: button === 2 ? 2 : 1, detail: m.detail || 1 });
      // A cancelled pointerdown keeps the mouse events from the page, as in a browser.
      mouseless = !send('pointer', 'pointerdown', held);
      const proceed = mouseless ? false : send('mouse', 'mousedown', held);
      if (proceed && !mouseless && button === 0) focusFor(target, hit);
      pressed = { element: target, button };
      reportFocus();
      return mouseless || !proceed ? 'handled' : 'default';
    }
    if (m.type === 'up') {
      const released = Object.assign({}, m, { button, buttons: 0, detail: m.detail || 1 });
      send('pointer', 'pointerup', released);
      if (!mouseless) send('mouse', 'mouseup', released);
      mouseless = false;
      const from = pressed;
      pressed = null;
      if (from && from.button === button && button === 0 && from.element.isConnected) {
        const clicked = commonAncestor(from.element, target);
        if (clicked) {
          clicked.dispatchEvent(mouseEvent(clicked.ownerDocument.defaultView, 'mouse', 'click', hit, point, released));
          if (released.detail === 2) {
            clicked.dispatchEvent(mouseEvent(clicked.ownerDocument.defaultView, 'mouse', 'dblclick', hit, point, released));
          }
        }
      }
      reportFocus();
      return 'default';
    }
    return 'ignored';
  }

  // m: { text, back }
  // What the phone's keyboard typed in the desktop view: `back` characters
  // taken away, then `text`, as the keyboard's own field changed (a Korean
  // syllable is typed by replacing the one before it). In a field it is
  // edited as typing edits it; on the rest of the page each new character is
  // a key, for the page's own shortcuts, and a replacement is not. Returns
  // 'typed', 'keys' or 'ignored'.
  function type(m) {
    const text = m.text || '';
    const back = m.back || 0;
    const target = deepActive();
    if (!text) {
      for (let i = 0; i < back; i++) key({ key: 'Backspace', code: 'Backspace' });
      return back ? 'keys' : 'ignored';
    }
    if (target && editable(target)) {
      if (!back && Array.from(text).length === 1) {
        key({ key: text, code: charCodes(text).code });
        return 'typed';
      }
      const doc = target.ownerDocument;
      for (let i = 0; i < back; i++) doc.execCommand('delete', false);
      doc.execCommand('insertText', false, text);
      return 'typed';
    }
    if (back) return 'ignored';
    for (const character of Array.from(text)) key({ key: character, code: charCodes(character).code });
    return 'keys';
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
    value: Object.freeze({ wheel, key, pointer, type, unsaved, state, clientPoint, hitTest, parseCursor, siteIcons }),
  });
})();
