# Changelog

What changes in Safience from one version to the next, newest first. A change that fixes or adds something adds its line under **Unreleased** the day it is merged.

## Unreleased

### Added

- iPhone, and the iPhone Duo folded and unfolded. A phone-width window has its bars at the bottom (back and forward, the address, the tabs, the space, a new tab, the page's menu) and its tabs as a grid; the bar rides above the keyboard while an address is typed. Phone-width windows get mobile sites, with Safari's iPhone user agent, touch scrolling and pinch zoom; windows at least 600 by 500 points get desktop sites. Request Desktop or Mobile Site (⌃⌥⇧M, or the page's menu) changes it for a site and remembers.
- Spaces and their bookmarks in iCloud, off until Settings › iCloud turns it on: each space's name, colour, icon and bookmarks show on every iPhone and iPad signed in to the same account; tabs, sign-ins and site data stay on each device. Turning it on joins spaces with the same name and keeps both sets of bookmarks.
- Signed with Apple's browser entitlement, which Apple granted: iPadOS offers Safience as the default browser, pages can use passkeys and service workers, and Share Page (⌃⌥S, or the tab's menu) puts Add to Home Screen in the share sheet. Settings says whether Safience is the default browser and opens Default Apps to make it so. A team without the entitlement turns it off in `Config/Local.xcconfig`.
- A new app icon, made with Icon Composer: a ring in Liquid Glass on a blue gradient on iOS and iPadOS 26 and later, with its dark and tinted looks, and a flat picture Xcode draws from it for earlier versions.
- A compact layout, the new default, as Safari's: one row with the space, back and forward, the tabs sharing the row at one width, new tab and the palette. The tab on screen shows where it is (or its title: Settings › The tab you are on shows; sign-in pages always show where); clicking a tab only goes to it, and clicking the one on screen turns it into the address field the way Safari's does: its words give way to the address, selected, in place, then the field widens over the other tabs, which stay where they are underneath, and Return, Escape or a click on the page takes it back into the tab along the same path. A pinned tab on screen stays an icon, so going to it moves nothing, unless it is on a sign-in page. Settings › Window › Tabs keeps the separate address bar instead.
- Split view, as in Dia: two tabs side by side in one window, shown as one tab in the row: the halves meet with squared ends on a shared ground, a see-through dark that takes on the bar's colour. A click in a pane gives it the keys and the bars, with a line in the space's colour along its top; drag the divider for more room on one side, or double-tap it for the middle. A tab's menu has Open in Split View, Separate Tabs and Swap Sides; the + button's menu, New Tab in Split View; ⌃⌥\\ splits the tab on screen with a new tab or separates it. Both pages stay live, closing one leaves the other, and a window narrower than two readable pages shows only the pane with the keys.
- Pinned tabs, as in Dia and Arc: icons at the front of the row, each space its own. Closing one unloads it and takes it back to its pinned address; Back to Pinned Page and Unpin are in its menu; ⌃⌥⇧P pins or unpins the tab on screen.
- Bookmarks, each space its own: a new tab shows them as a grid of site icons, folders and all; the star in the address (⌃⌥⇧D) adds or takes away the page; the palette finds them. Import from Chrome, Firefox or Safari (Bookmarks.html, or the ZIP of Safari's Export Browsing Data) in Settings, on the empty grid, or with ⌃⌥⇧I.
- Sites' icons on tabs, pinned tabs and bookmarks: the icon a page names, fetched once per site without cookies, and the ones a Chrome bookmarks file carries; a site without one shows its first letter.
- Space colours: a space's colour fills its button. Space Settings (⌃⌥⇧S, or the space's menu) sets the name, the colour and the icon from a grid; Settings › Spaces reorders the spaces.
- Pages' own cursors show on iPad, which WebKit never shows there: Figma's arrow, its tools' cursors, the rotated arrows on a selection. The page script draws the cursor under the pointer to a picture; the app hides the system pointer and draws it at the pointer, through clicks and drags. Settings › Show pages' own cursors turns it off; Diagnostics' last line says which cursor shows.
- `App/PrivacyInfo.xcprivacy`, the privacy manifest App Store Connect requires: no tracking, no data collected, and `UserDefaults` used only for the app's own settings.
- The command palette is see-through and blurred over the page it opens on, like Raycast, and dims the page only lightly. Under Reduce Transparency it is solid.
- The tab bar and the address bar take on the colour along the top of the page, as in Safari, so bars and page read as one; what they draw, and the status bar, turn light on a dark colour and dark on a light one.
- On iPadOS 26 and later, the space menu, the tabs, the new tab and palette buttons, back, forward and reload, and the address are in Liquid Glass. The tab you are on is in regular glass, the others in clear glass.
- Safience, a WebKit browser for iPad, made for Figma and web apps used with a trackpad and keyboard. Pages are asked for in desktop mode as Mac Safari. A trackpad pinch and ⌘ with two fingers reach the page as ctrl+wheel at the pointer, as on a Mac, and two-finger scrolling is bridged when WebKit sends the page nothing; iPad's own page zoom, scrolling, swipe back and callouts are off. The system's ⌘ menus are gone, so ⌘Z, ⌘F and the rest are the page's; the browser's own shortcuts are all ⌃⌥, with a command palette on ⌃⌥K. Each space signs in with a WebKit store of its own; windows work with Stage Manager; one heavy tab stays live and other tabs freeze to a picture, loading again when opened, and a page whose process ends reloads by itself. Sign-in pages always show the address, and Google's sign-in is never touched: no script, no cookie read.

### Changed

- Only the tab on screen is in Liquid Glass; every other tab is flat, with a faint see-through shade under the pointer that takes on the bar's colour.
- Tapping or clicking the address selects all of it, so typing replaces it, as in Safari.
- Bars are 44 points tall, so every control answers in at least 40 by 40, and presses give a little (to 0.96).
- A link opened from another app opens in a new tab after the one on screen, instead of replacing that tab's page.
- The address bar shows on every page, so the address and the way back stay in view. Settings › Show the address bar can keep it to sign-in pages, as before.

### Fixed

- Typing an address on an iPhone stopped at once: select all, sent to whatever had the keys, reached the page, which took them back. The field now selects its own text.
- The palette and the address field left out the last letter typed until the next key: the palette offered "Open github.co" for github.com, and Return opened github.co. The Korean keyboard keeps the last letter as text still being composed, which SwiftUI's text field doesn't pass on; both fields now read what they show, and Return commits the composition first.
- The not-secure warning flashed in the address of an https page while it loaded, before WebKit knew the page was secure. It now shows at once for an http address, and for anything else once the page has loaded.
- The tab bar and the address bar went blank whenever the keyboard was up, sign-in pages included, where the address must always show. SwiftUI moved what they draw out of sight to make room for the keyboard; they no longer make room for it.
- A trackpad pinch zoomed Figma only 1.41 times for a pinch to twice the size. Figma, told it is in Safari, zooms half as far per wheel event as Chrome's pinch asks, so its adapter now sends twice the delta, and the canvas follows the fingers.
- The Figma console test (`Validation/figma-ctrl-wheel.js`) printed FAIL on real Figma, which zooms in Safari half as far as Chrome's pinch asks. It now passes when Figma zooms at all, and prints how far (`strength`) and the pinch factor Figma's adapter needs for the zoom to follow the pinch.

### Removed

- The Mac app this repository began as, Search by Office Commun: its sources, build and release scripts, tests, AI engine, installer, roadmap and release notes. It stays in the git history.
