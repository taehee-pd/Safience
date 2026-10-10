// The extension's service worker: Chrome's bookmarks, pinned tabs and open
// tabs to and from the Safience space this Chrome profile is paired with.
//
// - Bookmarks, both ways: the bookmarks bar is the space's top level, Other
//   Bookmarks a folder of that name in it. One computer per Chrome profile
//   writes them (the writer): Chrome Sync carries them to the profile's
//   other computers, which would otherwise send each change twice.
// - Pinned tabs, both ways, on every computer: one pinned here pins it in
//   Safience; one pinned there opens pinned here. Nothing is ever closed:
//   a pinned tab removed elsewhere is unpinned, if it is still on its page.
// - Open tabs, this computer's, for Safience to list; Safience's, for the
//   popup to list. Never opened by themselves.
//
// Chrome runs one copy of the extension per profile, and none sees another
// profile: each pairs with a space of its own.

import config from '../config.js';
import { CloudKit, SignedOut } from './cloudkit.js';
import {
  changes, deviceTabsName, emptyMirror, flatten, isShareable, joinTrees, newName, remove, take,
  toRecord, tree, urlKey,
} from './model.js';

const ck = new CloudKit(config);
const OTHER_TITLE = 'Other Bookmarks';
const DAY = 24 * 60 * 60 * 1000;
const STALE = 14 * DAY;

// MARK: State, in chrome.storage.local

async function load() {
  const { state } = await chrome.storage.local.get('state');
  const loaded = state || {};
  return {
    installId: loaded.installId || newName(),
    deviceName: loaded.deviceName || defaultDeviceName(),
    signedIn: !!loaded.signedIn,
    paired: loaded.paired || null,
    syncToken: loaded.syncToken || null,
    mirror: loaded.mirror || emptyMirror(),
    bookmarkMap: loaded.bookmarkMap || {},
    pinnedMap: loaded.pinnedMap || {},
    pinnedOps: loaded.pinnedOps || { save: [], delete: [] },
    pendingSpace: !!loaded.pendingSpace,
    lastSync: loaded.lastSync || 0,
    error: loaded.error || '',
  };
}

async function store(state) {
  await chrome.storage.local.set({ state });
}

function browserName() {
  const brands = (navigator.userAgentData?.brands || []).map((b) => b.brand);
  for (const name of ['Microsoft Edge', 'Brave', 'Opera', 'Vivaldi', 'Arc', 'Dia']) {
    if (brands.some((b) => b.includes(name))) return name.replace('Microsoft ', '');
  }
  return 'Chrome';
}

function defaultDeviceName() {
  const platform = navigator.userAgentData?.platform || '';
  if (/mac/i.test(platform)) return 'Mac';
  if (/win/i.test(platform)) return 'Windows';
  if (/cros/i.test(platform)) return 'Chromebook';
  return platform || 'Computer';
}

// The computer that writes this profile's bookmarks: the first to pair,
// kept in Chrome Sync's storage, which the profile's computers share.
async function isWriter(state) {
  if (!state.paired) return false;
  const { safienceWriter } = await chrome.storage.sync.get('safienceWriter');
  return !!safienceWriter && safienceWriter.install === state.installId && safienceWriter.space === state.paired.space;
}

// MARK: One thing at a time

// Every task that reads and writes the state runs alone: a sync, pairing,
// what the popup asks. Otherwise one would save over another's changes.
let lock = Promise.resolve();
function exclusive(task) {
  const run = lock.then(task, task);
  lock = run.catch(() => {});
  return run;
}

let applying = false;
let quietUntil = 0;

function sync(reason) {
  return exclusive(async () => {
    const state = await load();
    try {
      if (!(await ck.token())) {
        state.signedIn = false;
        return state;
      }
      await pull(state);
      await push(state);
      state.signedIn = true;
      state.error = '';
      state.lastSync = Date.now();
    } catch (error) {
      if (error instanceof SignedOut) {
        state.signedIn = false;
        state.error = 'Signed out of iCloud. Sign in again.';
      } else {
        state.error = String(error.message || error);
      }
      console.warn('Safience sync', reason, error);
    } finally {
      await store(state);
      await badge(state);
    }
    return state;
  });
}

async function badge(state) {
  await chrome.action.setBadgeText({ text: state.error ? '!' : '' });
  await chrome.action.setBadgeBackgroundColor({ color: '#d97706' });
}

