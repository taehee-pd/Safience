# Safience

A WebKit browser for iPad, made for Figma and web apps used with a trackpad and keyboard. iPad's own trackpad and keyboard behaviour (page zoom, scrolling, swipe back, callouts, the menu bar's ⌘ shortcuts) is turned off or handed to the page, so a web app gets what it would get from Safari on a Mac.

## What it does

- **The page gets the trackpad.** A pinch zooms Figma's canvas around the pointer, not the whole page. ⌘ with two fingers zooms too, and two fingers pan, gliding on after a flick as on a Mac.
- **The page gets the keys.** ⌘Z, ⌘F, ⌘D and every other ⌘ shortcut belong to the page: the system menus that would take them are gone. The browser's own shortcuts are all ⌃⌥, which pages leave alone.
- **Safari on a Mac, to every site.** Desktop pages and Mac Safari's user agent, so web apps serve their full desktop version.
- **Spaces, each signed in on its own.** A space has its own tabs, its own cookies and its own bookmarks, and a colour and an icon that fill its button, so you can see which space a window is in: a client's Figma and your own, both signed in. Reorder them in Settings › Spaces.
- **One row, as Safari's compact layout.** The tab you are on shows where it is; click it and it becomes the address field, growing over the other tabs the way Safari's does, and shrinking back into the tab after. The other tabs sit beside it, flat, with only the one on screen in Liquid Glass. The bars take on the colour along the top of the page. Settings can put the address bar under the tabs instead.
- **Pinned tabs, as in Dia and Arc.** A pinned tab is an icon at the front of the row that keeps its page: closing it unloads it and takes it back to the address it was pinned with.
- **A new tab shows your bookmarks** as a grid of site icons, folders and all, imported from Chrome, Firefox or Safari (its export ZIP included).
- **Pages' own cursors.** Figma's arrow and its tools' cursors show, which WebKit on iPad never shows.
- **A command palette.** ⌃⌥K finds any tab in any space, any space, any command, or opens what you type.
- **Windows for Stage Manager.** Each window shows a space and a tab, and comes back as it was.
- **Memory spent on what you use.** One heavy tab (a Figma file) stays open while you look elsewhere; other tabs freeze to a picture and load again when opened. A page that runs out of memory reloads by itself.
- **Sign-in pages show their address**, always, so you can see which site asks for your password. Google's sign-in is never touched: no script, no cookie read.

## Build and run

Needs Xcode 16 or later and an iPad on iPadOS 17 or later (iPadOS 26 recommended, for its menu bar).

1. Create `Config/Local.xcconfig` with your team ID: `DEVELOPMENT_TEAM = ABCDE12345` (Xcode > Settings > Accounts shows it). If the bundle identifier `net.taehee.safience` is taken, set `PRODUCT_BUNDLE_IDENTIFIER` there too. Git ignores the file.
2. Open `Safience.xcodeproj`, choose your iPad, press Run.

