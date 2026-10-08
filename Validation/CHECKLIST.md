# Validating on a real iPad

What the tests in `Tests/` can't show: a real trackpad, a real keyboard, real sign-ins, real memory. Turn on the Diagnostics panel first (⌃⌥D, or Settings › Show diagnostics); most checks below read from it.

Last run: 2026-10-02, iPad Pro 13-inch (M5) on iPadOS 27.0, built with Xcode 27.0; Safari 27.0 on macOS 27.0. Results are under each section.

The panel's lines:

| Line | Reads |
|---|---|
| 1 | The site adapter, desktop or mobile pages, heavy or light |
| 2 | Page zoom, WebKit's scrolling, the scroll view's own pinch |
| 3 | Whether the page's `navigator.userAgent` is the Mac Safari string the app sends |
| 4 | Pinch steps, ⌘ zoom steps, wheel events bridged, and bridged events held back because WebKit sent its own |
| 5 | WebKit's own wheel events the page received, and the last bridged outcome |
| 6 | The wheel bridge mode, keys sent to the page, keys relayed, whether the focus is in a text field |
| 7 | Live and frozen tabs, and how many times this page's process ended |
| 8 | The cursor: the page's own picture (its size and hotspot), none, or the system's pointer |
| 9 | Ad blocking: on or off for this page, and the lists' rule count and dates |

## 1. Figma zooms on a synthetic ctrl+wheel (Mac Safari)

The pinch bridge rests on this, so check it first.

1. On a Mac, Safari › Settings › Advanced › Show features for web developers.
2. Open a Figma design file in Safari and click once on the canvas.
3. Develop › Show JavaScript Console, paste all of [figma-ctrl-wheel.js](figma-ctrl-wheel.js), press Return.

- [x] It prints `PASS: Figma zooms on a synthetic ctrl+wheel.` and the canvas zooms in, then back out.
- [ ] If it prints `LOOK:`, the zoom couldn't be read: the canvas should still zoom in and out.
- [x] Note `strength` and `pinchFactor`. Strength 1 means the zoom follows the pinch; `pinchFactor` is what Figma's adapter needs for it to (`Adapters.swift`).

Result: PASS. Figma took all 10 events and zoomed from 1.00 to 1.415: strength 0.50, pinchFactor 199. Measured one event at a time, Figma in Safari zooms by e^(−deltaY/200) for events up to 30, and less for bigger ones. The first version of the script asked for 1.5 and printed FAIL; it now passes at 1.1.

The same works inside the app: connect the iPad to the Mac, open the file in Safience, and pick its page under Safari's Develop › (your iPad). Every page in the app is inspectable.

## 2. Trackpad and keyboard in Figma

Open a design file in Safience, with a Magic Keyboard or a trackpad.

- [ ] Line 1 says Figma, desktop pages, heavy. Line 3 says Mac Safari.
- [ ] Hovering layers and frames highlights them; clicking selects; dragging moves.
- [ ] Pinching on the trackpad zooms the canvas around the pointer, not the whole page. Line 2 stays at zoom 1.00; line 4's pinch count goes up.
- [ ] ⌘ and two fingers zoom too.
- [ ] Two fingers pan the canvas. On line 5, if WebKit's own wheel events stay at 0, the bridge is doing the panning (line 4's bridged count goes up); if they go up, WebKit sends them itself and the bridge stands aside. Either way, note which.
- [ ] A quick two-finger flick keeps gliding for a moment, as on a Mac (only when the bridge does the panning).
- [ ] Figma's own cursors show, not the iPad's round pointer: its arrow on the canvas, and the frame, pen, comment and color picker tools' cursors, and the rotated arrows on a selection's corners and edges. Line 8 names the picture's size and hotspot. Over a panel's text or a field, the iPad's beam shows instead, as WebKit chooses.
- [ ] While dragging a layer, the cursor follows the pointer without jumping; after letting go, it doesn't blink to the iPad's pointer.
- [ ] With Settings › Show pages' own cursors off, the iPad's pointer is back everywhere.
- [ ] A secondary click (two-finger click) shows Figma's menu, and only Figma's.
- [ ] ⌘-click on a layer selects it and opens no tab.
- [ ] ⌘Z and ⇧⌘Z undo and redo in Figma. ⌘C, ⌘V copy and paste layers. ⌘F opens Figma's own find. ⌘D duplicates.
- [ ] Arrow keys nudge a selected layer; ⇧ and an arrow nudge by 10. Tab selects the next layer. If either doesn't reach Figma, turn on Settings › Tab and arrow keys › Send to the page first, and check again; note which setting works.
- [ ] Two fingers swiping sideways never goes back a page.
- [ ] Long-pressing a link or image with a finger shows no callout.
- [ ] Switch to another app and back, or click another Stage Manager window and back: typing a Figma shortcut works at once, without clicking the page first.
- [ ] On iPadOS 26, the menu bar shows the app's Go, Tabs, Spaces and Window menus, all on ⌃⌥, and none of the system's File, Edit, Format, View or Help. Hold ⌘: the shortcut list shows no ⌘ shortcut of the app's.