// MARK: From iCloud

async function pull(state) {
  let result = await ck.changes(state.syncToken);
  if (result.zoneMissing) {
    await ck.ensureZone();
    state.syncToken = null;
    result = await ck.changes(null);
  }
  const before = structuredClone(state.mirror);
  // The paired space removed in Safience: unpaired, Chrome's bookmarks kept.
  if (state.paired && result.records.some((r) => r.deleted && r.recordName === state.paired.space)) {
    state.paired = null;
    state.bookmarkMap = {};
    state.pinnedMap = {};
    state.error = 'The space this profile was paired with was removed in Safience. Pair it again.';
  }
  const deleted = new Set();
  for (const record of result.records) {
    if (record.deleted) {
      remove(state.mirror, record.recordName);
      deleted.add(record.recordName);
    } else {
      take(state.mirror, record);
    }
  }
  state.syncToken = result.syncToken;
  if (!state.paired) return;
  // Chrome takes iCloud's bookmarks only when iCloud's changed: a sync set off by an
  // edit made here would otherwise write the older copy back over the edit (the old
  // title or place, or the bookmark again) before push() could send it.
  if (bookmarksDiffer(before, state.mirror, state.paired.space) && await isWriter(state)) await applyBookmarks(state, deleted);
  await applyPinned(state, before);
}

function bookmarksDiffer(a, b, space) {
  const of = (mirror) => JSON.stringify(Object.keys(mirror.bookmarks).sort()
    .filter((name) => mirror.bookmarks[name].space === space).map((name) => [name, mirror.bookmarks[name]]));
  return of(a) !== of(b);
}

// MARK: Bookmarks

async function chromeRoots() {
  const [root] = await chrome.bookmarks.getTree();
  const kids = root.children || [];
  const bar = kids.find((n) => n.folderType === 'bookmarks-bar') || kids.find((n) => n.id === '1') || kids[0];
  const other = kids.find((n) => n.folderType === 'other') || kids.find((n) => n.id === '2') || kids[1];
  return { bar, other };
}

function chromeNodes(nodes) {
  return (nodes || []).map((n) => ({
    chromeId: n.id, title: n.title, url: n.url || null, children: n.url ? undefined : chromeNodes(n.children),
  }));
}

// Chrome's bookmarks as the space's tree, in record names: the bar's at
// the top, Other Bookmarks a folder at the end when it has anything.
async function localTree(state) {
  const { bar, other } = await chromeRoots();
  const seen = new Set();
  const named = (nodes) => nodes.map((n) => {
    seen.add(n.chromeId);
    state.bookmarkMap[n.chromeId] ||= newName();
    return { id: state.bookmarkMap[n.chromeId], title: n.title, url: n.url, children: n.url ? undefined : named(n.children) };
  });
  const top = named(chromeNodes(bar.children));
  if (other && ((other.children || []).length || state.bookmarkMap[other.id])) {
    seen.add(other.id);
    state.bookmarkMap[other.id] ||= newName();
    top.push({ id: state.bookmarkMap[other.id], title: OTHER_TITLE, url: null, children: named(chromeNodes(other.children)) });
  }
  // Removed from Chrome: no longer anyone's.
  for (const id of Object.keys(state.bookmarkMap)) if (!seen.has(id)) delete state.bookmarkMap[id];
  return top;
}

async function pushBookmarks(state) {
  const space = state.paired.space;
  const local = await localTree(state);
  const next = flatten(local, space, state.mirror);
  const others = Object.fromEntries(Object.entries(state.mirror.bookmarks).filter(([, b]) => b.space !== space));
  const nextMirror = { ...state.mirror, bookmarks: { ...others, ...next } };
  const diff = changes(state.mirror, nextMirror, ['bookmarks']);
  await send(state, nextMirror, diff);
}

