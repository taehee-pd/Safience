# Safience Sync, for Chrome

A Chrome extension that pairs a Chrome profile with a space in Safience, through the user's own iCloud: no server in between.

| What | How |
| --- | --- |
| Bookmarks | Both ways. The bookmarks bar is the space's top level; Other Bookmarks is a folder of that name in it |
| Pinned tabs | Both ways. One pinned in Chrome is pinned in Safience; one pinned in Safience opens pinned in Chrome. Nothing is ever closed: a pinned tab removed elsewhere is unpinned here if it is still on its page |
| Open tabs | Shown, never opened by themselves: Chrome's in Safience's tab overview and palette, Safience's in this popup |
| Never | Cookies, history, passwords, page contents. The extension has no access to pages at all |

It runs in Chrome, Edge, Brave, Vivaldi, Opera and other Chromium browsers. Chrome runs one copy per profile, and each pairs with a space of its own.

## How it works

The app and the extension read and write the same records in the user's private CloudKit database, container `iCloud.net.taehee.safience`, zone `Sync`:

| Record | Fields |
| --- | --- |
| `Space` | name, symbol, color |
| `BookmarkNode` | space, parent, position (double), title, url |
| `PinnedTab` | space, position (double), title, url |
| `DeviceTabs` | device, deviceName, browser, space, updated (timestamp), tabs (JSON: `u`, `t`, `p`, `g`) |

The app uses `CKSyncEngine` (`App/Sources/Sync.swift`); the extension uses CloudKit Web Services over `fetch` (`src/cloudkit.js`). The rules between records and a tree of bookmarks are the same on both sides: `PadCore/Sources/PadCore/SyncModel.swift` and `src/model.js`, with the same tests.

- **Sign-in.** Apple's own sign-in page, opened with `chrome.identity.launchWebAuthFlow`, returns a web token to `https://bdoihlcgbkkiiignggagkcbilfkjmhdo.chromiumapp.org/`, which Chrome hands to the extension. The token changes with every request (the next one comes in the `X-Apple-CloudKit-Web-Auth-Token` header) and lasts two weeks with "Keep me signed in".
- **The extension's id** is fixed by the `key` in `manifest.json`, so the callback address above stays the same wherever the folder is loaded from. The Chrome Web Store gives a published extension an id of its own; its callback address then goes in a second API token.
- **One writer of bookmarks per profile.** Chrome Sync carries a profile's bookmarks between its computers. If each computer also sent them to iCloud, every change would arrive twice, so the first computer to pair writes bookmarks, and the others leave them to Chrome Sync. The popup can move the writing to another computer.
- **Pairing joins** Chrome's bookmarks with the space's: the same address in the same folder is one bookmark, a folder matches one of the same name, and nothing is deleted on either side.

## Setting it up

1. **CloudKit's record types.** The first records saved in the container's Development environment make them: turn on Settings › iCloud in a debug build of Safience (run from Xcode), or pair this extension with `environment: 'development'` in `config.js`.
2. **Production, for TestFlight and the App Store.** In [CloudKit Console](https://icloud.developer.apple.com), open the container › Schema › Deploy Schema Changes. Until then, TestFlight builds can't save.
3. **An API token.** CloudKit Console › the container › API Access › API Tokens › add one:
   - Sign In Callback: **URL**, `https://bdoihlcgbkkiiignggagkcbilfkjmhdo.chromiumapp.org/`
   - Allowed Origins: any domain
   Put it in `config.js` as `apiToken`, with `environment` matching the app build you use (`development` for a debug build, `production` for TestFlight).
4. **Load it.** `chrome://extensions` › Developer mode › Load unpacked › this `Extension` folder.
5. **Pair.** The extension's button › Sign in with Apple Account › choose a space, or make one.

## Tests

```bash
node --test Extension/tests/model.test.mjs
```
