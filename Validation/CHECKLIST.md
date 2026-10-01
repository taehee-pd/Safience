# Validating on a real iPad

What the tests in `Tests/` can't show: a real trackpad, a real keyboard, real sign-ins, real memory. Turn on the Diagnostics panel first (⌃⌥D, or Settings › Show diagnostics); most checks below read from it.

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

## 1. Figma zooms on a synthetic ctrl+wheel (Mac Safari)

The pinch bridge rests on this, so check it first.

1. On a Mac, Safari › Settings › Advanced › Show features for web developers.
2. Open a Figma design file in Safari and click once on the canvas.
3. Develop › Show JavaScript Console, paste all of [figma-ctrl-wheel.js](figma-ctrl-wheel.js), press Return.

- [ ] It prints `PASS: Figma zooms on a synthetic ctrl+wheel.` and the canvas zooms in, then back out.
- [ ] If it prints `LOOK:`, the zoom couldn't be read: the canvas should still zoom in and out.

The same works inside the app: connect the iPad to the Mac, open the file in Safience, and pick its page under Safari's Develop › (your iPad). Every page in the app is inspectable.

## 2. Trackpad and keyboard in Figma

Open a design file in Safience, with a Magic Keyboard or a trackpad.

- [ ] Line 1 says Figma, desktop pages, heavy. Line 3 says Mac Safari.
- [ ] Hovering layers and frames highlights them; clicking selects; dragging moves.
- [ ] Pinching on the trackpad zooms the canvas around the pointer, not the whole page. Line 2 stays at zoom 1.00; line 4's pinch count goes up.
- [ ] ⌘ and two fingers zoom too.
- [ ] Two fingers pan the canvas. On line 5, if WebKit's own wheel events stay at 0, the bridge is doing the panning (line 4's bridged count goes up); if they go up, WebKit sends them itself and the bridge stands aside. Either way, note which.
- [ ] A quick two-finger flick keeps gliding for a moment, as on a Mac (only when the bridge does the panning).
- [ ] A secondary click (two-finger click) shows Figma's menu, and only Figma's.
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