// iCloud's tree into Chrome: made, renamed and moved; and removed only
// when iCloud says the record was deleted (`deleted`), never because its
// copy lacks one: a bookmark made in Chrome and not yet sent (a failed
// request, a pairing under way) must stay.
async function applyBookmarks(state, deleted = new Set()) {
  const space = state.paired.space;
  const cloud = tree(space, state.mirror);
  const reverse = Object.fromEntries(Object.entries(state.bookmarkMap).map(([chromeId, name]) => [name, chromeId]));
  const { bar, other } = await chromeRoots();
  const otherName = state.bookmarkMap[other?.id];
  applying = true;
  try {
    await reconcile(cloud.filter((n) => n.id !== otherName), bar.id, reverse, state);
    const otherNode = cloud.find((n) => n.id === otherName);
    if (otherNode && other) await reconcile(otherNode.children || [], other.id, reverse, state);
    for (const [chromeId, name] of Object.entries(state.bookmarkMap)) {
      if (!deleted.has(name) || chromeId === other?.id || chromeId === bar.id) continue;
      try { await chrome.bookmarks.removeTree(chromeId); } catch (_) {}
      delete state.bookmarkMap[chromeId];
    }
  } finally {
    applying = false;
    quietUntil = Date.now() + 1500;
  }
}

async function chromeNode(id) {
  try { return (await chrome.bookmarks.get(id))[0] || null; } catch (_) { return null; }
}

async function reconcile(list, parentId, reverse, state) {
  let previous = null;
  for (const node of list) {
    // Right after the one before it, or first.
    const after = previous ? await chromeNode(previous) : null;
    const target = after && after.parentId === parentId ? after.index + 1 : 0;
    let existing = reverse[node.id] ? await chromeNode(reverse[node.id]) : null;
    if (reverse[node.id] && !existing) {
      // Its bookmark was removed in Chrome and not sent yet: the next push deletes
      // it from iCloud, rather than this making it again.
      continue;
    }
    if (existing && !!existing.url !== !!node.url) {
      // A folder became a link or the other way: made again.
      try { await chrome.bookmarks.removeTree(existing.id); } catch (_) {}
      delete state.bookmarkMap[existing.id];
      existing = null;
    }
    if (!existing) {
      existing = await chrome.bookmarks.create({ parentId, index: target, title: node.title, url: node.url || undefined });
      state.bookmarkMap[existing.id] = node.id;
      reverse[node.id] = existing.id;
    } else {
      if (existing.title !== node.title || (node.url && existing.url !== node.url)) {
        await chrome.bookmarks.update(existing.id, node.url ? { title: node.title, url: node.url } : { title: node.title });
      }
      if (existing.parentId !== parentId || existing.index !== target) {
        // Chrome counts a move down its own folder before taking it out.
        const index = existing.parentId === parentId && existing.index < target ? target + 1 : target;
        await chrome.bookmarks.move(existing.id, { parentId, index });
      }
    }
    if (!node.url) await reconcile(node.children || [], existing.id, reverse, state);
    previous = existing.id;
  }
}

// MARK: Pinned tabs

async function mainWindow() {
  try {
    const window = await chrome.windows.getLastFocused({ populate: true, windowTypes: ['normal'] });
    return window && !window.incognito ? window : null;
  } catch (_) {
    return null;
  }
}

async function allTabs() {
  return (await chrome.tabs.query({ windowType: 'normal' })).filter((t) => !t.incognito);
}

// Each record to the pinned tab showing it, after a restart (new tab ids)
// by address.
async function rebindPinned(state) {
  const tabs = (await allTabs()).filter((t) => t.pinned);
  const byId = new Map(tabs.map((t) => [t.id, t]));
  const bound = new Set();
  for (const [name, entry] of Object.entries(state.pinnedMap)) {
    if (byId.has(entry.tabId)) bound.add(entry.tabId);
    else entry.tabId = null;
  }
  for (const [name, entry] of Object.entries(state.pinnedMap)) {
    if (entry.tabId) continue;
    const match = tabs.find((t) => !bound.has(t.id) && urlKey(t.url || '') === urlKey(entry.url));
    if (match) { entry.tabId = match.id; bound.add(match.id); }
  }
  // Pinned here while the extension wasn't looking: sent as new.
  for (const tab of tabs) {
    if (bound.has(tab.id) || !tab.url || !isShareable(tab.url)) continue;
    const known = Object.values(state.mirror.pinned).find((p) => p.space === state.paired.space && urlKey(p.url) === urlKey(tab.url)
      && !state.pinnedMap[p.id]?.tabId);
    const name = known ? known.id : newName();
    state.pinnedMap[name] = { tabId: tab.id, url: known ? known.url : tab.url };
    bound.add(tab.id);
    if (!known) queuePinned(state, 'save', name);
  }
}

