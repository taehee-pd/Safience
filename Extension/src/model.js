// The records Safience keeps in iCloud, and the rules between them and a
// tree of bookmarks: the same as PadCore's SyncModel.swift, which the app
// uses. A change to one is a change to both; Extension/tests/model.test.mjs
// and PadCore's SyncModelTests check the same cases.
//
// Nothing here touches Chrome or the network, so it runs under Node for tests.

export const ZONE = 'Sync';

export const KINDS = {
  Space: ['name', 'symbol', 'color'],
  BookmarkNode: ['space', 'parent', 'position', 'title', 'url'],
  PinnedTab: ['space', 'position', 'title', 'url'],
  DeviceTabs: ['device', 'deviceName', 'browser', 'space', 'updated', 'tabs'],
};

// CloudKit's field types for the fields that aren't text.
const TYPES = { position: 'DOUBLE', updated: 'TIMESTAMP' };

export function emptyMirror() {
  return { spaces: {}, bookmarks: {}, pinned: {}, deviceTabs: {} };
}

export function newName() {
  return crypto.randomUUID().toUpperCase();
}

// MARK: Records, as CloudKit Web Services has them

// A CloudKit record ({ recordName, recordType, fields: { name: { value } } })
// into the mirror; false for one that can't be read.
export function take(mirror, record) {
  const name = record.recordName;
  const value = (key) => record.fields?.[key]?.value;
  switch (record.recordType) {
    case 'Space': {
      if (typeof value('name') !== 'string') return false;
      mirror.spaces[name] = { id: name, name: value('name'), symbol: value('symbol') || 'square.grid.2x2', color: value('color') || 'blue' };
      return true;
    }
    case 'BookmarkNode': {
      if (typeof value('space') !== 'string') return false;
      mirror.bookmarks[name] = {
        id: name, space: value('space'), parent: value('parent') || null, position: Number(value('position') ?? 0),
        title: value('title') || '', url: value('url') || null,
      };
      return true;
    }
    case 'PinnedTab': {
      if (typeof value('space') !== 'string' || !value('url')) return false;
      mirror.pinned[name] = { id: name, space: value('space'), position: Number(value('position') ?? 0), title: value('title') || '', url: value('url') };
      return true;
    }
    case 'DeviceTabs': {
      if (typeof value('device') !== 'string' || typeof value('space') !== 'string') return false;
      let tabs = [];
      try { tabs = JSON.parse(value('tabs') || '[]'); } catch (_) {}
      mirror.deviceTabs[name] = {
        id: name, device: value('device'), deviceName: value('deviceName') || '', browser: value('browser') || '',
        space: value('space'), updated: Number(value('updated') || 0), tabs: Array.isArray(tabs) ? tabs : [],
      };
      return true;
    }
    default:
      return false;
  }
}

export function remove(mirror, name) {
  for (const kind of ['spaces', 'bookmarks', 'pinned', 'deviceTabs']) delete mirror[kind][name];
}

// What a mirror entry saves as: every field of its kind, those without a
// value left out, which a replace clears.
export function toRecord(mirror, name) {
  let kind; let item;
  if (mirror.spaces[name]) { kind = 'Space'; item = mirror.spaces[name]; }
  else if (mirror.bookmarks[name]) { kind = 'BookmarkNode'; item = mirror.bookmarks[name]; }
  else if (mirror.pinned[name]) { kind = 'PinnedTab'; item = mirror.pinned[name]; }
  else if (mirror.deviceTabs[name]) { kind = 'DeviceTabs'; item = { ...mirror.deviceTabs[name], tabs: JSON.stringify(mirror.deviceTabs[name].tabs) }; }
  else return null;
  const fields = {};
  for (const key of KINDS[kind]) {
    const value = item[key];
    if (value === null || value === undefined || value === '') continue;
    fields[key] = TYPES[key] ? { value: Number(value), type: TYPES[key] } : { value: String(value) };
  }
  return { recordType: kind, recordName: name, fields };
}

export function deviceTabsName(device, space) {
  return `tabs.${device}.${space}`;
}

// MARK: Positions

