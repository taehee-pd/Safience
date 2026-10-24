// Safience's shim for Chrome extensions (Docs/ExtensionsDesign.md).
//
// Put first in an extension's worker, its background scripts, its content
// scripts and its pages (ExtensionPreparation.swift), it mends where
// WebKit's extension APIs behave unlike Chrome's, adds what WebKit lacks
// and Safience answers, and tells Safience of the errors nobody caught.
// Most of it follows Search's (github.com/driceroland/Search, MIT, Office
// Commun, its ExtensionShims.swift), each part saying so; what Safience
// took is listed in Docs/ExtensionsFromSearch.md.
(() => {
  const root = globalThis;
  const chrome = root.chrome || root.browser;
  // A page's own world, where an extension's MAIN-world script runs with
  // this before it, has no extension APIs: nothing to mend there, and
  // nothing may be left there for a page to see. (Search)
  const ours = (() => { try { return !!(chrome && chrome.runtime && chrome.runtime.id); } catch (e) { return false; } })();
  if (!ours || root.__safienceShim) return;
  Object.defineProperty(root, "__safienceShim", { value: true });
  const runtime = chrome.runtime;
  // Every namespace WebKit gives this world, taken now: a sandbox that later
  // locks the globals away (MetaMask's LavaMoat) would break the shim's own
  // code that needs them. (Search)
  const spaces = new Set(Object.keys(chrome));
  // On a web page this is a content script: only Chrome's behaviour is
  // mended there, no API Chrome doesn't give content scripts either.
  const inContent = typeof location !== "undefined" && !/^(chrome|webkit)-extension:$/.test(location.protocol);
  // One of the extension's pages in a frame of a website: Vimium's bar, a
  // password manager's list under a field. WebKit runs it in the website's
  // process, which it trusts with no more than a content script: one call
  // to tabs, windows or scripting, and WebKit takes the process for
  // compromised and ends it. Chrome gives such a frame everything, so here
  // the worker makes those calls for it (see __safienceCall). (Search)
  const embedded = !inContent && typeof window !== "undefined" && window.top !== window && (() => {
    try { const a = location.ancestorOrigins; if (a && a.length) return [...a].some((o) => o !== location.origin); } catch (e) {}
    try { return window.top.location.origin !== location.origin; } catch (e) { return true; }
  })();
  const worker = typeof ServiceWorkerGlobalScope !== "undefined" && root instanceof ServiceWorkerGlobalScope;
  // The extension's background, whichever WebKit runs: its worker, or its
  // page, which it picks when a manifest names scripts as well. (Search)
  const background = worker || (!inContent && typeof document !== "undefined" && (() => {
    try { return typeof chrome.extension?.getBackgroundPage === "function" && chrome.extension.getBackgroundPage() === root; }
    catch (e) { return false; }
  })());
  const manifest = (() => { try { return runtime.getManifest() || {}; } catch (e) { return {}; } })();
  const hasWorker = !!(manifest.background && (manifest.background.service_worker || manifest.background.scripts || manifest.background.page));

  // Bitwarden's bundled TypeScript uses these as computed class keys before
  // it registers disposable resources: defined before any extension code
  // runs, Symbol.for keeping the key shared by its frames. (Search)
  for (const name of ["dispose", "asyncDispose"]) {
    if (root.Symbol[name] === undefined) Object.defineProperty(root.Symbol, name, { value: root.Symbol.for("Symbol." + name) });
  }

  // WebKit took requestIdleCallback back out after a page-load regression
  // (bug 287681), leaving Proton Pass's form detection without it. Chrome's
  // longest idle deadline is 50 ms; this gives the whole of it. (Search)
  if (typeof root.requestIdleCallback !== "function" || typeof root.cancelIdleCallback !== "function") {
    const idle = new Map();
    let last = 0;
    root.requestIdleCallback = (callback) => {
      const id = ++last;
      idle.set(id, setTimeout(() => {
        if (!idle.delete(id)) return;
        const start = Date.now();
        callback({ didTimeout: false, timeRemaining: () => Math.max(0, 50 - (Date.now() - start)) });
      }, 1));
      return id;
    };
    root.cancelIdleCallback = (id) => {
      const timer = idle.get(id);
      if (timer === undefined) return;
      idle.delete(id);
      clearTimeout(timer);
    };
  }

  // WebKit finds an extension's APIs through the chrome and browser globals
  // when it delivers an event. A sandbox that locks every global away
  // (MetaMask's LavaMoat) cuts it off. Made fixed accessors, they can't be
  // taken away, and a replacement that still carries the APIs is taken;
  // one that hides them (a Proxy, as Proton Pass puts there) isn't. (Search)
  for (const key of ["browser", "chrome"]) {
    // SingleFile installs its own browser getter: browser is left open for it.
    if (key === "browser" && runtime.id === "mpiodijhokgodhhofbcjdecpffjipkle") continue;
    const d = Object.getOwnPropertyDescriptor(root, key);
    if (!d || !d.configurable) continue;
    let value = root[key];
    const carries = (v) => { try { return !!(v && v.runtime && v.runtime.id); } catch (e) { return false; } };
    try {
      Object.defineProperty(root, key, { configurable: false, enumerable: d.enumerable, get: () => value, set: (v) => { if (carries(v)) value = v; } });
    } catch (e) {}
  }

  // WebKit's namespace and event objects are wrappers it doesn't keep
  // alive: once no script holds one, the next chrome.runtime is a fresh
  // object without what was set on it. So what is touched here is held for
  // good, and a member is set as an own property, which takes the place of
  // the prototype's method of the same name. (Search)
  const kept = new Set([chrome, runtime]);
  for (const space of spaces) { try { const ns = chrome[space]; if (ns && typeof ns === "object") kept.add(ns); } catch (e) {} }
  try { Object.defineProperty(root, "__safienceKept", { value: kept }); } catch (e) {}
  const put = (target, key, value) => {
    if (target && (typeof target === "object" || typeof target === "function")) kept.add(target);
    try { Object.defineProperty(target, key, { value, configurable: true, writable: true, enumerable: true }); }
    catch (e) { try { target[key] = value; } catch (e2) {} }
  };
  // Set for the callback, then as it was: WebKit's own, if it had one.
  const withLastError = (error, callback) => {
    const before = Object.getOwnPropertyDescriptor(runtime, "lastError");
    put(runtime, "lastError", { message: String(error && error.message || error) });
    try { callback(); } finally {
      try { if (before) Object.defineProperty(runtime, "lastError", before); else delete runtime.lastError; } catch (e) {}
    }
  };
  // runtime's methods as its own, bound, so code that takes one off it
  // still calls WebKit's on the object it came from. (Search)
  {
    const names = new Set();
    for (let o = runtime; o && o !== Object.prototype; o = Object.getPrototypeOf(o)) Object.getOwnPropertyNames(o).forEach((k) => names.add(k));
    for (const name of names) {
      if (name === "constructor" || /^on[A-Z]/.test(name)) continue;
      let f; try { f = runtime[name]; } catch (e) { continue; }
      if (typeof f === "function") put(runtime, name, f.bind(runtime));
    }
  }

  // Safience itself, through native messaging to "safience": it hears of
  // errors here, and answers the APIs WebKit lacks.
  const native = (api, args) =>
    runtime.sendNativeMessage("safience", { api, args: JSON.parse(JSON.stringify(args ?? [])) })
      .then((reply) => {
        if (reply && reply.error) throw new Error(reply.error);
        return reply ? reply.value : undefined;
      });
  // Chrome's APIs take a callback last, or return a promise without one.
  const call = (api) => (...args) => {
    const callback = args.length && typeof args[args.length - 1] === "function" ? args.pop() : null;
    const promise = native(api, args);
    if (!callback) return promise;
    promise.then((value) => callback(value), (error) => withLastError(error, callback));
  };
  // An event of the shim's own, as Chrome's events look.
  const event = () => {
    const listeners = new Set();
    return {
      addListener: (f) => { if (typeof f === "function") listeners.add(f); }, removeListener: (f) => listeners.delete(f),
      hasListener: (f) => listeners.has(f), hasListeners: () => listeners.size > 0,
      listeners,
    };
  };

  // Errors nobody caught, in the worker and the extension's own pages, told
  // to Safience, which keeps only those whose words name an API
  // (ExtensionError) and never the words themselves. Not from a content
  // script, where the page's own errors arrive too. macOS 27 tells the app
  // of them itself; this is how it hears where it doesn't.
  if (!inContent && typeof root.addEventListener === "function") {
    const report = (kind, error, file, line) => {
      try { native("report", [kind, String(error && error.message || error), String(file || ""), Number(line) || 0]).catch(() => {}); } catch (e) {}
    };
    root.addEventListener("error", (e) => report("error", e.error || e.message, e.filename, e.lineno));
    root.addEventListener("unhandledrejection", (e) => report("rejection", e.reason, "", 0));
  }

  // WebKit gives a worker the user agent of the last web page that set one,
  // Safari's, not the Chrome one an extension expects. Code that picks its
  // path by it takes the Safari one: Bitwarden's asks a Safari app for a
  // reply thousands of times a second. Its pages too: an extension reads it
  // to pick a code path, a download, a welcome page. (Search)
  if (!inContent && typeof navigator !== "undefined" && !/ Chrome\//.test(navigator.userAgent || "")) {
    const given = "__SAFIENCE_CHROME__";
    const version = /^\d+(\.\d+){3}$/.test(given) ? given : "140.0.0.0";
    const chromeUA = String(navigator.userAgent).replace(/ Version\/[\d.]+.*$/, "").replace(/ Safari\/[\d.]+$/, "") + " Chrome/" + version + " Safari/537.36";
    const proto = typeof WorkerNavigator !== "undefined" && worker ? WorkerNavigator.prototype : typeof Navigator !== "undefined" ? Navigator.prototype : null;
    try {
      if (proto) {
        Object.defineProperty(proto, "userAgent", { get: () => chromeUA, configurable: true });
        Object.defineProperty(proto, "appVersion", { get: () => chromeUA.replace(/^Mozilla\//, ""), configurable: true });
        Object.defineProperty(proto, "vendor", { get: () => "Google Inc.", configurable: true });
        if (!("userAgentData" in navigator)) {
          const major = version.split(".")[0];
          const brands = [{ brand: "Chromium", version: major }, { brand: "Google Chrome", version: major }, { brand: "Not.A/Brand", version: "99" }];
          const low = { brands, mobile: false, platform: "macOS" };
          const mac = (chromeUA.match(/Mac OS X (\d+)[_.](\d+)(?:[_.](\d+))?/) || []).slice(1).map((n) => n || "0").join(".") || "10.15.7";
          const high = {
            architecture: "arm", bitness: "64", model: "", platformVersion: mac, wow64: false,
            fullVersionList: brands.map((b) => ({ brand: b.brand, version: b.version === major ? version : b.version + ".0.0.0" })),
            uaFullVersion: version,
          };
          const pick = (hints) => Object.assign({}, low, ...(Array.isArray(hints) ? hints : []).filter((h) => h in high).map((h) => ({ [h]: high[h] })));
          const data = Object.assign({}, low, { getHighEntropyValues: (hints) => Promise.resolve(pick(hints)), toJSON: () => low });
          Object.defineProperty(proto, "userAgentData", { get: () => data, configurable: true });
        }
      }
    } catch (e) {}
  }

  // A script a worker imports that isn't there: Chrome throws at once.
  // WebKit goes looking for it first, and while it does, runs the promises
  // already waiting: code that notes "still starting" until its first
  // promise settles (Tampermonkey) then thinks startup is over, and refuses
  // its own listeners. The extension's files are known, so a missing one is
  // refused as Chrome refuses it, and an empty one (Tampermonkey's test.js)
  // isn't fetched at all. (Search)
  const scripts = /*__SAFIENCE_SCRIPTS__*/null;
  const moduleWorker = worker && manifest.background && manifest.background.type === "module";
  if (worker && !moduleWorker && Array.isArray(scripts) && typeof root.importScripts === "function") {
    const shipped = new Set(), empty = new Set();
    for (const p of scripts) p.startsWith("-") ? empty.add(p.slice(1)) : shipped.add(p);
    const load = root.importScripts.bind(root);
    root.importScripts = (...urls) => {
      const wanted = [];
      for (const u of urls) {
        let url; try { url = new URL(u, location.href); } catch (e) { wanted.push(u); continue; }
        const path = decodeURIComponent(url.pathname);
        if (url.origin === location.origin && empty.has(path)) continue;
        if (url.origin === location.origin && !shipped.has(path) && path !== "/_safience/shim.js") {
          throw new DOMException("Failed to execute 'importScripts' on 'WorkerGlobalScope': The script at '" + url.href + "' failed to load.", "NetworkError");
        }
        wanted.push(u);
      }
      if (wanted.length) return load(...wanted);
    };
  }

  // The static routing API of Chrome's service workers (the install event's
  // addRoutes): a speed-up, so nothing is lost without it. (Search)
  if (typeof root.InstallEvent === "function" && root.InstallEvent.prototype && !root.InstallEvent.prototype.addRoutes) {
    root.InstallEvent.prototype.addRoutes = () => Promise.resolve();
  }

  // clients.matchAll() in an extension's worker: Chrome lists the
  // extension's own pages that are open. WebKit lists none, so an extension
  // that checks whether its popup is open before sending it news always
  // hears no: 1Password's popup stays on "connecting to the app" for ever.
  // Safience knows which pages are open, so they are added to the list; a
  // message posted to one reaches it through a channel the pages listen on,
  // as a message from the worker. The other way round, a page reaches the
  // worker through navigator.serviceWorker, which no worker controls here,
  // so a page is given one that posts to the worker over the same channel.
  // A port handed over with a message can't cross the channel: it stays
  // with its sender, and what is posted to the one the other side is given
  // comes back over the channel to it. (Search)
  const clientsChannel = typeof BroadcastChannel === "function" && !inContent && !embedded ? new BroadcastChannel("safience-clients") : null;
  if (clientsChannel) {
    // The ports a page handed over, kept on its side, and the stand-ins
    // the other side was given: what is posted on either goes over the
    // channel to the other, so a port carries both ways.
    const heldPorts = new Map(), standIns = new Map();
    const handOver = (transfer) => (Array.isArray(transfer) ? transfer : (transfer && transfer.transfer) || [])
      .filter((p) => typeof MessagePort === "function" && p instanceof MessagePort)
      .map((port) => {
        const key = Math.random().toString(36).slice(2);
        heldPorts.set(key, port);
        port.onmessage = (e) => clientsChannel.postMessage({ toPort: key, data: e.data });
        return key;
      });
    const answered = (data) => {
      if (typeof data.port === "string") {
        const port = heldPorts.get(data.port);
        if (port) port.postMessage(data.data);
        return true;
      }
      if (typeof data.toPort === "string") {
        const port = standIns.get(data.toPort);
        if (port) port.postMessage(data.data);
        return true;
      }
      return false;
    };
    const messageFrom = (source, data, keys) => {
      const ports = (Array.isArray(keys) ? keys : []).map((key) => {
        const pair = new MessageChannel();
        pair.port1.onmessage = (e) => clientsChannel.postMessage({ port: key, data: e.data });
        standIns.set(key, pair.port1);
        return pair.port2;
      });
      const message = new MessageEvent("message", { data, ports, origin: location.origin });
      if (source) Object.defineProperty(message, "source", { value: source });
      return message;
    };
    if (worker && root.clients && typeof root.clients.matchAll === "function") {
      const matchAll = root.clients.matchAll.bind(root.clients);
      // A page is known by its address, here and on the message it sends.
      const client = (p) => ({
        id: "safience-" + p.url, url: p.url, type: "window", frameType: "top-level",
        visibilityState: p.visible ? "visible" : "hidden", focused: !!p.focused,
        postMessage: (data, transfer) => { try { clientsChannel.postMessage({ url: p.url, data, ports: handOver(transfer) }); } catch (e) {} },
        focus() { return Promise.resolve(this); },
        navigate: () => Promise.resolve(null),
      });
      put(root.clients, "matchAll", async (options) => {
        const found = [...await matchAll(options)];
        const type = (options && options.type) || "window";
        if (type !== "window" && type !== "all") return found;
        let pages = [];
        try { pages = (await native("clients.pages", [])) || []; } catch (e) {}
        const listed = new Set(found.map((c) => c.url));
        return found.concat(pages.filter((p) => p && typeof p.url === "string" && !listed.has(p.url)).map(client));
      });
      clientsChannel.onmessage = ({ data }) => {
        if (!data || answered(data) || typeof data.from !== "string") return;
        root.dispatchEvent(messageFrom(client({ id: data.from, url: data.from }), data.data, data.ports));
      };
    } else if (!background && typeof navigator !== "undefined" && navigator.serviceWorker) {
      const container = navigator.serviceWorker;
      const script = manifest.background && manifest.background.service_worker;
      const controller = script && !container.controller ? {
        scriptURL: new URL(script, location.origin + "/").href, state: "activated", onstatechange: null, onerror: null,
        postMessage: (data, transfer) => { try { clientsChannel.postMessage({ from: location.href, data, ports: handOver(transfer) }); } catch (e) {} },
        addEventListener: () => {}, removeEventListener: () => {}, dispatchEvent: () => true,
      } : null;
      clientsChannel.onmessage = ({ data }) => {
        if (!data || answered(data) || data.url !== location.href) return;
        try { container.dispatchEvent(messageFrom(controller, data.data, data.ports)); } catch (e) {}
      };
      // Only the controller: `ready` is left as WebKit has it, since a
      // made-up registration has none of a real one's methods.
      if (controller) {
        kept.add(container);
        try { Object.defineProperty(container, "controller", { configurable: true, get: () => controller }); } catch (e) {}
      }
    }
  }

  // WebKit runs an extension's worker on its web process's main thread, and
  // a worker's WebSocket waits there for the main thread to set up its
  // channel, for itself, for ever: the worker and every page of the
  // extension freeze. 1Password opens one as a sign-in succeeds. So a
  // worker's socket is made by Safience (ExtensionSocket.swift) and its
  // frames come and go over a native port. (Search)
  if (worker && typeof root.WebSocket === "function" && typeof runtime.connectNative === "function") {
    const connectNative = runtime.connectNative.bind(runtime);
    const encode = (bytes) => { let s = ""; for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000)); return btoa(s); };
    const decode = (text) => { const s = atob(text), bytes = new Uint8Array(s.length); for (let i = 0; i < s.length; i++) bytes[i] = s.charCodeAt(i); return bytes.buffer; };
    const states = { CONNECTING: 0, OPEN: 1, CLOSING: 2, CLOSED: 3 };
    class WebSocket extends EventTarget {
      #port; #state = 0; #queue = Promise.resolve(); #origin; #hello;
      constructor(url, protocols) {
        super();
        let parsed;
        try { parsed = new URL(url, location.href); } catch (e) { throw new DOMException("The URL '" + url + "' is invalid.", "SyntaxError"); }
        if (parsed.protocol === "http:") parsed.protocol = "ws:";
        if (parsed.protocol === "https:") parsed.protocol = "wss:";
        if (!/^wss?:$/.test(parsed.protocol) || parsed.hash) throw new DOMException("The URL '" + url + "' is invalid.", "SyntaxError");
        const list = protocols === undefined ? [] : (Array.isArray(protocols) ? protocols : [protocols]).map(String);
        Object.defineProperty(this, "url", { value: parsed.href, enumerable: true });
        this.#origin = parsed.origin;
        this.protocol = ""; this.extensions = ""; this.binaryType = "blob"; this.bufferedAmount = 0;
        this.onopen = null; this.onmessage = null; this.onerror = null; this.onclose = null;
        this.#hello = { open: this.url, protocols: list, userAgent: navigator.userAgent };
        this.#connect();
      }
      // WebKit drops what a worker posts on a port it has only just
      // opened, without a word either way. So the opening is said again,
      // on the same port, until Safience answers anything at all.
      #connect() {
        const port = connectNative("safience.socket");
        let ready = false, tries = 0;
        this.#port = port;
        const again = () => {
          if (ready || this.#state === 3) return;
          if (tries++ >= 20) { this.#fire("error"); this.#closed(1006, "", false); return; }
          try { port.postMessage(this.#hello); } catch (e) {}
          setTimeout(again, 100 * Math.min(tries, 5));
        };
        port.onMessage.addListener((m) => {
          if (!ready) ready = true;
          if (m && m.ready === true) return;
          this.#take(m);
        });
        port.onDisconnect.addListener(() => {
          if (this.#state === 3) return;
          this.#fire("error");
          this.#closed(1006, "", false);
        });
        again();
      }
      get readyState() { return this.#state; }
      #fire(type, init) {
        let e;
        if (type === "message") e = new MessageEvent("message", init);
        else if (type === "close" && typeof CloseEvent === "function") e = new CloseEvent("close", init);
        else { e = new Event(type); if (init) for (const k in init) Object.defineProperty(e, k, { value: init[k] }); }
        const handler = this["on" + type];
        if (typeof handler === "function") { try { handler.call(this, e); } catch (error) { setTimeout(() => { throw error; }); } }
        this.dispatchEvent(e);
      }
      #closed(code, reason, wasClean) {
        this.#state = 3;
        try { this.#port.disconnect(); } catch (e) {}
        this.#fire("close", { code, reason, wasClean });
      }
      #take(m) {
        if (!m || this.#state === 3) return;
        if ("opened" in m) {
          // Closed while connecting: it goes no further.
          if (this.#state !== 0) return;
          this.protocol = m.opened; this.#state = 1; this.#fire("open");
        }
        else if ("text" in m) this.#fire("message", { data: m.text, origin: this.#origin });
        else if ("binary" in m) {
          const buffer = decode(m.binary);
          this.#fire("message", { data: this.binaryType === "arraybuffer" ? buffer : new Blob([buffer]), origin: this.#origin });
        }
        else if ("failed" in m) this.#fire("error");
        else if ("closed" in m) this.#closed(m.closed, m.reason || "", !!m.clean);
      }
      send(data) {
        if (this.#state === 0) throw new DOMException("WebSocket is still in CONNECTING state.", "InvalidStateError");
        if (this.#state !== 1) return;
        const post = (message) => { try { this.#port.postMessage(message); } catch (e) {} };
        if (typeof data === "string") { this.#queue = this.#queue.then(() => post({ send: data })); return; }
        const bytes = data instanceof ArrayBuffer ? Promise.resolve(new Uint8Array(data))
          : ArrayBuffer.isView(data) ? Promise.resolve(new Uint8Array(data.buffer, data.byteOffset, data.byteLength))
          : data instanceof Blob ? data.arrayBuffer().then((b) => new Uint8Array(b))
          : Promise.resolve(null);
        this.#queue = this.#queue.then(() => bytes).then((b) => b ? post({ sendBinary: encode(b) }) : post({ send: String(data) }));
      }
      close(code, reason) {
        if (code !== undefined && code !== 1000 && !(code >= 3000 && code <= 4999)) {
          throw new DOMException("The close code must be either 1000, or between 3000 and 4999. " + code + " is neither.", "InvalidAccessError");
        }
        if (this.#state >= 2) return;
        this.#state = 2;
        const message = { close: code === undefined ? 1000 : code, reason: reason === undefined ? "" : String(reason) };
        this.#queue = this.#queue.then(() => { try { this.#port.postMessage(message); } catch (e) {} });
      }
    }
    for (const [k, v] of Object.entries(states)) { Object.defineProperty(WebSocket, k, { value: v }); Object.defineProperty(WebSocket.prototype, k, { value: v }); }
    Object.defineProperty(root, "WebSocket", { value: WebSocket, configurable: true, writable: true });
  }

  // The same loss meets a worker's port to an app on the Mac: what it posts
  // in its first moments never reaches the app. iCloud Passwords says hello
  // to its helper that way, and without the helper's answer asks for the
  // code again and again. So on such a port, what the extension posts is
  // held until Safience says the port has arrived, asked on the same port,
  // and then sent in order. WebKit won't let connectNative be replaced in a
  // worker, so this is done on what every port shares, found through a port
  // to Safience itself; the question and the answer are kept from the
  // extension's listeners, and never reach the app. (Search)
  if (worker && typeof runtime.connectNative === "function") {
    let found = null;
    try { found = runtime.connectNative("safience"); found.disconnect(); } catch (e) {}
    const portProto = found && Object.getPrototypeOf(found);
    const eventProto = found && found.onMessage && Object.getPrototypeOf(found.onMessage);
    if (portProto && eventProto && typeof portProto.postMessage === "function" && typeof eventProto.addListener === "function") {
      // Ports that go to the extension's own pages or tabs, not an app.
      const toPages = new WeakSet();
      for (const space of [runtime, chrome.tabs]) {
        const connect = space && space.connect;
        if (typeof connect !== "function") continue;
        put(space, "connect", (...args) => { const port = connect.apply(space, args); try { toPages.add(port); } catch (e) {} return port; });
      }
      const post = portProto.postMessage, add = eventProto.addListener, remove = eventProto.removeListener, has = eventProto.hasListener;
      const word = (m) => !!m && typeof m === "object" && "__safienceNative" in m;
      const ports = new WeakMap();
      const start = (port) => {
        const state = { held: [] };
        let tries = 0;
        const flush = () => { const list = state.held; state.held = null; for (const m of list || []) post.call(port, m); };
        const again = () => {
          if (!state.held) return;
          // Unanswered, they go anyway: no worse than before.
          if (tries++ >= 20) { flush(); return; }
          try { post.call(port, { __safienceNative: "here?" }); } catch (e) {}
          setTimeout(again, 100 * Math.min(tries, 5));
        };
        add.call(port.onMessage, (m) => {
          if (m && m.__safienceNative === "here" && state.held) flush();
          // WebKit keeps a worker only while it has posted on an open port
          // in the last two minutes. Safience's word now and then is
          // answered on the port, so a worker holding a port to an app
          // stays, as in Chrome.
          if (m && m.__safienceNative === "alive") { try { post.call(port, { __safienceNative: "beat" }); } catch (e) {} }
        });
        add.call(port.onDisconnect, () => { state.held = null; });
        again();
        return state;
      };
      put(portProto, "postMessage", function (message) {
        let state = ports.get(this);
        if (!state) {
          const toApp = !toPages.has(this) && this.sender == null && typeof this.name === "string" && !/^safience(\.|$)/.test(this.name);
          state = toApp ? start(this) : { held: null };
          ports.set(this, state);
        }
        if (state.held) { state.held.push(message); return; }
        return post.call(this, message);
      });
      // Every event shares this prototype, so every listener goes behind
      // one that lets the question and the answer pass by: one for each
      // function, whatever event object it is added on, so it is found
      // again on a fresh wrapper of the same event; and every argument
      // passed on, a filter included (webRequest, webNavigation).
      const wrappers = new WeakMap();
      const wrapper = (f) => {
        let w = wrappers.get(f);
        if (!w) { w = function (m, ...rest) { if (word(m)) return; return f.call(this, m, ...rest); }; wrappers.set(f, w); }
        return w;
      };
      put(eventProto, "addListener", function (f, ...rest) {
        if (kept.has(this) || typeof f !== "function") return add.call(this, f, ...rest);
        return add.call(this, wrapper(f), ...rest);
      });
      put(eventProto, "removeListener", function (f, ...rest) {
        return remove.call(this, (typeof f === "function" && wrappers.get(f)) || f, ...rest);
      });
      put(eventProto, "hasListener", function (f, ...rest) {
        return has.call(this, (typeof f === "function" && wrappers.get(f)) || f, ...rest);
      });
    }
  }

  // Who has something to say about a message, told between the extension's
  // worker and its own pages on a channel they share (one origin): each
  // says, as soon as its listeners have run, whether it answers or lets the
  // message pass, and the sender says so of what it sends. A page with
  // nothing to say can then stay silent only as long as someone else may
  // still answer (see the end of dispatch). A page in a website's frame is
  // on the website's side of the channel and takes no part. (Search)
  const channel = !inContent && !embedded && typeof BroadcastChannel === "function" ? new BroadcastChannel("safience-messages") : null;
  const me = Math.random().toString(36).slice(2);
  const peers = new Set();
  const verdicts = new Map();
  const waiting = new Set();
  const present = new Set();
  // Pages that are there but didn't hear the last message sent to all:
  // WebKit doesn't bring every message to every page. Not waited for until
  // they say something about one they heard.
  const deaf = new Set();
  // A message is known by its JSON; a long one by a fingerprint of it.
  const fingerprint = (text) => {
    let a = 0x811c9dc5, b = 0x01000193;
    for (let i = 0; i < text.length; i++) { const c = text.charCodeAt(i); a = Math.imul(a ^ c, 16777619); b = Math.imul(b ^ c, 2246822507); }
    return "#" + (a >>> 0).toString(36) + (b >>> 0).toString(36) + text.length.toString(36);
  };
  const keyOf = (message) => {
    try { const k = JSON.stringify(message); return k === undefined ? null : k.length < 4000 ? k : fingerprint(k); } catch (e) { return null; }
  };
  const tell = (message, verdict, heard) => {
    const key = channel && keyOf(message);
    if (key) channel.postMessage({ key, from: background ? "worker" : me, verdict, heard, at: Date.now() });
  };
  // WebKit hands none of the extension's pages a message its worker or
  // another of its pages sent, and Bitwarden's sync and passkey window wait
  // on those. So each also goes over the channel, and a page that didn't
  // hear it from WebKit takes it from there. Each message's copies are
  // paired by count, keyed on all of it, and only with what the extension's
  // own pages and worker sent: one WebKit delivered cancels one relayed copy
  // still to come, and one relayed cancels a late one from WebKit. A content
  // script's message, however alike, is never taken for one, and an
  // unpaired copy is forgotten after a few seconds. (Search)
  const relayKey = (message) => { try { const text = JSON.stringify(message); return text === undefined ? null : text; } catch (e) { return null; } };
  const ownPlace = (() => { try { return runtime.getURL(""); } catch (e) { return ""; } })();
  const fromOwnPages = (sender) => !!sender && sender.id === runtime.id && typeof sender.url === "string" && !!ownPlace
    && (sender.url + "/").startsWith(ownPlace.replace(/\/$/, "") + "/");
  const heardNatively = new Map(), heardRelayed = new Map();
  const count = (map, key, by) => {
    const now = Date.now();
    for (const [k, v] of map) if (now - v.at > 5000) map.delete(k);
    const n = ((map.get(key) || {}).n || 0) + by;
    if (n > 0) { if (map.size > 200) map.clear(); map.set(key, { n, at: now }); } else map.delete(key);
  };
  const pending = (map, key) => { const v = map.get(key); return !!v && Date.now() - v.at <= 5000 && v.n > 0; };
  let deliverRelayed = null, relaying = false;
  // A relayed message's answer comes back over the channel to its sender,
  // which takes it if WebKit brought none (see the sendMessage below).
  const relays = new Map();
  const relay = (message) => {
    if (!channel) return null;
    const id = me + ":" + Math.random().toString(36).slice(2);
    try { channel.postMessage({ relay: message, from: me, url: location.href, id }); } catch (e) { return null; }
    return id;
  };
  // Only a page that listens for messages is waited for: one that doesn't
  // never hears them, so never says anything about them.
  let listening = false;
  const join = () => { if (channel && !background && !listening) { listening = true; channel.postMessage({ hello: true, from: me, where: location.pathname }); } };
  const leave = () => { if (channel && !background && listening) { listening = false; channel.postMessage({ bye: true, from: me }); } };
  if (channel) {
    channel.onmessage = ({ data }) => {
      if (!data || data.from === me) return;
      if (data.relay !== undefined) {
        const key = relayKey(data.relay);
        if (!background && deliverRelayed) setTimeout(() => {
          if (key && pending(heardNatively, key)) { count(heardNatively, key, -1); return; }
          if (key) count(heardRelayed, key, 1);
          relaying = true;
          let answer;
          try { answer = deliverRelayed(data.relay, { id: runtime.id, url: data.url, origin: location.origin }); } finally { relaying = false; }
          if (answer && typeof data.id === "string") {
            channel.postMessage({ answering: data.id, from: me });
            answer.then((value) => { if (value !== undefined) channel.postMessage({ answered: data.id, value, from: me }); });
          }
        }, 50);
        return;
      }
      if (typeof data.answering === "string" || typeof data.answered === "string") {
        const waiter = relays.get(data.answering || data.answered);
        if (waiter) data.answered ? waiter.answer(data.value) : waiter.answering();
        return;
      }
      // The pages that listen, as they come and go.
      if (!background && data.hello) {
        const known = peers.has(data.from);
        peers.add(data.from);
        if (!known && listening) channel.postMessage({ hello: true, from: me, where: location.pathname });
        return;
      }
      if (data.bye) { peers.delete(data.from); waiting.forEach((check) => check()); return; }
      // A popup that closes is thrown away without a word; so a page left
      // waiting asks who is still there.
      if (data.roll) { if (listening && !background) channel.postMessage({ here: true, from: me, to: data.from }); return; }
      if (data.here) { if (data.to === me) present.forEach((hear) => hear(data.from)); return; }
      if (typeof data.key !== "string") return;
      const now = Date.now();
      for (const [k, v] of verdicts) { if (now - v.at > 30000) verdicts.delete(k); else break; }
      const entry = verdicts.get(data.key) || { at: now, worker: null, pages: new Map() };
      verdicts.delete(data.key);
      verdicts.set(data.key, entry);
      entry.at = now;
      if (data.from === "worker") entry.worker = data;
      else { peers.add(data.from); if (data.heard) deaf.delete(data.from); entry.pages.set(data.from, data); }
      waiting.forEach((check) => check());
    };
    if (!background) try { root.addEventListener("pagehide", () => leave()); } catch (e) {}
  }
  // What a runtime.sendMessage call sends, and whether to this extension:
  // Chrome takes (extensionId?, message, options?), a string first being an
  // id only when an options object, or a third argument, doesn't say the
  // second is one. (Search)
  const messageOf = (args) => {
    const options = args[1];
    const isOptions = options == null || (typeof options === "object" && !Array.isArray(options)
      && Object.keys(options).every((key) => key === "includeTlsChannelId"));
    const explicit = args.length >= 3 || (args.length === 2 && typeof args[0] === "string" && !isOptions);
    return { message: args[explicit ? 1 : 0], own: !explicit || !args[0] || args[0] === runtime.id };
  };
  // Who sent a message from the extension's popup, as Chrome says it: no
  // tab. WebKit carries a page's messages only when it can name the tab the
  // page is in, so the popup is one, at no place in the window's row (its
  // index comes as NaN), its own page at the top. (Search)
  const untabbed = (sender) => {
    const tab = sender && sender.tab;
    if (!tab || tab.index >= 0 || sender.frameId || tab.url !== sender.url || !String(sender.url).startsWith(ownPlace)) return sender;
    const plain = { ...sender };
    delete plain.tab;
    return plain;
  };
  // The tab an extension's framed page is in, asked once (see __safienceToFrame).
  let ownTab = null;

  // Several onMessage listeners: WebKit (on macOS 26, as Search found; 27
  // already waits) takes the first one's return, usually undefined, as the
  // answer. Chrome's rule, as of Chrome 148: the first listener to answer,
  // fail or throw decides; an answer comes by sendResponse after returning
  // true, or by a promise; an empty one is null; a throw or a rejection
  // fails the sender's call. So the extension's listeners are gathered
  // behind one of WebKit's that follows it, and answers WebKit with a
  // promise. (Search) That promise never fails: when one does, WebKit
  // (27.0.1) never calls the sender back. A failure is an answer marked as
  // one instead, which the sender's shim turns back into lastError or a
  // rejection (replied, below); to another extension, which has no shim of
  // Safience's, it is null. An answer of the extension's own that looks
  // like the mark reads as a failure too: at worst a call fails.
  const failure = "__safienceFailed";
  const gathered = new Set();
  const gather = (target, eager, internal) => {
    if (!target || typeof target.addListener !== "function" || gathered.has(target)) return;
    gathered.add(target);
    kept.add(target);
    const add = target.addListener.bind(target);
    const remove = typeof target.removeListener === "function" ? target.removeListener.bind(target) : () => {};
    const listeners = new Set();
    // A promise when this world has something to say, or nothing.
    const dispatch = (message, sender, local = false) => {
      if (internal && !local && !background && !relaying && fromOwnPages(sender)) {
        const k = relayKey(message);
        if (k && pending(heardRelayed, k)) { count(heardRelayed, k, -1); return undefined; }
        if (k) count(heardNatively, k, 1);
      }
      let settle;
      const answer = new Promise((resolve) => { settle = resolve; });
      let answered = false;
      let keep = false;
      const failWith = (error) => {
        let words = "Error";
        try { words = String(error && typeof error.message === "string" ? error.message : error); } catch (e) {}
        answered = true;
        settle(internal ? { [failure]: words } : null);
      };
      // As Chrome sends it, as JSON, taken when it is given: changed
      // afterwards, it goes as it was; not JSON, it fails.
      const respond = (value) => {
        if (answered) return;
        let copy;
        try {
          const json = value === undefined ? undefined : JSON.stringify(value);
          copy = json === undefined ? null : JSON.parse(json);
        } catch (e) { return failWith(e); }
        answered = true;
        settle(copy);
      };
      const fail = (error) => { if (!answered) failWith(error); };
      // Nothing to say, after all: undefined, which the sender reads as no answer.
      const silent = () => { if (!answered) { answered = true; settle(undefined); } };
      const run = (listener, payload, from) => {
        let result, then;
        try {
          result = listener(payload, from, respond);
          then = result !== true && result ? result.then : undefined;
        } catch (e) { fail(e); setTimeout(() => { throw e; }); return false; }
        if (result === true) return true;
        if (typeof then !== "function") return false;
        try { then.call(result, respond, fail); } catch (e) { fail(e); }
        return true;
      };
      if (internal && message && typeof message === "object") {
        // Only the worker answers its pages' question whether it runs.
        if (message.__safiencePing === true) {
          if (background) respond("pong"); else setTimeout(silent, 15000);
          return answer;
        }
        // Safience's own envelopes come from this extension only: another
        // extension could otherwise speak as a frame of its own; and a tab's
        // message for a frame only from its own pages and worker, never a
        // content script.
        const fromHere = !!(sender && sender.id === runtime.id);
        if ((message.__safienceToFrame || message.__safienceCall) && !fromHere) return undefined;
        if (message.__safienceToFrame && !fromOwnPages(sender)) return undefined;
        // A tab's message, handed on by the worker (see alsoFramed): taken
        // by the frame it names, in the tab it names; every other page lets
        // it pass without answering, as it would a message not for it.
        if (message.__safienceToFrame) {
          const to = message.__safienceToFrame;
          if (!embedded || !(to.urls || []).includes(location.href)) {
            if (background) return undefined;
            setTimeout(silent, 10000);
            return answer;
          }
          if (!ownTab) ownTab = Promise.resolve(Object.getPrototypeOf(runtime).sendMessage.call(runtime, { __safienceCall: { space: "tabs", method: "getCurrent", args: [] } }))
            .then((reply) => reply && reply.value ? reply.value.id : null, () => null);
          ownTab.then((id) => {
            if (id !== to.tabId) return setTimeout(silent, 10000);
            let held = false;
            for (const listener of [...listeners]) if (run(listener, to.message, sender)) held = true;
            if (!held) silent();
          });
          return answer;
        }
        // A call one of the extension's pages in a website's frame can't
        // make itself (see embedded), made here for it, and only for one
        // of its pages: a content script gets no more than Chrome gives it.
        if (message.__safienceCall) {
          if (!background) { setTimeout(silent, 15000); return answer; }
          const { space, method, args } = message.__safienceCall;
          // Language detection accepts supplied text only. Content scripts may
          // use it without gaining access to any page, tab or native API.
          if (space === "i18n" && method === "detectLanguage") {
            Promise.resolve().then(() => native("i18n.detectLanguage", args))
              .then((value) => respond({ value }), (e) => respond({ error: String(e && e.message || e) }));
            return answer;
          }
          const own = (() => { try { return new URL(sender.url).origin === location.origin; } catch (e) { return false; } })();
          if (!own) { respond({ error: "chrome." + space + " isn't available to content scripts" }); return answer; }
          if (space === "tabs" && method === "getCurrent") { respond({ value: sender.tab }); return answer; }
          let ns; try { ns = chrome[space]; } catch (e) {}
          if (!ns || typeof ns[method] !== "function") { respond({ error: "chrome." + space + "." + method + " isn't available" }); return answer; }
          Promise.resolve().then(() => ns[method](...(args || [])))
            .then((value) => respond({ value }), (e) => respond({ error: String(e && e.message || e) }));
          return answer;
        }
      }
      const from = untabbed(sender);
      for (const listener of [...listeners]) if (run(listener, message, from)) keep = true;
      if (internal && !local && !inContent) tell(message, keep || answered ? "answers" : "passes", true);
      if (keep || answered) {
        // Once it has its answer, those who stepped aside may say nothing.
        if (internal && !local && !inContent) answer.then(() => tell(message, "settled", true));
        return answer;
      }
      if (local || !internal) return undefined;
      // Nothing here answers it. In Chrome that leaves the question to the
      // extension's other pages and its worker; WebKit takes the first
      // reply from any of them, an empty one from a page that only listens
      // for something else included, which would arrive before the worker's
      // real answer. So a page that has nothing to say steps aside, and
      // says nothing only once everyone else has had ample time, or as soon
      // as the worker and every other open page have said they let it pass
      // too. (Search)
      if (!background && !inContent) {
        const received = Date.now();
        const key = channel && keyOf(message);
        let check = () => {}, roll = null;
        const done = () => { waiting.delete(check); clearTimeout(late); clearTimeout(roll); };
        const late = setTimeout(() => { done(); silent(); }, 10000);
        // Without the channel (a page in a website's frame), only the wait.
        if (key) {
          // Only what was said about this message, not an identical one a while ago.
          const fresh = (said) => said && said.at >= received - 2000;
          check = () => {
            const entry = verdicts.get(key);
            if (answered || !entry) return;
            const workerSaid = entry.worker;
            const said = [...peers].filter((id) => !deaf.has(id) || entry.pages.has(id)).map((id) => entry.pages.get(id));
            // Someone has answered and it has gone: nothing to wait for.
            if ([workerSaid, ...said].some((p) => fresh(p) && p.verdict === "settled")) { done(); silent(); return; }
            // Someone is answering: wait for them to say it has gone, however
            // long that takes, so this page's nothing never comes first.
            if ([workerSaid, ...said].some((p) => fresh(p) && p.verdict === "answers")) { clearTimeout(late); return; }
            // With no background, nobody is to be heard from there.
            if ((hasWorker && !fresh(workerSaid)) || said.some((p) => !fresh(p))) return;
            done();
            silent();
          };
          waiting.add(check);
          check();
          // Still waiting on someone after a moment: those who don't say
          // they are here within a second are gone, and those who do but
          // have said nothing about this message didn't hear it.
          roll = setTimeout(() => {
            if (answered) return;
            const heard = new Set();
            const hear = (id) => heard.add(id);
            present.add(hear);
            channel.postMessage({ roll: true, from: me });
            setTimeout(() => {
              present.delete(hear);
              for (const id of [...peers]) if (!heard.has(id)) peers.delete(id);
              const entry = verdicts.get(key);
              for (const id of peers) { const p = entry && entry.pages.get(id); if (!p || p.at < received - 2000) deaf.add(id); }
              check();
            }, 1000);
          }, 200);
        }
        return answer;
      }
      return undefined;
    };
    // Only while there is a listener: a page with none says nothing, as it
    // would without the shim. The background's is WebKit's from the start:
    // a worker may add listeners only while it starts, and WebKit wakes it
    // for an event only if it knows a listener for it. (Search)
    let attached = false;
    const attach = () => { if (!attached) { attached = true; add(dispatch); } };
    put(target, "addListener", (f) => {
      if (typeof f !== "function") return;
      listeners.add(f);
      if (internal && eager) { join(); deliverRelayed = (m, s) => dispatch(m, s, true); }
      attach();
    });
    put(target, "removeListener", (f) => {
      listeners.delete(f);
      if (internal && eager && !listeners.size) leave();
      if (attached && !listeners.size && !(background && eager)) { attached = false; remove(dispatch); }
    });
    put(target, "hasListener", (f) => listeners.has(f));
    put(target, "hasListeners", () => listeners.size > 0);
    if (background && eager) attach();
  };

  // A reply that never came, asked for with a callback: Chrome calls back
  // with lastError set; WebKit calls back with nothing and no error, and
  // code that pings a tab to see whether its script is there waits for
  // ever. An empty answer is null, from the gate above, as in Chrome, and
  // sets nothing. A failure marked as one by the gate is lastError, or a
  // rejection when there is no callback. (Search)
  const isFailure = (reply) => reply !== null && typeof reply === "object" && typeof reply[failure] === "string";
  const replied = (promise, callback, gone) => {
    const settled = Promise.resolve(promise);
    if (!callback) return settled.then((reply) => { if (isFailure(reply)) throw new Error(reply[failure]); return reply; });
    settled.then(
      (reply) => isFailure(reply) ? withLastError(new Error(reply[failure]), () => callback())
        : reply === undefined ? withLastError(new Error(gone), () => callback())
        : callback(reply),
      (error) => withLastError(error, () => callback()));
  };

  // WebKit can lose a worker without knowing, its process stopped along
  // with a tab's, and then answers every message with nothing, for good.
  // So after a message, a page asks the worker itself (its shim answers) at
  // most every few seconds; asked three times, then once more after waking
  // it, and only then is the extension taken up afresh. (Search)
  let heard = 0;
  let checkWorker = () => {};
  if (typeof document !== "undefined" && !inContent && !background && hasWorker) {
    let asking = false;
    checkWorker = () => {
      if (asking || Date.now() - heard < 5000) return;
      asking = true;
      const ping = Object.getPrototypeOf(runtime).sendMessage;
      const ask = () => Promise.race([ping.call(runtime, { __safiencePing: true }), new Promise((r) => setTimeout(() => r("late"), 15000))]).catch(() => undefined);
      const pause = (ms) => new Promise((w) => setTimeout(w, ms));
      const tries = [() => ask(), () => pause(1000).then(ask), () => pause(1000).then(ask),
        () => native("background.wake", []).catch(() => {}).then(() => pause(1000)).then(ask)];
      const attempt = (i, last) => i >= tries.length || last === "pong" ? Promise.resolve(last) : tries[i]().then((r) => attempt(i + 1, r));
      const started = Date.now();
      attempt(0).then((r) => {
        // Any real answer from the worker meanwhile says it runs, too.
        if (r === "pong" || heard >= started) heard = Math.max(heard, Date.now());
        else native("background.revive", []).catch(() => {});
      }).finally(() => { asking = false; });
    };
  }

  for (const ns of new Set([chrome, root.browser].filter(Boolean))) {
    const rt = ns.runtime;
    if (rt && typeof rt.sendMessage === "function") {
      const proto = Object.getPrototypeOf(rt);
      const send = (proto && typeof proto.sendMessage === "function" ? proto.sendMessage : rt.sendMessage).bind(rt);
      put(rt, "sendMessage", (...args) => {
        const callback = args.length && typeof args[args.length - 1] === "function" ? args.pop() : null;
        const { message, own } = messageOf(args);
        const ours = !!(message && typeof message === "object" && Object.keys(message).some((k) => k.startsWith("__safience")));
        // Never heard back by the one that sends it, so said for it.
        if (!inContent && own) tell(message, "passes");
        checkWorker();
        let answer = Promise.resolve(send(...args)).then((r) => { if (r !== undefined) heard = Date.now(); return r; });
        const relayed = !inContent && own && !ours && message !== undefined ? relay(message) : null;
        if (relayed) {
          // A page that took the relayed copy says so at once, and answers
          // when it has one: what WebKit brought wins; when it brought
          // nothing, a page's answer does, if one said it would within a
          // moment (a page that lets it pass says nothing).
          let saidSo = false, answered, gotAnswer = false, wake = () => {};
          const waiter = {
            answering: () => { saidSo = true; wake(); },
            answer: (value) => { if (!gotAnswer) { gotAnswer = true; answered = value; wake(); } },
          };
          relays.set(relayed, waiter);
          const native = answer;
          answer = native.then(async (r) => {
            if (r !== undefined) return r;
            const waitFor = (ms, until) => new Promise((done) => {
              if (until()) return done();
              wake = () => { if (until()) done(); };
              setTimeout(done, ms);
            });
            await waitFor(300, () => saidSo || gotAnswer);
            if (saidSo && !gotAnswer) await waitFor(30000, () => gotAnswer);
            return gotAnswer ? answered : undefined;
          }).finally(() => relays.delete(relayed));
        }
        return replied(answer, callback, "The message port closed before a response was received.");
      });
    }
    const tabs = ns.tabs;
    if (tabs && typeof tabs.sendMessage === "function") {
      const send = tabs.sendMessage.bind(tabs);
      // A message for a tab reaches only its content scripts in WebKit. In
      // Chrome it reaches the extension's own pages framed in that tab too:
      // 1Password's sign-in banner is one. So the worker hands it to those
      // frames as well, and the first answer from either wins. (Search)
      const alsoFramed = (answer, tabId, message, options) => {
        const nav = chrome.webNavigation;
        if (!nav || typeof nav.getAllFrames !== "function" || typeof tabId !== "number") return answer;
        const wanted = options && typeof options.frameId === "number" ? options.frameId : null;
        const framed = Promise.resolve(nav.getAllFrames({ tabId })).then((frames) => {
          const urls = (frames || []).filter((f) => f.url && f.url.startsWith(ownPlace) && f.frameId !== 0 && (wanted === null || f.frameId === wanted)).map((f) => f.url);
          if (!urls.length) return undefined;
          return Object.getPrototypeOf(runtime).sendMessage.call(runtime, { __safienceToFrame: { tabId, urls, message } });
        }, () => undefined);
        return new Promise((resolve, reject) => {
          let left = 2, failed = null;
          const none = () => { if (--left === 0) failed ? reject(failed) : resolve(undefined); };
          answer.then((v) => v !== undefined ? resolve(v) : none(), (e) => { failed = e; none(); });
          framed.then((v) => v !== undefined ? resolve(v) : none(), () => none());
        });
      };
      put(tabs, "sendMessage", (tabId, message, options, callback) => {
        if (typeof options === "function") { callback = options; options = undefined; }
        const p = Promise.resolve(options === undefined ? send(tabId, message) : send(tabId, message, options));
        return replied(background ? alsoFramed(p, tabId, message, options) : p, callback, "Could not establish connection. Receiving end does not exist.");
      });
    }
    // browser is the same as chrome in WebKit; if it isn't, its events are
    // gathered too, only when listened to.
    gather(rt && rt.onMessage, ns === chrome, true);
    gather(rt && rt.onMessageExternal, ns === chrome, false);
  }

  // Google Translate uses this API in its worker, popup and content script.
  // WebKit exposes i18n without detectLanguage. The native answer performs
  // bounded on-device language recognition and receives only this string.
  if (chrome.i18n && typeof chrome.i18n.detectLanguage !== "function") {
    const detect = (text, callback) => {
      const answer = (async () => {
        if (typeof text !== "string") throw new TypeError("i18n.detectLanguage requires a string");
        if (!inContent && !embedded) return native("i18n.detectLanguage", [text]);
        const reply = await runtime.sendMessage({ __safienceCall: { space: "i18n", method: "detectLanguage", args: [text] } });
        if (!reply) throw new Error("i18n.detectLanguage had no answer from the extension's background");
        if (reply.error) throw new Error(reply.error);
        return reply.value;
      })();
      if (typeof callback !== "function") return answer;
      answer.then((value) => callback(value), (error) => withLastError(error, callback));
    };
    put(chrome.i18n, "detectLanguage", detect);
    if (root.browser && root.browser !== chrome && root.browser.i18n
        && typeof root.browser.i18n.detectLanguage !== "function") put(root.browser.i18n, "detectLanguage", detect);
  }

  if (inContent) {
    // A content script reads an extension page's frame as
    // webkit-masked-url://hidden/, src and attribute alike, even one of its
    // own extension's that it put there itself. Chrome gives the address
    // back, and code that posts to the frame with that address as the
    // target origin throws instead. So an address of this extension that
    // its scripts set is what src gives them back, and only that. (Search)
    if (root.HTMLIFrameElement) {
      const given = new WeakMap();
      const remember = (frame, value) => {
        const address = String(value);
        if (ownPlace && address.startsWith(ownPlace)) given.set(frame, address); else given.delete(frame);
      };
      const proto = HTMLIFrameElement.prototype;
      const d = Object.getOwnPropertyDescriptor(proto, "src");
      if (d && d.get && d.set && d.configurable) {
        Object.defineProperty(proto, "src", Object.assign({}, d, {
          get() {
            const shown = d.get.call(this);
            return given.has(this) && shown.startsWith("webkit-masked-url:") ? given.get(this) : shown;
          },
          set(value) { remember(this, value); d.set.call(this, value); },
        }));
        const setAttribute = Element.prototype.setAttribute;
        Element.prototype.setAttribute = function (name, value) {
          if (this instanceof HTMLIFrameElement && String(name).toLowerCase() === "src") remember(this, value);
          return setAttribute.apply(this, arguments);
        };
        const getAttribute = Element.prototype.getAttribute;
        Element.prototype.getAttribute = function (name) {
          const shown = getAttribute.apply(this, arguments);
          if (this instanceof HTMLIFrameElement && String(name).toLowerCase() === "src" && given.has(this)
            && typeof shown === "string" && shown.startsWith("webkit-masked-url:")) return given.get(this);
          return shown;
        };
      }
    }
    return;
  }

  // In a website's frame, everything WebKit keeps to the extension's own
  // process goes through the worker instead. What stays direct is what
  // WebKit lets a content script call too. (Search)
  if (embedded) {
    const direct = new Set(["runtime", "storage", "i18n", "extension", "permissions", "dom", "test"]);
    const ask = (space, method, args) => {
      while (args.length && args[args.length - 1] === undefined) args.pop();
      if (space === "scripting" && method === "executeScript" && typeof (args[0] && args[0].func) === "function") {
        return Promise.reject(new Error("scripting.executeScript with a function isn't available to an extension's page in a website's frame"));
      }
      let payload;
      try { payload = JSON.parse(JSON.stringify(args)); } catch (e) { return Promise.reject(e); }
      return Promise.resolve(Object.getPrototypeOf(runtime).sendMessage.call(runtime, { __safienceCall: { space, method, args: payload } })).then((reply) => {
        if (!reply) throw new Error("chrome." + space + "." + method + " had no answer from the extension's background");
        if (reply.error) throw new Error(reply.error);
        return reply.value;
      });
    };
    // Some members WebKit answers from the object itself, ahead of anything
    // set on it (windows.create, update and remove). Put there, ours reads
    // back as WebKit's, and the call still ends the process. A namespace
    // like that is given through a stand-in chrome instead, which has ours
    // for those members and WebKit's own objects for the rest, so listeners
    // still go on WebKit's events. (Search)
    const stand = new Map();
    for (const space of spaces) {
      if (direct.has(space)) continue;
      let ns; try { ns = chrome[space]; } catch (e) { continue; }
      if (!ns || typeof ns !== "object") continue;
      const names = new Set();
      for (let o = ns; o && o !== Object.prototype; o = Object.getPrototypeOf(o)) Object.getOwnPropertyNames(o).forEach((k) => names.add(k));
      const mine = new Map();
      const own = (name, value) => { put(ns, name, value); mine.set(name, value); };
      for (const name of names) {
        if (name === "constructor" || /^on[A-Z]/.test(name)) continue;
        let f; try { f = ns[name]; } catch (e) { continue; }
        if (typeof f !== "function") continue;
        // A port can't be carried over: one that closes at once, as
        // Chrome's does when nothing answers, rather than a dead process.
        if (name === "connect") {
          own(name, (...args) => {
            const port = { name: (args.find((a) => a && typeof a === "object") || {}).name || "", sender: undefined,
              postMessage: () => {}, disconnect: () => {}, onMessage: event(), onDisconnect: event() };
            setTimeout(() => withLastError(new Error("Could not establish connection. Receiving end does not exist."), () => {
              for (const f of [...port.onDisconnect.listeners]) f(port);
            }));
            return port;
          });
          continue;
        }
        own(name, (...args) => {
          const callback = args.length && typeof args[args.length - 1] === "function" ? args.pop() : null;
          const answer = ask(space, name, args);
          // A message nobody in the tab answered reads as Chrome says it.
          if (space === "tabs" && name === "sendMessage") return replied(answer, callback, "Could not establish connection. Receiving end does not exist.");
          if (!callback) return answer;
          answer.then((value) => callback(value), (error) => withLastError(error, callback));
        });
      }
      const lost = new Map([...mine].filter(([name, value]) => ns[name] !== value));
      if (!lost.size) continue;
      stand.set(space, new Proxy(ns, {
        get: (target, key) => lost.has(key) ? lost.get(key) : Reflect.get(target, key),
        defineProperty: (target, key, d) => lost.has(key) && "value" in d ? (lost.set(key, d.value), true) : Reflect.defineProperty(target, key, d),
      }));
    }
    // Set through the fixed accessors above, which take a replacement that
    // still carries the APIs; on browser too, the same object in WebKit.
    if (stand.size) {
      const standIn = new Proxy(chrome, { get: (target, key) => stand.has(key) ? stand.get(key) : Reflect.get(target, key) });
      try { root.chrome = standIn; } catch (e) {}
      try { if (root.browser) root.browser = standIn; } catch (e) {}
    }
  }

  // Native messaging the extension asked for only as an optional
  // permission, which the preparation gave it outright for the shim's way
  // to Safience: Chrome asks the person before granting it, and so does
  // Safience, which keeps the answer (ExtensionAnswers, permissions.native).
  const added = /*__SAFIENCE_ADDED__*/[];
  if (added.includes("nativeMessaging") && (manifest.optional_permissions || []).includes("nativeMessaging") && chrome.permissions) {
    const ns = chrome.permissions;
    const split = (p) => {
      const list = (p && p.permissions) || [];
      const rest = { ...(p || {}), permissions: list.filter((x) => x !== "nativeMessaging") };
      const empty = !rest.permissions.length && !(rest.origins && rest.origins.length);
      return { asks: list.includes("nativeMessaging"), rest, empty };
    };
    for (const [name, action] of [["request", "request"], ["contains", "has"], ["remove", "remove"]]) {
      const original = typeof ns[name] === "function" ? ns[name].bind(ns) : null;
      if (!original) continue;
      put(ns, name, (p, callback) => {
        const { asks, rest, empty } = split(p);
        const answer = (async () => {
          if (asks) {
            const yes = await native("permissions.native", [action]);
            if (!yes && action !== "remove") return false;
          }
          return empty ? true : original(rest);
        })();
        if (typeof callback !== "function") return answer;
        answer.then((value) => callback(value), (error) => withLastError(error, callback));
      });
    }
  }

  // Whole namespaces WebKit lacks, answered by Safience (ExtensionAnswers).
  const define = (name, methods, events = [], extra = {}) => {
    if (chrome[name]) return;
    const api = Object.assign({}, extra);
    for (const m of methods) api[m] = call(name + "." + m);
    for (const e of events) api[e] = event();
    put(chrome, name, api);
    if (root.browser && root.browser !== chrome && !root.browser[name]) put(root.browser, name, api);
  };
  define("offscreen", ["createDocument", "closeDocument", "hasDocument"], [],
    { Reason: new Proxy({}, { get: (_, key) => String(key) }) });
  // Only what the extension itself is, never another's.
  define("management", ["getSelf", "get"], ["onInstalled", "onUninstalled", "onEnabled", "onDisabled"]);

  // A tab number the extension knows, as Safience can find the tab: its
  // place in the window and its address, as WebKit tells them. (Search's
  // tabs.describe)
  const place = async (tabId) => {
    if (typeof tabId !== "number" || !chrome.tabs || typeof chrome.tabs.get !== "function") return null;
    try { const t = await chrome.tabs.get(tabId); return t ? { index: t.index, url: t.url || "" } : null; } catch (e) { return null; }
  };
  // The side panel, Safience's (ExtensionSidePanel.swift).
  if (!chrome.sidePanel) {
    const placed = (api) => (...args) => {
      const callback = args.length && typeof args[args.length - 1] === "function" ? args.pop() : null;
      const answer = (async () => {
        const options = args[0] && typeof args[0] === "object" ? { ...args[0] } : {};
        if (typeof options.tabId === "number") options.__place = await place(options.tabId);
        return native(api, [options]);
      })();
      if (!callback) return answer;
      answer.then((value) => callback(value), (error) => withLastError(error, callback));
    };
    put(chrome, "sidePanel", {
      setOptions: placed("sidePanel.setOptions"), getOptions: placed("sidePanel.getOptions"),
      setPanelBehavior: call("sidePanel.setPanelBehavior"), getPanelBehavior: call("sidePanel.getPanelBehavior"),
      open: placed("sidePanel.open"), close: placed("sidePanel.close"),
      onOpened: event(), onClosed: event(),
    });
  }
  // The popup its button opens, set for every tab, told to Safience, whose
  // pane shows it (ExtensionPopup.swift); one set for a single tab is
  // WebKit's alone.
  for (const name of ["action", "browserAction"]) {
    const ns = chrome[name];
    if (!ns || typeof ns.setPopup !== "function") continue;
    const set = ns.setPopup.bind(ns);
    put(ns, "setPopup", (details, ...rest) => {
      try { if (details && details.tabId === undefined) native("action.popup", [String(details.popup || "")]).catch(() => {}); } catch (e) {}
      return set(details, ...rest);
    });
  }
  if (typeof runtime.getContexts !== "function") put(runtime, "getContexts", call("runtime.getContexts"));
})();