## 3. Sign-in, for every tool you use

For each tool, sign in from a fresh space (Spaces › New Space…, so nothing is signed in yet) with each method it offers. The address bar should show on every sign-in page with the host in bold.

Edit the rows to your own list of tools.

| Tool | Google | Email and password | SSO | Address bar on sign-in | Notes |
|---|---|---|---|---|---|
| Figma | | | | | |
| Google Workspace (Drive, Docs) | | n/a | | | |
| Slack | | | | | |
| Notion | | | | | |
| Linear | | | | | |
| Miro | | | | | |
| Jira / Confluence | | | | | |

For each:

- [ ] A sign-in in a pop-up opens over the page as a sheet with its address on top, and closes by itself when done.
- [ ] On accounts.google.com, line 1 says hands-off, nothing injected, and line 3 says the user agent is not read there.
- [ ] If Google refuses ("This browser or app may not be secure", or Error 403: disallowed_useragent), a banner says so and points to email or SSO; Go Back returns to the tool's sign-in page.
- [ ] After signing in, quit the app (swipe it away) and open it again: still signed in.
- [ ] Two spaces signed in to two different accounts of the same tool stay apart.
- [ ] Passkey buttons are expected to fail: passkeys are out of scope (see README).

## 4. Memory, with a large Figma file

1. Open the heaviest Figma file you have (a design system, a file with many pages and images). Note how long it takes to become usable.
2. Open three more tabs: Slack, Notion, and a second Figma file.
3. Switch between them while watching line 7.

- [ ] The first file stays live while you visit Slack and come back (no reload, same view).
- [ ] Opening the second Figma file freezes the first: going back shows its picture at once, then the file loads again underneath.
- [ ] More than two light tabs off screen freeze, oldest first (Settings › Light tabs kept open changes the number).
- [ ] A tab with something typed but not sent (a message half written in Slack) doesn't freeze.
- [ ] If the file runs out of memory, the tab reloads by itself and line 7's process ends count goes up. After three in a minute, a banner offers Reload instead of reloading again.
- [ ] With Xcode's Instruments (Activity Monitor template, the iPad as target), note the peak memory of the `com.apple.WebKit.WebContent` process for the file. This is the number iPadOS limits, and no setting can raise it.

## 5. Windows

- [ ] ⌃⌥N opens a second window (Stage Manager or Split View). Each window shows its own tab; choosing a tab that the other window shows brings that window forward.
- [ ] A tab's menu (long press or secondary click on it) › Open in New Window moves it there.
- [ ] Close the app and open it again: each window comes back with its space and tab.

## 6. With Apple's browser entitlement