// Positions for `names` in this order: the longest run already in
// increasing order keeps theirs, the rest go between their neighbours; when
// a gap has run out of room, all are numbered again.
export function positions(names, previous) {
  const known = names.map((n) => (n in previous ? previous[n] : null));
  const keep = increasingRun(known);
  const out = new Array(names.length).fill(0);
  let index = 0;
  while (index < names.length) {
    if (keep.has(index)) { out[index] = known[index]; index += 1; continue; }
    const start = index;
    while (index < names.length && !keep.has(index)) index += 1;
    const below = start > 0 ? out[start - 1] : null;
    const above = index < names.length ? known[index] : null;
    const count = index - start;
    for (let k = 0; k < count; k++) {
      if (below !== null && above !== null) out[start + k] = below + (above - below) * (k + 1) / (count + 1);
      else if (below !== null) out[start + k] = below + k + 1;
      else if (above !== null) out[start + k] = above - (count - k);
      else out[start + k] = k + 1;
    }
  }
  for (let i = 1; i < out.length; i++) {
    if (!(out[i] > out[i - 1]) || out[i] - out[i - 1] < 1e-9) return names.map((_, j) => j + 1);
  }
  return out;
}

function increasingRun(values) {
  const tails = [];
  const before = new Array(values.length).fill(-1);
  values.forEach((value, index) => {
    if (value === null) return;
    let low = 0; let high = tails.length;
    while (low < high) {
      const mid = (low + high) >> 1;
      if (values[tails[mid]] < value) low = mid + 1; else high = mid;
    }
    if (low > 0) before[index] = tails[low - 1];
    if (low === tails.length) tails.push(index); else tails[low] = index;
  });
  const run = new Set();
  let at = tails.length ? tails[tails.length - 1] : -1;
  while (at >= 0) { run.add(at); at = before[at]; }
  return run;
}

// MARK: Trees and records

const byPosition = (a, b) => (a.position - b.position) || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0);

// The space's bookmarks as a tree: { id, title, url, children }. A bookmark
// whose folder hasn't arrived shows at the top until it does; two folders
// each inside the other are broken at the top.
export function tree(space, mirror) {
  const nodes = Object.values(mirror.bookmarks).filter((b) => b.space === space);
  const names = new Set(nodes.map((n) => n.id));
  const children = new Map();
  for (const node of nodes) {
    const parent = node.parent && names.has(node.parent) && node.parent !== node.id ? node.parent : null;
    if (!children.has(parent)) children.set(parent, []);
    children.get(parent).push(node);
  }
  const placed = new Set();
  const build = (parent) => (children.get(parent) || []).slice().sort(byPosition).flatMap((node) => {
    if (placed.has(node.id)) return [];
    placed.add(node.id);
    return [node.url ? { id: node.id, title: node.title, url: node.url } : { id: node.id, title: node.title, url: null, children: build(node.id) }];
  });
  const top = build(null);
  for (const node of nodes) {
    if (placed.has(node.id)) continue;
    placed.add(node.id);
    top.push(node.url ? { id: node.id, title: node.title, url: node.url } : { id: node.id, title: node.title, url: null, children: build(node.id) });
  }
  return top;
}

// The records of a space's bookmark tree, built on what the mirror holds:
// positions kept wherever the order is unchanged, a bookmark whose folder
// hasn't arrived kept in it.
export function flatten(list, space, previous, parent = null, out = {}) {
  const prior = Object.fromEntries(Object.values(previous.bookmarks).map((b) => [b.id, b.position]));
  const places = positions(list.map((n) => n.id), prior);
  list.forEach((node, index) => {
    let folder = parent;
    let position = places[index];
    const known = previous.bookmarks[node.id];
    if (parent === null && known && known.parent && !previous.bookmarks[known.parent]) {
      folder = known.parent;
      position = known.position;
    }
    out[node.id] = { id: node.id, space, parent: folder, position, title: node.title || '', url: node.url || null };
    if (!node.url) flatten(node.children || [], space, previous, node.id, out);
  });
  return out;
}

// The records to save and delete for `old` to become `next`, among the
// given kinds.
export function changes(old, next, kinds = ['spaces', 'bookmarks', 'pinned']) {
  const save = []; const del = [];
  const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
  for (const kind of kinds) {
    for (const [name, value] of Object.entries(next[kind])) if (!same(old[kind][name], value)) save.push(name);
    for (const name of Object.keys(old[kind])) if (!(name in next[kind])) del.push(name);
  }
  return { save: save.sort(), delete: del.sort() };
}