`project.yml` generates the project with [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`). After adding or removing a file, run `xcodegen` at the root and commit the regenerated project, so building needs only Xcode.

## With Apple's browser entitlement

Apple's `com.apple.developer.web-browser` entitlement lets iPadOS offer Safience as the default browser, and lets WebKit use passkeys on any site. It is likely also what makes the Passwords app suggest a site's passwords (not stated by Apple). Apple grants it to a paid developer team on request:

1. Join the Apple Developer Program. Only the team's Account Holder can make the request.
2. Put a build on TestFlight, so Apple can try it: an app record in App Store Connect for the bundle identifier, then an archive uploaded from Xcode. `App/PrivacyInfo.xcprivacy` declares what App Store Connect asks for.
3. Request it with Apple's [default browser entitlement form](https://developer.apple.com/contact/request/default-browser-entitlement/), which asks for the team's ID and name, the bundle identifier and the TestFlight link. Safience meets the criteria listed in [Preparing your app to be the default web browser](https://developer.apple.com/documentation/xcode/preparing-your-app-to-be-the-default-browser): `http` and `https` in `Info.plist`, no `UIWebView` (only `WKWebView`), an address bar on launch, links opened as asked (each in a new tab), and none of the `Info.plist` keys browsers may not use.
4. Once granted, turn the entitlement on for the app's identifier in Certificates, Identifiers & Profiles, if Apple hasn't already.
5. In `Config/Local.xcconfig`, put the new team's ID in `DEVELOPMENT_TEAM` and add `CODE_SIGN_ENTITLEMENTS = Config/Browser.entitlements`. If the bundle identifier is taken (a free team that used it may still hold it), set another in `PRODUCT_BUNDLE_IDENTIFIER` there.
6. Build and run, then check [Validation/CHECKLIST.md](Validation/CHECKLIST.md) section 6.

Before then, leave that line out: signing with an entitlement the team doesn't have fails.

## Privacy

| What | Where | Who can read it |
|---|---|---|
| Spaces, tabs and each space's bookmarks | `workspace.json` in the app's Application Support folder | You |
| Sites' icons | The app's Caches folder, one per site: the icon a page names, fetched by the app without cookies, or carried in a Chrome bookmarks file | You. iPadOS may clear it |
| Pictures of frozen tabs, and what it takes to reopen them | The app's Caches folder; never for a sign-in page | You. iPadOS may clear it |
| Cookies, sign-ins, site data | One WebKit store per space | The sites that set them |
| Settings | The app's preferences | You |
| Anything else | Nowhere. There is no server, no analytics, no telemetry | |

## Layout

| Path | What |
|---|---|
| `App/Sources/` | The app: UIKit for windows and gestures, SwiftUI for bars, palette and settings |
| `PadCore/` | Plain logic, no UIKit or WebKit: adapters, sign-in detection, the freezer, the workspace model, address parsing. Builds and tests on any machine with Swift |
| `PadCore/Sources/PadCore/Scripts/bridge.js` | The script that goes into pages |
| `Tests/` | Browser tests for `bridge.js` |
| `Validation/` | What to check on a real iPad, and the Figma console test |
| `project.yml`, `Config/` | The Xcode project's source, and signing |

## Where each requirement lives

| Requirement | How | Where |
|---|---|---|
| Desktop mode | `preferredContentMode = .desktop`, in the configuration and again for every navigation | `Page.configuration`, `decidePolicyFor` |
| Mac Safari user agent | `applicationNameForUserAgent = "Version/<iPadOS version> Safari/605.1.15"` | `Identity.swift` |
| WebKit's own hover, click, move | Left to WebKit; the app's recognizers never cancel or delay touches | `Pointer.swift` |
| Native scrolling and zoom off | `isScrollEnabled = false`, the scroll view's pinch off, zoom held at 1 | `Page.setUp`, `ZoomHold` |
| Pinch bridge | `UIPinchGestureRecognizer` on `.indirectPointer` only, sent as `WheelEvent` with `ctrlKey` at the cursor, `deltaY = -100 × ln(step)` (Chrome's), or `-200 × ln(step)` on Figma, which zooms half as far per event | `Pointer.pinched`, `Pinch.wheelDelta`, `Adapters.figma`, `bridge.js wheel()` |
| Cursor tracking | `UIHoverGestureRecognizer` | `Pointer.hovered` |
| The page's own cursors | WebKit on iPad shows the system pointer for every cursor but the text beam. `bridge.js` reads the cursor under the pointer and draws its image (an SVG, an image set, a PNG) to a PNG; the app turns WebKit's pointer interactions off, hides the pointer with its own, and draws the picture at the pointer, through clicks and drags | `bridge.js parseCursor()`, `PageCursor`, `Pointer.show` |
| ⌘ + scroll zoom | `modifierFlags.contains(.command)` on the scroll pan | `Pointer.scrolled` |
| Wheel bridge (optional) | Two-finger pan as `WheelEvent`, with momentum. In `auto` mode `bridge.js` stands aside while WebKit's own wheel events arrive | `Pointer.scrolled`, `bridge.js` |
| No callouts or previews | `allowsLinkPreview = false`, `-webkit-touch-callout: none`, no system context menu | `Page.setUp`, `base.css`, `contextMenuConfigurationForElement` |
| No swipe back | `allowsBackForwardNavigationGestures = false` | `Page.setUp` |
| Default menus removed | Every top-level menu but the app menu removed, the app menu emptied, in `buildMenu(with:)`. Covers iPadOS 26's menu bar, whatever menus it adds | `Menus.swift` |
| ⌘F for the page | `isFindInteractionEnabled = false` | `Page.setUp` |
| Tab and arrows | Registered with `wantsPriorityOverSystemBehavior` when Settings or a site's adapter says so, and handed to the page as keydown and keyup | `PageView.keyCommands`, `bridge.js key()` |
| Focus back to the page | On `sceneDidBecomeActive` and `UIWindow.didBecomeKeyNotification`, and after the palette, the address bar or a sheet | `SceneDelegate`, `Browser.focusPage` |
| Browser shortcuts on rare keys | Every one is ⌃⌥ (below) | `Shortcuts` in `Commands.swift` |
| Address bar on sign-in pages | Shown on sign-in hosts, sign-in paths, OAuth requests and pages with a password field, whatever Settings says | `SignIn.swift`, `AddressVisibility` |
| Hands off accounts.google.com | No user script in any world, no JavaScript call, no cookie read. Checked before every call; a test reads the source to keep it so | `HandsOff.swift`, `Page.call`, `PolicyTests` |
| Email and SSO as fallback | Pop-up sign-ins open as a sheet; HTTP authentication is answered; Google's refusal page gets a banner pointing to email or SSO | `Popup.swift`, `Dialogs.credentials`, `SignIn.googleRefused` |
| Passkeys | WebKit's own, once Apple grants the `com.apple.developer.web-browser` entitlement; ready to switch on (With Apple's browser entitlement, above) | `Config/Browser.entitlements` |
| Cookie store per space | `WKWebsiteDataStore(forIdentifier: space.id)`; removing a space erases its store | `Stores.swift` |
| Site adapters | CSS, our-world JS, page-world JS, user agent, bridges, heavy pages. Figma first | `Adapters.swift` |
| Command palette | ⌃⌥K: tabs of every space, spaces, the space's bookmarks, commands, typed addresses and searches | `CommandPalette.swift`, `PaletteSearch.swift` |
| Compact tabs | The tab on screen says where it is (`CurrentTabFace`), the only tab in Liquid Glass; a click on it grows the address field out of it over the row and back (`TabStrip`); the row shows whenever an address must, the tab bar hidden or not | `Bars.swift`, `Browser.refreshChrome` |
| Pinned tabs | First in the row, as icons; `Workspace.closeTab` takes a pinned tab back to its pinned address instead of away | `Workspace.pin`, `PinnedChip` |
| Bookmarks | Each space's own, in `workspace.json`; a new tab shows them as tiles; Netscape bookmark files and Safari's export ZIP are read without a dependency | `Bookmarks.swift`, `ZipFile.swift`, `StartPage.swift` |
| Space colour, icon and order | Each space's colour fills its button; Settings › Spaces reorders them | `SpaceColor`, `Spaces.swift` |
| Multiple windows | `UIApplicationSupportsMultipleScenes`, one scene per window, each restored with its space and tab | `Info.plist`, `SceneDelegate`, `WindowState` |
| One heavy tab live, the rest frozen | Off-screen tabs freeze to a picture plus WebKit's interaction state and load again when opened. One heavy tab (a Figma file) stays live, two light ones by default, none under memory pressure | `Memory.swift` (Freezer), `Pages.swift` |
| Reload after the process ends | `webViewWebContentProcessDidTerminate` reloads the tab on screen; after 3 endings in a minute it waits for a click | `Page.processEnded`, `CrashGuard` |
| Memory limit | Not raised: no entitlement reaches WebKit's content processes | |

Two places where the app does a little more than the list, because the list's rules would otherwise collide:

- **WebKit's scrolling stays on for hands-off pages and PDFs.** With scrolling off, pages scroll through the wheel bridge, and on accounts.google.com no script may run. Left off there, a long Google account chooser could not scroll.
- **Zoom is held at 1, or at WebKit's own fit when the window is narrower than the page's desktop layout** (portrait, small Stage Manager windows). Held at 1 there, the right side of the page would be cut off with no way to scroll to it.

## Shortcuts

Every shortcut of the browser's own is ⌃⌥, so ⌘, ⌥ and ⇧ stay the page's. They are listed in Settings and in the menu bar on iPadOS 26.

| | |
|---|---|
| ⌃⌥K command palette | ⌃⌥L address |
| ⌃⌥T new tab · ⌃⌥W close · ⌃⌥⇧T reopen | ⌃⌥← ⌃⌥→ previous, next tab · ⌃⌥1 to ⌃⌥9 a tab by place |
| ⌃⌥[ ⌃⌥] back, forward · ⌃⌥R reload · ⌃⌥. stop | ⌃⌥↑ ⌃⌥↓ previous, next space · ⌃⌥⇧N new space |
| ⌃⌥N new window · ⌃⌥⇧W close window | ⌃⌥B tab bar · ⌃⌥D diagnostics · ⌃⌥P keys back to the page · ⌃⌥, settings |

With VoiceOver on, ⌃⌥ is VoiceOver's key; use the palette.

## Tests

```
cd PadCore && swift test          # PadCore, 71 tests; runs on macOS or Linux
node Tests/bridge.mjs             # bridge.js in Chromium (needs Playwright)
node Tests/bridge.mjs webkit      # the same in Playwright's WebKit
```

`Tests/bridge.html` also runs on its own in Safari: `python3 -m http.server 8642` at the root, then open `http://localhost:8642/Tests/bridge.html`.

What only a real iPad can show (the trackpad, the keyboard, memory) is in [Validation/CHECKLIST.md](Validation/CHECKLIST.md), with the Diagnostics panel (⌃⌥D) to read along.

## Known limitations

- iPadOS keeps its own shortcuts (⌘Tab, ⌘Space, ⌘H, the Globe key) and its three- and four-finger gestures. No app can hand those to a page.
- Until Apple grants the browser entitlement (above): no passkeys, so sign in with a password, an email link or single sign-on; and the Passwords app suggests nothing for a site, though it names the site in its AutoFill sheet. Type the site's name in the sheet's search to pick a password, and copy a verification code from the Passwords app.
- A synthetic event is marked `isTrusted: false`. A page that ignores untrusted wheel or key events can't be reached by the bridges; Validation's first check is that Figma isn't one.
- A frame from another site can't be reached by the wheel bridge; its events go to the frame's element in the page around it.
- A page's own cursor is drawn by the app, so it can trail the pointer by a frame. Cursors given by name (`ew-resize`, `crosshair`, `grab`) show the iPad's pointer, and the text beam is the iPad's own. Settings › Show pages' own cursors turns them off.
- No extensions, ad blocker, password manager, history or reader mode.
- A bookmark of a site never opened in Safience shows the site's first letter until it is: its icon is fetched only from a page you open (Safari's export carries no icons, Chrome's does).

## Where it came from

Safience began as a fork of [Search](https://github.com/driceroland/Search), a WebKit browser for the Mac by Office Commun, released under the MIT license. The Mac app was removed when Safience became an iPad app and stays in this repository's git history; Safience keeps its address parsing (`Address.swift`, `Engine.swift`, `Registrable.swift`) and its quiet grey colours. "Search" and its icon are Office Commun's.

## Contributing and security

See [CONTRIBUTING.md](CONTRIBUTING.md). Found a security problem? Report it privately, as [SECURITY.md](SECURITY.md) says.

## License

MIT, see [LICENSE](LICENSE).
