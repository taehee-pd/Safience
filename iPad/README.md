# Safience for iPad

A WebKit browser for iPad, made for Figma and web apps used with a trackpad and keyboard. iPad's own trackpad and keyboard behaviour (page zoom, scrolling, swipe back, callouts, the menu bar's ⌘ shortcuts) is turned off or handed to the page, so a web app gets what it would get from Safari on a Mac.

It lives beside the Mac app and shares its address parsing (`Sources/Search/Address.swift`, `Engine.swift`, `Registrable.swift`, linked into `PadCore/Sources/PadCore/Shared/`). Nothing in the Mac app changed.

## Build and run

Needs Xcode 16 or later and an iPad on iPadOS 17 or later (iPadOS 26 recommended, for its menu bar).

1. Put your team ID in `Config/Signing.xcconfig` (`DEVELOPMENT_TEAM = ABCDE12345`), and change `PRODUCT_BUNDLE_IDENTIFIER` there if it is taken.
2. Open `Safience.xcodeproj`, choose your iPad, press Run.

`project.yml` generates the project with [XcodeGen](https://github.com/yonaskolb/XcodeGen). After adding or removing a file, run `xcodegen` in this folder. The generated project is committed, so building needs only Xcode.

## Layout

| Path | What |
|---|---|
| `App/Sources/` | The app: UIKit for windows and gestures, SwiftUI for bars, palette and settings |
| `PadCore/` | Plain logic, no UIKit or WebKit: adapters, sign-in detection, the freezer, the workspace model. Builds and tests on any machine with Swift |
| `PadCore/Sources/PadCore/Scripts/bridge.js` | The script that goes into pages |
| `Tests/` | Browser tests for `bridge.js` |
| `Validation/` | What to check on a real iPad, and the Figma console test |

## Where each requirement lives

| Requirement | How | Where |
|---|---|---|
| Desktop mode | `preferredContentMode = .desktop`, in the configuration and again for every navigation | `Page.configuration`, `decidePolicyFor` |
| Mac Safari user agent | `applicationNameForUserAgent = "Version/<iPadOS version> Safari/605.1.15"` | `Identity.swift` |
| WebKit's own hover, click, move | Left to WebKit; the app's recognizers never cancel or delay touches | `Pointer.swift` |
| Native scrolling and zoom off | `isScrollEnabled = false`, the scroll view's pinch off, zoom held at 1 | `Page.setUp`, `ZoomHold` |
| Pinch bridge | `UIPinchGestureRecognizer` on `.indirectPointer` only, sent as `WheelEvent` with `ctrlKey` at the cursor, `deltaY = -100 × ln(step)` (Chrome's) | `Pointer.pinched`, `Pinch.wheelDelta`, `bridge.js wheel()` |
| Cursor tracking | `UIHoverGestureRecognizer` | `Pointer.hovered` |
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
| Passkeys | Out of scope: no `com.apple.developer.web-browser` entitlement | |
| Cookie store per space | `WKWebsiteDataStore(forIdentifier: space.id)`; removing a space erases its store | `Stores.swift` |
| Site adapters | CSS, our-world JS, page-world JS, user agent, bridges, heavy pages. Figma first | `Adapters.swift` |
| Command palette | ⌃⌥K: tabs of every space, spaces, commands, typed addresses and searches | `CommandPalette.swift`, `PaletteSearch.swift` |
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
cd iPad/PadCore && swift test        # PadCore, 71 tests; runs on macOS or Linux
node iPad/Tests/bridge.mjs           # bridge.js in Chromium (needs Playwright)
node iPad/Tests/bridge.mjs webkit    # the same in Playwright's WebKit
```

`Tests/bridge.html` also runs on its own in Safari: `cd iPad && python3 -m http.server 8642`, then open `http://localhost:8642/Tests/bridge.html`.

What only a real iPad can show (the trackpad, the keyboard, memory) is in [Validation/CHECKLIST.md](Validation/CHECKLIST.md), with the Diagnostics panel (⌃⌥D) to read along.

## Known limitations

- iPadOS keeps its own shortcuts (⌘Tab, ⌘Space, ⌘H, the Globe key) and its three- and four-finger gestures. No app can hand those to a page.
- Passkeys need the default-browser entitlement Apple grants to browsers it approves. Without it, sign in with a password, an email link, or single sign-on.
- A synthetic event is marked `isTrusted: false`. A page that ignores untrusted wheel or key events can't be reached by the bridges; Validation's first check is that Figma isn't one.
- A frame from another site can't be reached by the wheel bridge; its events go to the frame's element in the page around it.
- The Mac app's extensions, ad blocker, passwords, bookmarks, history, reader mode, floating video and AI are not part of the iPad app.