On a build signed with it (README › With Apple's browser entitlement).

- [ ] Safience's Settings › Default browser › Make Safience the Default Browser opens Settings › Apps › Default Apps; choose Browser App › Safience. Back in Safience's Settings, it says Safience is your default browser.
- [ ] A link tapped in Mail, Notes or Slack opens in Safience, in a new tab after the one on screen, which stays as it was.
- [ ] On a site that offers passkeys (Google, GitHub, Figma if offered), signing in with a passkey shows the system's passkey sheet and signs in.
- [ ] Creating a passkey on a site saves it in the Passwords app.
- [ ] The key button above the keyboard lists the site's own passwords without searching, and a verification code field offers the code.
- [ ] Share Page (⌃⌥S, or the tab's menu) shows the share sheet with Add to Home Screen; the icon it adds opens the page.
- [ ] A site with a service worker (an offline-capable web app) registers it: Diagnostics or the site itself says so.

## 7. Compact tabs, pinned tabs, bookmarks, spaces

- [ ] One row: the space's button in its colour, back and forward, pinned icons, tabs at one width, + and ⌘. The tab on screen shows a close button, its host with the name that matters in bold, the key badge on a sign-in page, the star and reload; it alone is in Liquid Glass.
- [ ] Clicking another tab only goes to it: no tab changes width. Going to a pinned tab keeps it an icon, unless its page is a sign-in page.
- [ ] Clicking the tab on screen: its host turns into the address, selected, in place, then the field widens over the other tabs without moving them; typing replaces it; Return goes; a click on the page or Escape takes the field back into the tab the same way, and the tab is as it was.
- [ ] Settings › The tab you are on shows › Its title: the tab shows the page's title, and its host on a sign-in page.
- [ ] With Settings › Show the tab bar off, the row still shows on a sign-in page and on a new tab.
- [ ] Split: a tab's menu › Open in Split View puts it beside the tab on screen, both as one tab in the row; a click in either pane moves the keys, the glass half and the coloured line to it; the divider drags and a double tap centres it; the + button's menu › New Tab in Split View opens a new tab beside, typed into; closing a pane leaves the other full width; the split comes back the same after relaunch.
- [ ] With the Korean keyboard, typing github.com in the palette shows Open github.com before any other key, and Return goes there; the same in the address field.
- [ ] Pin a tab from its menu: it becomes an icon at the front. Go elsewhere in it, then close it (⌃⌥W): it stays, and opening it shows its pinned page again. Unpin puts it back among the others.
- [ ] Import Chrome's export, then Safari's ZIP (Settings › Apps › Safari › Export › Bookmarks), into one space: the grid on a new tab shows them, the second import of the same file adds nothing, and another space's grid stays empty.
- [ ] The star adds and takes away the page; a bookmark's menu opens it in a new tab or deletes it; ⌃⌥K finds bookmarks by name.
- [ ] Space Settings changes the name, colour and icon at once in the bar; Settings › Spaces › Edit reorders, and ⌃⌥↑ ⌃⌥↓ follow the new order.

## 8. iPhone, iPhone Duo, iCloud

- [ ] On an iPhone, the bars are at the bottom: back and forward, the address, the tabs (with their count), the space, + and the menu. Tapping the address types a new one, the address selected, with the bar above the keyboard; Return goes.
- [ ] A site's mobile version loads (the page names an iPhone); it scrolls and pinches with a finger. Menu › Request Desktop Site loads the desktop version, and the site keeps it next time.
- [ ] The tabs button shows the space's tabs as a grid; a tap goes to one, × closes one, + opens a new tab.
- [ ] Turned sideways, an iPhone keeps the bars at the bottom (a Pro Max turns to the iPad's row) and keeps mobile sites.
- [ ] On an iPhone Duo: folded, the bars are at the bottom and sites are mobile; unfolded, the iPad's row comes back and sites load as desktop on the next page. Folding mid-typing leaves the address as it was.
- [ ] Settings › iCloud › Sync Spaces and Bookmarks on two devices with the same account: a space of the same name joins with both devices' bookmarks; a bookmark added on one shows on the other within a minute; a space removed on one goes on the other; tabs and sign-ins don't move.
- [ ] Signed out of iCloud, Settings says to sign in.

## 9. ⌘-click

On any site with links (a news site, GitHub), with the trackpad:

- [ ] ⌘-click on a link opens it in a new tab after the one on screen, which stays as it was. Two more ⌘-clicks put their tabs after the first, in order.
- [ ] ⌘⇧-click on a link opens it and goes to it.
- [ ] With a mouse, the middle button opens the link behind.
- [ ] A link that opens a new window by itself (Slack's, Notion's) opens behind with ⌘ and in front without it.
- [ ] ⌘-click on a search button (Google's, Wikipedia's) opens the results in a new tab; ⌘-click on a form that sends something (a comment's Post) sends it once, in place.
- [ ] A plain click on a link still goes there in place.

## 10. Ads and trackers

- [ ] A news site with ads (a newspaper's home page) shows no ad slots, and loads no Google Tag Manager or Analytics (Web Inspector's Network tab, or line 9 of Diagnostics says "on here").
- [ ] Menu › Allow Ads on This Site loads it again with its ads; Block Ads on This Site takes them away again; the choice stays for the site after a relaunch.
- [ ] accounts.google.com: line 9 says "off here", and line 1 "hands-off, nothing injected".
- [ ] Settings › Ads and trackers off: ads come back on every site from the next page; on again, they go.
- [ ] After four days with the app opened, Settings shows lists dated within the last week.