// MARK: Addresses

// Two addresses that are the same page, as Safience's Bookmarks.key has it:
// no difference for case in the scheme and host, or a slash ending the path.
export function urlKey(address) {
  try {
    const url = new URL(address);
    let path = url.pathname;
    if (path.endsWith('/')) path = path.slice(0, -1);
    return `${url.protocol}//${url.host.toLowerCase()}${path}${url.search}${url.hash}`;
  } catch (_) {
    return address;
  }
}

// Sign-in pages, as Safience's SignIn.swift tells them.
const SIGN_IN_HOSTS = [
  'accounts.google.com', 'login.microsoftonline.com', 'login.microsoft.com', 'login.live.com',
  'appleid.apple.com', 'idmsa.apple.com', 'account.apple.com', 'id.atlassian.com', 'signin.aws.amazon.com',
  'login.salesforce.com', 'accounts.zoho.com', 'login.yahoo.com', 'auth.openai.com',
];
const SIGN_IN_DOMAINS = ['okta.com', 'oktapreview.com', 'okta-emea.com', 'auth0.com', 'onelogin.com',
  'duosecurity.com', 'pingone.com', 'pingidentity.com', 'jumpcloud.com'];
const SIGN_IN_WORDS = new Set(['login', 'log-in', 'log_in', 'signin', 'sign-in', 'sign_in', 'signon', 'sign-on',
  'signup', 'sign-up', 'sign_up', 'sso', 'saml', 'saml2', 'oauth', 'oauth2', 'authorize', 'authenticate', 'auth',
  'session', 'sessions', 'mfa', '2fa', 'two-factor', 'challenge', 'verify', 'password', 'reset-password']);
// Query names that make an address a credential (SyncPlan.secretNames).
const SECRET_NAMES = new Set(['code', 'token', 'access_token', 'id_token', 'refresh_token', 'session', 'sessionid',
  'sid', 'sig', 'signature', 'auth', 'authuser_token', 'password', 'otp', 'key', 'api_key', 'apikey']);

const within = (host, domain) => host === domain || host.endsWith('.' + domain);

export function isSignInPage(address) {
  let url;
  try { url = new URL(address); } catch (_) { return false; }
  const host = url.hostname.toLowerCase();
  if (SIGN_IN_HOSTS.some((h) => within(host, h)) || SIGN_IN_DOMAINS.some((d) => within(host, d))) return true;
  if (url.pathname.toLowerCase().split('/').some((part) => SIGN_IN_WORDS.has(part))) return true;
  return url.searchParams.has('client_id') && url.searchParams.has('redirect_uri');
}

// A web address another device may see: never a sign-in page or one that
// carries a credential.
export function isShareable(address) {
  let url;
  try { url = new URL(address); } catch (_) { return false; }
  if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password || isSignInPage(address)) return false;
  const names = [...url.searchParams.keys()];
  const fragment = new URLSearchParams(url.hash.replace(/^#/, ''));
  names.push(...fragment.keys());
  return !names.some((name) => SECRET_NAMES.has(name.toLowerCase()));
}

// MARK: Joining

// A Chrome tree ({ chromeId, title, url, children }) joined to a space's
// tree from iCloud, as Safience's Bookmarks.merge joins an import: a link
// matches one at the same address in the same folder, a folder one with its
// title. Returns the record name each Chrome bookmark takes: iCloud's for a
// match, a new one otherwise. Nothing of iCloud's is lost.
export function joinTrees(chrome, cloud, map = {}) {
  const remaining = [...cloud];
  for (const node of chrome) {
    if (node.url) {
      const at = remaining.findIndex((c) => c.url && urlKey(c.url) === urlKey(node.url));
      map[node.chromeId] = at >= 0 ? remaining.splice(at, 1)[0].id : newName();
    } else {
      const at = remaining.findIndex((c) => !c.url && c.title === node.title);
      const match = at >= 0 ? remaining.splice(at, 1)[0] : null;
      map[node.chromeId] = match ? match.id : newName();
      joinTrees(node.children || [], match ? match.children || [] : [], map);
    }
  }
  return map;
}