function queuePinned(state, op, name) {
  const other = op === 'save' ? 'delete' : 'save';
  state.pinnedOps[other] = state.pinnedOps[other].filter((n) => n !== name);
  if (!state.pinnedOps[op].includes(name)) state.pinnedOps[op].push(name);
}

async function applyPinned(state, before) {
  const space = state.paired.space;
  await rebindPinned(state);
  const wanted = Object.values(state.mirror.pinned).filter((p) => p.space === space).sort((a, b) => a.position - b.position);
  const window = await mainWindow();
  // Just after Chrome starts, its own pinned tabs may not be back yet:
  // opening iCloud's then would make them twice.
  const { startedAt } = await chrome.storage.session.get('startedAt');
  const settling = startedAt && Date.now() - startedAt < 60000;
  for (const pin of wanted) {
    const entry = state.pinnedMap[pin.id];
    if (entry?.tabId) continue;
    if (!window || settling) break;
    const tab = await chrome.tabs.create({ windowId: window.id, url: pin.url, pinned: true, active: false });
    state.pinnedMap[pin.id] = { tabId: tab.id, url: pin.url };
  }
  // Unpinned elsewhere: unpinned here if it is still on its page; never closed.
  for (const [name, entry] of Object.entries(state.pinnedMap)) {
    if (state.mirror.pinned[name] || !before.pinned[name] || state.pinnedOps.save.includes(name)) continue;
    if (entry.tabId) {
      try {
        const tab = await chrome.tabs.get(entry.tabId);
        if (urlKey(tab.url || '') === urlKey(entry.url)) await chrome.tabs.update(tab.id, { pinned: false });
      } catch (_) {}
    }
    delete state.pinnedMap[name];
  }
}

// Tabs unpinned here, or closed other than with their window (Chrome
// quitting), since the last sync: their records go.
const unpinned = new Set();

function takeUnpinned(state) {
  for (const tabId of unpinned) {
    const name = Object.keys(state.pinnedMap).find((n) => state.pinnedMap[n].tabId === tabId);
    if (!name) continue;
    delete state.pinnedMap[name];
    queuePinned(state, 'delete', name);
  }
  unpinned.clear();
}

async function pushPinned(state) {
  const space = state.paired.space;
  const ops = state.pinnedOps;
  if (!ops.save.length && !ops.delete.length) return;
  const next = structuredClone(state.mirror);
  const ours = Object.values(next.pinned).filter((p) => p.space === space);
  let last = Math.max(0, ...ours.map((p) => p.position));
  for (const name of ops.save) {
    const entry = state.pinnedMap[name];
    if (!entry) continue;
    let title = '';
    try { title = (await chrome.tabs.get(entry.tabId)).title || ''; } catch (_) {}
    if (!next.pinned[name]) last += 1;
    next.pinned[name] = { id: name, space, position: next.pinned[name]?.position ?? last, title, url: entry.url };
  }
  for (const name of ops.delete) delete next.pinned[name];
  await send(state, next, changes(state.mirror, next, ['pinned']));
  state.pinnedOps = { save: [], delete: [] };
}

// MARK: Open tabs

async function groupTitles() {
  const titles = new Map();
  try {
    for (const group of await chrome.tabGroups.query({})) titles.set(group.id, group.title || '');
  } catch (_) {}
  return titles;
}

async function pushOpenTabs(state) {
  const space = state.paired.space;
  const groups = await groupTitles();
  const tabs = (await allTabs()).filter((t) => t.url && isShareable(t.url)).map((t) => {
    const tab = { u: t.url, t: t.title || '' };
    if (t.pinned) tab.p = true;
    const group = groups.get(t.groupId);
    if (group) tab.g = group;
    return tab;
  });
  const name = deviceTabsName(state.installId, space);
  const known = state.mirror.deviceTabs[name];
  const fresh = known && JSON.stringify(known.tabs) === JSON.stringify(tabs) && known.deviceName === state.deviceName
    && Date.now() - known.updated < DAY;
  if (fresh) return;
  const next = structuredClone(state.mirror);
  next.deviceTabs[name] = {
    id: name, device: state.installId, deviceName: state.deviceName, browser: browserName(), space, updated: Date.now(), tabs,
  };
  await send(state, next, { save: [name], delete: [] });
}

