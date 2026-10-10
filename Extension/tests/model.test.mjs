// The extension's sync rules, the same cases as PadCore's SyncModelTests:
//   node --test Extension/tests
import test from 'node:test';
import assert from 'node:assert/strict';
import {
  changes, emptyMirror, flatten, isShareable, joinTrees, positions, take, toRecord, tree, urlKey,
} from '../src/model.js';

const SPACE = 'S';

function workspaceTree() {
  return [
    { id: 'A', title: 'Figma', url: 'https://figma.com' },
    { id: 'F', title: 'Code', url: null, children: [{ id: 'G', title: 'GitHub', url: 'https://github.com' }] },
    { id: 'L', title: 'Linear', url: 'https://linear.app' },
  ];
}

function mirrorOf(list, previous = emptyMirror()) {
  const mirror = emptyMirror();
  mirror.bookmarks = flatten(list, SPACE, previous);
  return mirror;
}

test('bookmarks go to records and come back the same', () => {
  const mirror = mirrorOf(workspaceTree());
  assert.equal(Object.keys(mirror.bookmarks).length, 4);
  assert.deepEqual(tree(SPACE, mirror), workspaceTree());
  assert.equal(mirror.bookmarks.G.parent, 'F');
});

test('moving one bookmark rewrites one record', () => {
  const before = mirrorOf(workspaceTree());
  const list = workspaceTree();
  list.unshift(list.pop());
  const after = mirrorOf(list, before);
  assert.deepEqual(changes(before, after), { save: ['L'], delete: [] });
  assert.deepEqual(tree(SPACE, after), list);
});

test('removing a folder removes what is in it', () => {
  const before = mirrorOf(workspaceTree());
  const list = workspaceTree().filter((n) => n.id !== 'F');
  assert.deepEqual(changes(before, mirrorOf(list, before)).delete, ['F', 'G']);
});

test('positions keep the longest run in order and fit the rest between', () => {
  const previous = { a: 1, b: 2, c: 3, d: 4 };
  const places = positions(['d', 'a', 'b', 'c', 'x'], previous);
  assert.deepEqual(places.slice(1, 4), [1, 2, 3]);
  assert.ok(places[0] < 1 && places[4] > 3);
  assert.deepEqual(positions([], {}), []);
  assert.deepEqual(positions(['a', 'b'], { a: 1, b: 1 + 1e-12 }), [1, 2]);
});

test('a bookmark whose folder has not arrived waits at the top and stays in it', () => {
  const mirror = emptyMirror();
  mirror.bookmarks.G = { id: 'G', space: SPACE, parent: 'F', position: 1, title: 'GitHub', url: 'https://github.com' };
  const shown = tree(SPACE, mirror);
  assert.deepEqual(shown.map((n) => n.title), ['GitHub']);
  const again = mirrorOf(shown, mirror);
  assert.equal(again.bookmarks.G.parent, 'F');
  assert.deepEqual(changes(mirror, again).save, []);
});

test('two folders inside each other are broken at the top', () => {
  const mirror = emptyMirror();
  mirror.bookmarks.A = { id: 'A', space: SPACE, parent: 'B', position: 1, title: 'A', url: null };
  mirror.bookmarks.B = { id: 'B', space: SPACE, parent: 'A', position: 1, title: 'B', url: null };
  const shown = tree(SPACE, mirror);
  assert.equal(shown.length, 1);
  assert.equal(shown[0].children.length, 1);
});

test('records go out with their types and come back the same', () => {
  const mirror = mirrorOf(workspaceTree());
  const folder = toRecord(mirror, 'F');
  assert.equal(folder.recordType, 'BookmarkNode');
  assert.equal(folder.fields.url, undefined, 'a folder has no address');
  assert.equal(folder.fields.parent, undefined, 'and at the top, no parent');
  assert.deepEqual(folder.fields.position, { value: mirror.bookmarks.F.position, type: 'DOUBLE' });
  const back = emptyMirror();
  for (const name of Object.keys(mirror.bookmarks)) assert.ok(take(back, toRecord(mirror, name)));
  assert.deepEqual(back.bookmarks, mirror.bookmarks);
  mirror.deviceTabs['tabs.D.S'] = { id: 'tabs.D.S', device: 'D', deviceName: 'Mac', browser: 'Chrome', space: SPACE, updated: 1000, tabs: [{ u: 'https://a.com', t: 'A' }] };
  const tabs = toRecord(mirror, 'tabs.D.S');
  assert.deepEqual(tabs.fields.updated, { value: 1000, type: 'TIMESTAMP' });
  assert.ok(take(back, tabs));
  assert.deepEqual(back.deviceTabs['tabs.D.S'], mirror.deviceTabs['tabs.D.S']);
  assert.equal(take(back, { recordType: 'BookmarkNode', recordName: 'X', fields: {} }), false);
});

test('joining matches by address in the same folder and by folder title', () => {
  const cloud = workspaceTree();
  const chrome = [
    { chromeId: '10', title: 'Figma!', url: 'https://FIGMA.com/' },
    { chromeId: '11', title: 'Code', url: null, children: [
      { chromeId: '12', title: 'GitHub', url: 'https://github.com' },
      { chromeId: '13', title: 'Mine', url: 'https://example.com' },
    ] },
    { chromeId: '14', title: 'GitHub at the top', url: 'https://github.com' },
  ];
  const map = joinTrees(chrome, cloud);
  assert.equal(map['10'], 'A', 'the same address, whatever the case or the slash');
  assert.equal(map['11'], 'F');
  assert.equal(map['12'], 'G');
  assert.notEqual(map['13'], undefined);
  assert.ok(!['A', 'F', 'G', 'L'].includes(map['13']), 'a new one for a bookmark iCloud lacks');
  assert.ok(!['A', 'F', 'G', 'L'].includes(map['14']), 'the same address in another folder is another bookmark');
});

test('addresses: the same page, and what may be shared', () => {
  assert.equal(urlKey('https://Example.com/a/'), urlKey('https://example.com/a'));
  assert.ok(isShareable('https://figma.com/file/1'));
  assert.ok(!isShareable('https://accounts.google.com/signin'));
  assert.ok(!isShareable('https://app.example.com/callback?code=abc'));
  assert.ok(!isShareable('https://example.com/#access_token=abc'));
  assert.ok(!isShareable('chrome://settings'));
  assert.ok(!isShareable('https://example.com/oauth/authorize'));
});
