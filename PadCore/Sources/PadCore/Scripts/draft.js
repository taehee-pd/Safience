// Read-only draft inspection, called once before the app releases a page.
// A rich editor cannot tell us what its site saved, so even an empty or
// hidden editor stays live until the site removes it or the page navigates.
// Changed fields, including a deletion to empty, stay too. A canvas can
// hold unsaved private drawing state, so every canvas stays live as unknown.
//
// Look through open shadow roots and same-origin frames. An unreadable
// frame or an inspection too large to finish is unknown, so stays live.
// Closed shadow roots and private JavaScript state without an observable
// editor or canvas cannot be inspected. The system can still end the process.
function safienceHasDraft(handsOff) {
  const host = location.hostname.toLowerCase().replace(/\.+$/, '');
  if (handsOff.some((h) => host === h || host.endsWith('.' + h))) return true;
  const untyped = /^(button|checkbox|color|file|hidden|image|radio|range|reset|submit)$/;
  const pending = [document];
  const seen = new Set();
  let remaining = 20000;
  while (pending.length) {
    const root = pending.pop();
    if (seen.has(root)) continue;
    seen.add(root);
    if (root.nodeType === 9 && String(root.designMode).toLowerCase() === 'on') return true;
    for (const element of root.querySelectorAll('*')) {
      if (--remaining < 0) return true;
      if (element.isContentEditable || element.tagName === 'CANVAS') return true;
      if (element.tagName === 'TEXTAREA' || (element.tagName === 'INPUT' &&
          !untyped.test((element.getAttribute('type') || '').toLowerCase()))) {
        if (element.value !== element.defaultValue) return true;
      }
      if (element.shadowRoot) pending.push(element.shadowRoot);
      if (element.tagName === 'IFRAME' || element.tagName === 'FRAME') {
        try {
          const host = element.contentWindow.location.hostname.toLowerCase().replace(/\.+$/, '');
          if (handsOff.some((h) => host === h || host.endsWith('.' + h))) return true;
          const inner = element.contentDocument;
          if (!inner) return true;
          pending.push(inner);
        } catch (_) { return true; }
      }
    }
  }
  return false;
}