// MARK: To iCloud

async function push(state) {
  if (!state.paired) return;
  const space = state.paired.space;
  // A space made here goes first.
  if (state.mirror.spaces[space] && state.pendingSpace) {
    await send(state, state.mirror, { save: [space], delete: [] }, true);
    state.pendingSpace = false;
  }
  if (await isWriter(state)) await pushBookmarks(state);
  takeUnpinned(state);
  await rebindPinned(state);
  await pushPinned(state);
  await pushOpenTabs(state);
}

// Saves and deletions; the mirror becomes `next` once iCloud has them.
async function send(state, next, diff, force = false) {
  if (!diff.save.length && !diff.delete.length && !force) return;
  const saves = diff.save.map((name) => toRecord(next, name)).filter(Boolean);
  const failed = await ck.modify(saves, diff.delete);
  if (failed.length) throw new Error(`iCloud didn't take ${failed.length} change(s): ${failed[0].serverErrorCode}`);
  state.mirror = next;
}

// MARK: Pairing

async function pair({ space, name }) {
  await exclusive(() => pairing({ space, name }));
  return sync('paired');
}

async function pairing({ space, name }) {
  const state = await load();
  await ck.ensureZone();
  state.paired = null;
  state.syncToken = null;
  state.mirror = emptyMirror();
  await pull(state);
  let target = space;
  if (!target) {
    target = newName();
    state.mirror.spaces[target] = { id: target, name: name || browserName(), symbol: 'globe', color: 'blue' };
    state.pendingSpace = true;
  }
  if (!state.mirror.spaces[target]) throw new Error('That space is no longer in iCloud.');
  state.paired = { space: target };
  state.bookmarkMap = {};
  state.pinnedMap = {};
  state.pinnedOps = { save: [], delete: [] };
  // The first computer to pair this profile with this space writes its bookmarks.
  const { safienceWriter } = await chrome.storage.sync.get('safienceWriter');
  if (!safienceWriter || safienceWriter.space !== target) {
    await chrome.storage.sync.set({ safienceWriter: { install: state.installId, space: target } });
  }
  if (state.pendingSpace) {
    await send(state, state.mirror, { save: [target], delete: [] }, true);
    state.pendingSpace = false;
  }
  if (await isWriter(state)) await joinBookmarks(state);
  await applyPinned(state, state.mirror);
  await store(state);
}

// Chrome's bookmarks matched to the space's: the same address in the same
// folder is one bookmark; iCloud's come into Chrome, Chrome's go to iCloud
// with the next push, and nothing is deleted on either side. On pairing,
// and when this computer becomes the one that writes them: without it,
// every bookmark would go to iCloud as new and iCloud's as deleted.
async function joinBookmarks(state) {
  const { bar, other } = await chromeRoots();
  const nodes = chromeNodes(bar.children);
  if (other && (other.children || []).length) {
    nodes.push({ chromeId: other.id, title: OTHER_TITLE, url: null, children: chromeNodes(other.children) });
  }
  state.bookmarkMap = {};
  joinTrees(nodes, tree(state.paired.space, state.mirror), state.bookmarkMap);
  await applyBookmarks(state);
}

function unpair() {
  return exclusive(unpairing);
}

async function unpairing() {
  const state = await load();
  if (state.paired) {
    const name = deviceTabsName(state.installId, state.paired.space);
    try { await ck.modify([], [name]); } catch (_) {}
    remove(state.mirror, name);
  }
  state.paired = null;
  state.bookmarkMap = {};
  state.pinnedMap = {};
  state.pinnedOps = { save: [], delete: [] };
  await store(state);
}

// MARK: What the popup asks

function status() {
  return exclusive(reading);
}

async function reading() {
  const state = await load();
  const writer = await isWriter(state);
  const now = Date.now();
  const spaces = Object.values(state.mirror.spaces).sort((a, b) => a.name.localeCompare(b.name));
  const elsewhere = state.paired
    ? Object.values(state.mirror.deviceTabs)
      .filter((d) => d.space === state.paired.space && d.device !== state.installId && now - d.updated < STALE && d.tabs.length)
      .sort((a, b) => b.updated - a.updated)
    : [];
  return {
    configured: !!config.apiToken,
    signedIn: state.signedIn && !!(await ck.token()),
    paired: state.paired,
    spaceName: state.paired ? state.mirror.spaces[state.paired.space]?.name || '' : '',
    spaceColor: state.paired ? state.mirror.spaces[state.paired.space]?.color || '' : '',
    spaces,
    writer,
    deviceName: state.deviceName,
    browser: browserName(),
    lastSync: state.lastSync,
    error: state.error,
    elsewhere,
    redirect: chrome.identity.getRedirectURL(),
  };
}

const handlers = {
  status: () => status(),
  signIn: async () => {
    await ck.signIn();
    await exclusive(async () => {
      const state = await load();
      state.signedIn = true;
      state.error = '';
      await store(state);
    });
    await ck.ensureZone();
    await sync('signed in');
    return status();
  },
  signOut: async () => {
    await unpair();
    await ck.signOut();
    await exclusive(async () => {
      const state = await load();
      state.signedIn = false;
      state.mirror = emptyMirror();
      state.syncToken = null;
      await store(state);
    });
    return status();
  },
  pair: async (message) => { await pair(message); return status(); },
  unpair: async () => { await unpair(); return status(); },
  syncNow: async () => { await sync('popup'); return status(); },
  becomeWriter: async () => {
    await exclusive(async () => {
      const state = await load();
      if (!state.paired) return;
      await chrome.storage.sync.set({ safienceWriter: { install: state.installId, space: state.paired.space } });
      await pull(state);
      await joinBookmarks(state);
      await store(state);
    });
    await sync('writer');
    return status();
  },
  rename: async ({ deviceName }) => {
    await exclusive(async () => {
      const state = await load();
      state.deviceName = (deviceName || '').trim() || defaultDeviceName();
      await store(state);
    });
    await sync('renamed');
    return status();
  },
  open: async ({ url }) => {
    if (/^https?:/.test(url)) await chrome.tabs.create({ url });
    return null;
  },
};

chrome.runtime.onMessage.addListener((message, _sender, reply) => {
  const handler = handlers[message?.type];
  if (!handler) return false;
  handler(message).then((value) => reply({ ok: true, value }), (error) => reply({ ok: false, error: String(error.message || error) }));
  return true;
});

// MARK: When to sync

let soon = null;
function syncSoon(reason, delay = 2000) {
  clearTimeout(soon);
  soon = setTimeout(() => sync(reason), delay);
}

chrome.runtime.onInstalled.addListener(() => {
  // This computer's id, kept from now on.
  exclusive(async () => store(await load()));
  chrome.alarms.create('sync', { periodInMinutes: 5 });
  syncSoon('installed', 500);
});
chrome.runtime.onStartup.addListener(() => {
  chrome.storage.session.set({ startedAt: Date.now() });
  chrome.alarms.create('sync', { periodInMinutes: 5 });
  syncSoon('startup', 3000);
});
chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === 'sync') sync('alarm');
});

const bookmarkChanged = () => {
  if (applying || Date.now() < quietUntil) return;
  syncSoon('bookmarks');
};
for (const event of [chrome.bookmarks.onCreated, chrome.bookmarks.onRemoved, chrome.bookmarks.onChanged,
  chrome.bookmarks.onMoved, chrome.bookmarks.onChildrenReordered, chrome.bookmarks.onImportEnded]) {
  event.addListener(bookmarkChanged);
}

// A tab pinned here is found by the next sync (rebindPinned), which first
// looks for a record at its address, so a pinned tab this extension opened
// isn't sent back as new. Unpinned and closed ones are noted here: a tab
// closed with its window (Chrome quitting) is not unpinned.
chrome.tabs.onUpdated.addListener((tabId, info) => {
  if ('pinned' in info) {
    if (!info.pinned) unpinned.add(tabId);
    syncSoon('pinned');
  }
  if (info.status === 'complete' || 'title' in info) syncSoon('tabs', 5000);
});
chrome.tabs.onCreated.addListener(() => syncSoon('tabs', 5000));
chrome.tabs.onRemoved.addListener((tabId, info) => {
  if (!info.isWindowClosing) unpinned.add(tabId);
  syncSoon('tabs', 5000);
});
for (const event of [chrome.tabs.onMoved, chrome.tabs.onAttached, chrome.tabs.onDetached]) {
  event.addListener(() => syncSoon('tabs', 5000));
}
