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
- [ ] On a page opened at an address with `?id=7&utm_source=letter&fbclid=x`: the share sheet's Copy, the page's menu's Copy Link (… on iPhone, the tab's menu on iPad), a link's Copy Link and Share…, and the tab overview's Copy Link all give the address with `id=7` alone. A YouTube link shared from its app (`?si=…`) and an X post's (`?s=20&t=…`) lose those; `?t=42` on YouTube stays.
- [ ] A site with a service worker (an offline-capable web app) registers it: Diagnostics or the site itself says so.

## 7. Compact tabs, pinned tabs, bookmarks, spaces

- [ ] One row: the space's button in its colour, back and forward, pinned icons, tabs at one width, + and ⌘. The tab on screen shows a close button, its host with the name that matters in bold, the key badge on a sign-in page, the star and reload; it alone is in Liquid Glass.
- [ ] Clicking another tab only goes to it: no tab changes width. Going to a pinned tab keeps it an icon, unless its page is a sign-in page.
- [ ] Clicking the tab on screen: its host turns into the address, selected, in place, then the field widens over the other tabs without moving them; typing replaces it; Return goes; a click on the page or Escape takes the field back into the tab the same way, and the tab is as it was.
- [ ] Settings › The tab you are on shows › Its title: the tab shows the page's title, and its host on a sign-in page.
- [ ] With Settings › Show the tab bar off, the row still shows on a sign-in page and on a new tab.
- [ ] Split: a tab's menu › Open in Split View puts it beside the tab on screen, both as one tab in the row; a click in either pane moves the keys, the glass half and the coloured ring to it; the two pages are cards with the frame's corners and gap; the divider drags, settles in the middle with a tap when let go near it, and a double tap centres it; the + button's menu › New Tab in Split View opens a new tab beside, typed into; closing a pane leaves the other full width; the split comes back the same after relaunch.
- [ ] Drag to split (iPadOS 27): a tab dragged from the row along the top onto the page shows Open on the Left and Open on the Right; the side under the finger grows to the pane, ringed in the space's colour, with a tick; let go there and it opens on that side with the keys; over a split it takes that side's place; the other pane's tab carried across swaps them; let go in the middle, nothing changes; the same from the sidebar; under Reduce Motion the sides change in place.
- [ ] With the Korean keyboard, typing github.com in the command bar and pressing Return goes to github.com, the last letter included.
- [ ] Pin a tab from its menu: it becomes an icon at the front. Go elsewhere in it, then close it (⌃⌥W): it stays, and opening it shows its pinned page again. Unpin puts it back among the others.
- [ ] Pin vercel.com and mobbin.com, in light and dark: on screen each tile shows its icon over a faint glow (Vercel's black disc whole; Mobbin's M black in the light, white in the dark), and at rest Mobbin's M is white in the dark.
- [ ] Import Chrome's export, then Safari's ZIP (Settings › Apps › Safari › Export › Bookmarks), into one space: the grid on a new tab shows them, the second import of the same file adds nothing, and another space's grid stays empty.
- [ ] The star adds and takes away the page; a bookmark's menu opens it in a new tab or deletes it; ⌃⌥K finds bookmarks by name.
- [ ] Tabs in a sidebar (iPad and Mac): Bookmarks over New Tab brings the bookmarks out over the list as a card with ✕, not as rows among the tabs; a tap on one opens it in the tab on screen and the card goes; ⌘-click (a keyboard and trackpad on iPad) opens it in a new tab and the card stays; a folder opens in place; ✕, Escape, a tap outside the card or on the page, and another space each put it away; light and dark.
- [ ] A toast at the page's top right, in Liquid Glass, for about two seconds: Copy Link (⌃⌥⇧C on iPad, ⇧⌘C on the Mac, the page menu, a tab's or a bookmark's menu, a link's) says Link Copied; the star or ⌃⌥⇧D says Added to or Removed from Bookmarks; Allow or Block Ads on This Site says so; another copy at once replaces it; taps and clicks go through it; VoiceOver reads it; on iPhone it is below the status bar.
- [ ] Space Settings changes the name, colour and icon at once in the bar; Settings › Spaces › Edit reorders, and ⌃⌥↑ ⌃⌥↓ follow the new order.

- [ ] Settings has nothing written under App icon, Desktop View, Trackpad and keyboard, Diagnostics or Shortcuts, and nothing under Default browser once Safience is the default. The filter lists' credits show beside each list, in Ads and trackers › Filter lists.
- [ ] Settings › App icon: Engineer's globe looks the size of the other icons' globes, with clear room under the title bar and over the icon's bottom edge.
- [ ] Settings › App icon and the Home Screen, light, dark and tinted: the default icon is the oval globe in pale blue on a sky-blue oval, its rim ridged on the left, with a dark navy cursor; Punk's spray can leans in as the pointer with its cap toward the globe; Astro's pointer is a glass shuttle with a glowing flame; each still reads as a pointer at the Home Screen's size.
- [ ] Settings › App icon: choosing Designer changes the Home Screen icon after the system's notice; choosing Safience puts the app's own back. With Diazo, Lilac, Oxide, Citrus or Midnight chosen in an earlier build (the names Designer, Vista, Hardcover, Punk and Astro had then), note what the Home Screen shows after the update; nothing is ringed in Settings, and choosing the icon again there sets it. Designer is a globe in lines of one weight with square anchor points at its left, right and bottom, a light blue square of the same size at its top and two light blue handles out level from it, each ending in a dot, under the pen tool, in Settings and on the Home Screen. Punk is the globe sprayed in black on an acid-lime wall in light and in lime on black in dark, with a chrome spray can in the lower right leaning toward it, cut off by the icon's edge and solid (the wall doesn't show through it), in Settings and on the Home Screen.

## 8. iPhone, iPhone Duo, iCloud

- [ ] On an iPhone, the bars are at the bottom: back and forward, the address, the tabs (with their count), the space, + and the menu. Tapping the address types a new one, the address selected, with the bar above the keyboard; Return goes.
- [ ] A site's mobile version loads (the page names an iPhone); it scrolls and pinches with a finger. Menu › Request Desktop Site loads the desktop version, and the site keeps it next time.
- [ ] A long page (a Wikipedia entry, a news story) scrolled to its end: its last line and the links at its foot come up over the bar, and nothing of it stays under. The bar is still over the page while it scrolls, the page showing through its blur.
- [ ] A page that only fills the window: google.com (its foot with Settings, Privacy and Terms), a sign-in page, a chat with its field at the bottom (chatgpt.com, claude.ai), an editor with tools at the bottom (excalidraw.com). Its bottom row shows above the bar and takes a tap; the bar has the colour of the page's last points. It may show under the bar for a third of a second as the page comes in. From such a page to a long one (a search from google.com) the page runs under the bar again, and its end still scrolls clear.
- [ ] With the keyboard up in a page's own field at the bottom (a chat), the field stays above the keyboard, and when the keyboard goes the page is as it was. Turned sideways and back, the same.
- [ ] The tabs button shows the space's tabs as a grid; a tap goes to one, × closes one, + opens a new tab.
- [ ] With more pinned tabs than the dock at the bottom of the tabs has room for (ten on a Pro Max), the dock scrolls sideways, and an icon half out at either end is cut along the dock's rounded end, nothing of it past the outline.
- [ ] Turned sideways, an iPhone keeps the bars at the bottom (a Pro Max turns to the iPad's row) and keeps mobile sites.
- [ ] On an iPhone Duo: folded, the bars are at the bottom and sites are mobile; unfolded, the iPad's row comes back and sites load as desktop on the next page. Folding or unfolding mid-typing carries what is typed over to the other field, the cursor at its end.
- [ ] On an iPhone Duo closed: the strip beside the screen has back and forward at its top, … under them with the page's menu, and + and the tabs (with their count) at its foot; the bar at the bottom is one row, the space and the address, and the page starts at the top of the screen. Typing an address hides the space and the strip moves + into its …. The tabs from the strip while an address is typed end the typing; + or anything else from the strip with the tabs out puts them away first, and the tabs again only puts them away. A sideways swipe on the bar brings the next tab's row in from the strip's edge, not from under it. The tabs' Done stays clear of the strip.
- [ ] On an iPhone Duo open, upright and turned: the same tools stand in the strip beside the status bar, the iPad's bars along the top with nothing above them; Tabs in the strip shows the tab bar, and again hides it; with Settings › Window › Tabs › In a Sidebar, the strip has no Tabs.
- [ ] On an iPhone Duo opened like a book, with the tabs in a sidebar: the sidebar reaches the fold and the page starts past it; closed and opened again, the same.
- [ ] In the iPhone's tabs, touch and hold a card, then move it: the tab goes there, in the iPad's row and sidebar too. A quick sideways swipe still closes a card.
- [ ] An iPhone with a keyboard attached: the command bar's rows show their keys, and Settings has Keyboard (the Tab and arrow keys), Shortcuts and Known limitations; with the keyboard gone, none of them.
- [ ] In Desktop View on iPhone, a pinch past the closest or the farthest zoom gives a little and springs back as the fingers let go.
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
- [ ] After four days with the app opened, Settings › Ads and trackers › Filter lists shows lists dated within the last week.
- [ ] Korean sites: on m.dcinside.com's gallery list no "AD" line shows under the heading and no "광고" row at the foot of the list; on clien.net no empty grey block sits between the notice board and the first list. With YousList off in Filter lists, both come back after a reload.
- [ ] Filter lists: EasyList, EasyPrivacy, YousList and the Adblock Warning Removal List are on; KoreanList is on too on a device set to Korean or to the Korea region, and a regional list on a device in its language. Each row names the list's authors and licence.
- [ ] Turning a list on that doesn't ship (EasyList Cookie List) says "Getting ready…", then its date and rule count within a minute; the Rules count in Settings goes up. In Airplane Mode it says "Not downloaded yet", and it comes after the app is opened again with a network.
- [ ] With the Cookie List on, a site with a cookie banner (a European newspaper) shows none after a reload.
- [ ] A page that opens an advertiser's window at a tap (a streaming or download site) opens none.
- [ ] Diagnostics' ad blocking line counts the filters kept for scripts. On a site with none of its own (example.com) Web Inspector shows no `blocker.js` or `scriptlets.js` among the page's scripts.
- [ ] A clean install: within a minute Settings shows the rule count, and Xcode's memory gauge stays under about 200 MB while the lists are made (it was over 300 MB).
- [ ] A site whose filters hide by what an element says (target.com's search results, signed out: the tiles marked "Sponsored"): the tiles are gone, more of them go as the page is scrolled and loads more, and scrolling stays smooth. In Web Inspector's Timelines, `blocker.js` shows as a millisecond or two after each batch the page adds, not tens.
- [ ] Turning a list off and on again quickly in Filter lists says "Getting ready…" at most once, and the Rules count is the same as before.

## 11. Address bar suggestions

In a space with a few tabs, a pinned tab and bookmarks, on iPad in each layout (Settings › Window › Tabs) and on an iPhone. On iPad the field is the command bar, floating over the page (section 16); on iPhone it is in the bar at the bottom:

- [ ] On an iPhone, the app closed from the app switcher and opened again: the first tap on the address brings the keyboard up with the address selected, and the bar stays where it is until the keyboard comes, then rides up over it. It never sits at the foot of the screen with its tools cut off. The second tap is as quick as it was. With a keyboard with keys attached, the bar makes room a moment after the first tap.
- [ ] Typing "fig" with figma.com open in a tab shows it first, "fig" plain and "ma.com…" in bold, its title under it and "Open Tab" at the end; Return goes to that tab rather than loading the page again.
- [ ] A pinned tab says "Pinned Tab", a bookmark "Bookmark", and "new" offers New Tab and New Space, with their keys drawn as keys on iPad and "Command" at the end on iPhone; choosing New Tab opens one, the command bar open for it.
- [ ] After a moment, Google's suggestions show under the first row, marked "Google"; choosing one searches for it. With Settings › Search engine set to DuckDuckGo or Bing they come from it and say so; with Kagi there are none.
- [ ] ↓ from the field chooses the first row, ↑ from it goes back to the field, and Return with no row chosen sends what was typed, as before. A tap or a click on a row takes it.
- [ ] Korean: typing 피그마 shows Google's suggestions while the last syllable is still being composed, and Return sends the whole word.
- [ ] Typing figma.com/ sends nothing to Google (Web Inspector's Network tab on the app shows no suggestqueries request), and Settings › Search engine suggestions off sends nothing at all while tabs and bookmarks still show.
- [ ] Escape, Cancel, a tap on the page, or going to another tab takes the rows away with the field. On iPhone the rows sit just above the bar and scroll when the keyboard leaves them little room.
- [ ] With Apple Intelligence on (iOS or iPadOS 26): "share this page" offers Share Page…, "탭 고정" and "pin this" Pin or Unpin Tab, "광고 차단" Block or Allow Ads on This Site, "email" an open Gmail tab, and a few words about a tab's subject that share no word with its title (a Figma file's topic) offer that tab, each a few seconds after typing stops, with sparkles beside its source. Two letters, or figma.com, never wait on the model.
- [ ] A plain web search typed with tabs and bookmarks open ("weather tomorrow", "lasagna recipe", "how to center a div") gets no row with sparkles, however long one waits; the rows with sparkles are as many as fit, none to five, never three every time.
- [ ] With Settings › Search engine suggestions off and Apple Intelligence on, searches marked Apple Intelligence show instead of Google's; with Airplane Mode on, they still do.
- [ ] Settings › Suggest with Apple Intelligence off: no sparkles. With Apple Intelligence off in the Settings app, on iOS 18, or on a device without it, Settings › Search has no Suggest with Apple Intelligence switch and says nothing of Apple Intelligence, and the app starts as before.

## 12. The phone bar's swipe, and a link's menu

On an iPhone, in a space with three tabs or more:

- [ ] A drag to the left on the bar brings the next tab in from the right, its page and its address both following the finger; letting go past halfway, or with a flick, goes to it, and short of that springs back.
- [ ] At the last tab a drag to the left moves a little and springs back; at the first, a drag to the right.
- [ ] A swipe up on the bar still shows the tabs, and while an address is typed a sideways drag only moves the text's caret.
- [ ] In Desktop View a sideways drag on the bar does nothing.
- [ ] A long press on a link lifts it with a menu under its address: Open in New Tab goes to it in a new tab, Open in Background adds a tab (the count goes up, with a tap felt) and stays, Copy Link puts the address on the clipboard, Share… opens the share sheet. A tap on the lifted link goes there in the same tab.
- [ ] On iPad at full width, a long press with a finger on a link on a plain page (a Wikipedia article) shows the same menu, and so does a secondary click with the trackpad, a moment after the click.
- [ ] On iPad, a secondary click on a link in a page with a context menu of its own (a file in Figma's file browser, a message in a web mail app, a row in GitHub's file list where the site has none) shows only the page's menu where it has one, never both.
- [ ] In Figma, on the canvas and in the file browser, a long press with a finger and a secondary click show only Figma's own menus.
- [ ] On accounts.google.com a long press on a link shows no menu of the app's.

## 13. Sites with their own menus, pictures, swipes, find

Sites with their own menus:

- [ ] Settings › Link menu › Sites with their own menus lists the built-in sites, each with a switch, and Add takes an address (`https://www.example.com/app` becomes example.com) and refuses a word that isn't one.
- [ ] On a plain page, the page's menu has Use This Site's Own Menus; after it, a long press on a link there shows nothing, the site is under Your sites in Settings, and the menu says Show Link Menu on This Site, which undoes it.
- [ ] With Figma's switch off in Settings, a long press on a link in Figma's file browser shows the app's menu; with it on again, only Figma's.
- [ ] In Google Docs, Notion, Linear and Slack, a secondary click and a long press show only the app's own menus; on google.com's results a link still has the link menu.

Pictures:

- [ ] A long press on a picture that isn't a link lifts it with Share…, Save to Photos, Copy and the rest; Save to Photos asks once to add to Photos and the picture is there afterwards.
- [ ] A long press on a picture that is a link shows the link's menu with Save to Photos at the bottom.
- [ ] On iPad, a secondary click with the trackpad on a picture in a page with its own context menu shows only the page's menu. (Not checked in the simulator, which has no pointer to click with.)

Back and forward by a swipe:

- [ ] On iPhone, a finger dragged in from the left edge slides the page before in, and from the right edge the page after.
- [ ] On iPad, on a desktop page with a page to go back to, a finger dragged in from the page's left edge brings an arrow in; letting go once it has filled goes back, and before that does nothing. With nowhere to go back to, no arrow shows and the page gets the drag.
- [ ] On iPad with a trackpad, on a plain page (a Wikipedia article reached from another), two fingers to the right bring the arrow in from the left and go back; two fingers to the left go forward.
- [ ] In Figma, on the canvas, two fingers sideways pan the canvas and never go back, however far and however often. The same in Miro, Google Sheets and a map.
- [ ] On a page with a row that scrolls sideways (a carousel, a wide table), two fingers sideways over the row scroll it, and a swipe that reaches the row's end doesn't go back. A new swipe begun at the row's end does, as in Safari on a Mac, and so does one away from the row.
- [ ] In a split view, each pane goes back by a drag from its own left edge.
- [ ] ⌘ with two fingers still zooms, and ⇧ with a mouse wheel scrolls sideways without going back.

The cursor at the page's top and bottom, in the iPhone's Desktop View:

- [ ] One finger down moves the cursor to the bottom of the page, and what the finger moves after that scrolls the page down; the cursor stays at the bottom. The same upward: at the top, the page scrolls up.
- [ ] With the cursor already at the bottom, a flick down scrolls and glides on, and a touch stops it. A flick that only gets the cursor to the bottom doesn't glide.
- [ ] Sideways along the bottom, and back up from it, scroll nothing.
- [ ] Zoomed in with a pinch, the view follows the cursor to the desktop's bottom first, and only then does the page scroll.
- [ ] Touch and hold, then drag past the top or the bottom: the page scrolls while the button is held.
- [ ] In Figma, the cursor pushed against the top or the bottom pans the canvas, as two fingers do.
- [ ] On a page laid out as an app (a chat, a mail client: a bar of its own at the top or the bottom, and a list between them that scrolls by itself), the cursor pushed against the bottom rests on the page's bar and the list scrolls down all the same; against the top, up. Two fingers with the cursor on the bar do the same.
- [ ] With the cursor over a list that is at its end, pushing on scrolls nothing else on the page.
- [ ] On a long page with a frame in it that has nothing to scroll (the page's own, or another site's: a video's player, a map), the cursor left over the frame and pushed against the bottom scrolls the page.
- [ ] A page that scrolls inside its body (`html, body { height: 100%; overflow-x: hidden }`, as many a React app has) scrolls with two fingers and with the cursor at the bottom.
- [ ] A page of full-screen sections that snap (`scroll-snap-type: y mandatory`) goes one section a stroke, not to its end.
- [ ] A PDF in Desktop View scrolls with two fingers and with the cursor pushed against the bottom or the top.

Pull to load again, and find:

- [ ] On iPhone, at the top of a page, a pull down shows the spinner and loads the page again; the spinner goes when the page is back.
- [ ] On iPad, on a desktop page, and in the iPhone's Desktop View, a drag down does nothing of the kind.
- [ ] Find on Page (⌃⌥F, or the page's menu) shows the find bar; a word typed is counted and marked, and the arrows go from one to the next. After the bar is closed, ⌘F in Figma is Figma's again.

## 14. Links for other apps

- [ ] A `tel:` or `mailto:` link, and a link with an app's own scheme, opens that app at once when tapped.
- [ ] On a site with an "Open in app" button (instagram.com or youtube.com on an iPhone, with the app installed): the button asks "Open in Another App?", naming the site; Open goes to the app, and coming back, no empty tab has been left behind.
- [ ] Cancel, then the button again: it asks again. A second Cancel, and it asks no more until the page is loaded again.
- [ ] A link to Instagram or YouTube in a search's results opens the app, as in Safari (a universal link, which WebKit opens itself).
- [ ] With the app not installed, Open says that nothing on the device opens the link.
- [ ] A page that tries another app by itself as it loads (an ad's redirect to the App Store) only asks; nothing opens without Open.

## 15. The phone bar in the page's colour

On an iPhone, with the system in Dark Mode and again in Light Mode:

- [ ] Over a white page the bar fades to white and its controls are dark; over a dark page it fades to dark and they are light. Neither depends on the system's appearance.
- [ ] Over a page with a coloured ground (a navy footer, a yellow banner) the bar takes that colour.
- [ ] Scrolling from a light part of a page to a dark one turns the bar over as the dark part comes under it, eased and without a flash, and scrolling stays smooth.
- [ ] A new tab's start page has the system's own ground: dark in Dark Mode.
- [ ] In Desktop View the bar goes by the page under it in the same way.
- [ ] On iPad, with the tabs along the top, the row stands on the space's colour and the page is a card 5 points in, light or dark as the system is whatever the page's colour; with a split, the half on screen in the row sits inside its pair's ground, its glass's rim showing all round.

## 16. The command bar

On iPad with a keyboard, in a workspace with two spaces, a few tabs in each and bookmarks:

- [ ] ⌘T makes a new tab and the command bar comes up over it, in the middle a little down from the top, empty, with rows under headings: Open Tabs, Tabs in Other Spaces, Spaces, Commands (each with its keys drawn as keys), Settings, Bookmarks. The + button does the same.
- [ ] An address or a search typed there and Return loads in the new tab. ↓ to an open tab and Return goes to that tab, and the new, empty tab is gone from the row. A tab of another space goes to that space. Escape leaves the new tab, with the start page.
- [ ] On a page, ⌘T, then "reload" and Reload Page: the page reloads and no empty tab is left. The same with Pin or Unpin Tab (the page's tab is pinned) and Settings (Settings opens over the page).
- [ ] Typing narrows the rows; "tab" lists every command with Tab in its name before Google's suggestions; a command taken runs (Reload Page, Settings, Pin or Unpin Tab).
- [ ] A click on the address in the tab on screen, and ⌃⌥L, open the bar holding the page's address, selected, with no rows; typing replaces it and Return loads in that tab. In the separate layout a click on the address bar does the same.
- [ ] ⌃⌥K opens the bar empty with everything listed and makes no tab. ⌃⌥K or ⌘T while the bar is already open starts it over. With Settings › Show the tab bar off, no bar comes out while typing.
- [ ] With a keyboard attached and an address being typed, drag the window to phone width, or back to full width: the typing ends, and the keys go to the page at once (the arrow keys scroll it) with no tap on the page.
- [ ] "change icon" offers App Icon marked Settings; taking it opens Settings with App icon's heading just under the title bar, in the accent colour for a moment, with or without the on-screen keyboard up. "ad blocker", "search engine", "shortcuts" and "sync" go to their sections. On iPhone "cursor speed" goes to Desktop View, and no Trackpad or Shortcuts part is offered.
- [ ] A click on the page, on the start page's bookmarks or on another tab puts the bar away, and the click does what it would have. The page under the bar still scrolls with two fingers.
- [ ] With the on-screen keyboard (no hardware keyboard), the bar's rows end above the keyboard and scroll.
- [ ] The bar is Liquid Glass on iPadOS 26 and later (the page shows through, bent at its edges) and blurred material on iPadOS 18. Its tint is the row of tabs' colour: on a site with a dark top (a dark theme-color) the bar is dark with light words. Settings › Appearance › Liquid Glass moved to clear and to tinted makes the bar clearer and more opaque, on iPhone's rows too. ⌘T pressed twice makes one new tab, not two. Reduce Motion: the bar only fades. Reduce Transparency: it is solid. VoiceOver reads a command's row as its name and its keys in words.
- [ ] ⇧⌘T after closing an empty new tab reopens the last page closed, not the empty tab.

On an iPhone:

- [ ] + makes a new tab, gives a light tap, and opens the field over the keyboard with everything listed over it, under the same headings, commands without keys. Cancel leaves the new tab with the start page.
- [ ] The page's menu (…) › Commands lists everything without making a tab.

## 17. Handoff

With Settings › Handoff on, and Claude, ChatGPT or Gemini installed:

- [ ] On an iPhone the page's menu (…) ends in a row of three: Find, Share, Handoff, with Copy Link over it. With Handoff off in Settings the row is Find and Share. On an iPad the tab's menu has Copy Link and then Handoff Page… after Share Page, and ⌃⌥H and the command bar run it.
- [ ] On a device with Apple Intelligence, Handoff on an article (a Wikipedia entry, a blog post) shows a sheet from the bottom: Handoff, "Give an assistant this page's context.", and three steps with a line down their side. The first (The context is one file) is ticked; the second (Apple Intelligence organises it) has its sparkles in the space's colour, moving, and a card under it with a page under a magnifying glass, "Reading this page…" and "This takes a few seconds."; the third (You ask in the app you choose) is grey, its share symbol in the middle of its mark. Then the second is ticked and its card shows a newspaper in the space's colour, "This is an article" and "You'll share all of its text.", the third takes the colour and a tap is felt. The Share button is dimmed and does nothing until then; after, it opens the share sheet. The share sheet never opens by itself, however long the sheet is left. Swiping the sheet down ends the handoff and no share sheet comes. With Reduce Motion on, nothing on the sheet moves but fades.
- [ ] At the largest text size the sheet scrolls, and Share can be reached.
- [ ] The card names the page rightly: a megaphone and "This is a landing page", "You'll share its main sections." on linear.app; a window and "This is a web app", "You'll share what's on the page." on excalidraw.com; a list and "This is a list of links", "You'll share one line per item." on a page of search results (duckduckgo.com, npmjs.com/search); a play button and "This is a media page", "You'll share its description." on a video at vimeo.com; a globe and "This page is ready", "You'll share all of its text." on a repository at github.com.
- [ ] With a sentence selected on an article, the card's second line is "Your selection goes first.", and the file has "The reader selected this on the page:" and the sentence as a quotation before the page's text.
- [ ] On a device without Apple Intelligence (an iPhone 14, any device before iOS 26), or with Apple Intelligence off in the Settings app: no Handoff in the page's menu, the tab's menu, the menu bar or the command bar, ⌃⌥H does nothing, Settings has no Handoff section, and Settings › Shortcuts does not list it. Turn Apple Intelligence on and come back to the app: all of it is there.
- [ ] In Low Power Mode, the same sheet comes up: the second step is "Safience organises it" with a list for its mark and no sparkles, its card goes from "Reading this page…" to what the page is within a second, and Share is dimmed only until then. The file has no summary line.
- [ ] With VoiceOver on, Share is read as dimmed while the page is read, and what the page turned out to be is spoken when it is ready.
- [ ] The share sheet's header names a Text Document with the page's title. Save to Files, then open the file: the title, `Source:` with the address, "About this file, written by Safience and not by the page:" (the kind of page, what follows, and a summary said to be the page's claim where the model answered), "From the page:" (its description, what it declares, the heading that was on screen, what was set aside), then the page's text. "About this file" begins with "Read:" and a time ending in Z, and `Source:` has no `utm_` or `fbclid` in it for a page opened from a newsletter or an advertisement.
- [ ] A maker's page for a phone (apple.com/iphone) has "Not in this file: the site's foot …" with a count, "… large pictures have no description", marks such as `[^4]` in its text with the notes they point to at the file's end, and no `.m3u8` address. A video at youtube.com has "[Video: …, 53:57]" where the player is, "Its title where it is shared:" where the title shown was translated, and "What the recording says is not in this file". A shop's page at a Korean store (brand.naver.com) has a summary in Korean that names what the page sells, each sold-out link once, and its notices under "Set aside, Footer".
- [ ] A landing page (linear.app, stripe.com, apple.com/iphone) goes as "landing page": a long list of short lines ends in "[… more characters here.]", every paragraph of some length is there whole, and a pricing or questions section is whole and named after "Whole:". A tool with little to read (excalidraw.com, squoosh.app) goes as "web app". A repository on GitHub goes whole, with no kind named. A news site's front page goes whole or, where most of it is headlines with a link each, as a list of links.
- [ ] An article with comments under it (a blog post, a news story) has its text whole and "Set aside, Comments: … characters, starting …" under "From the page"; the comments are not in the text, and a sharing bar or newsletter box is not there at all.
- [ ] A web app scrolled part of the way down (a board, a long form) begins with what was on screen, then "[On screen down to here. The rest of the page follows.]". An article scrolled down says "On screen when shared:" and the heading that was there.
- [ ] A list of search results goes as "list of links", one line a result: its title as a link, then the start of what it says. A video's page goes as "video or audio page", with "It declares: published …, length …" where the page says so. A job posting that declares itself (jobs.lever.co, jobs.ashbyhq.com, wanted.co.kr/wd/…) goes as "job posting", whole, with "It declares: … employer …, full time, pay …, closes …" where the page says so, and the card says "This is a job posting", "You'll share the whole posting."; a board's search (wanted.co.kr/wdlist) does not. A posting at job-boards.greenhouse.io/<company>/jobs/<number>, which declares nothing, goes as "job posting" too, with "Set aside, Apply for this job: …" (and "Voluntary Self Identification" where the form has it) under "From the page" and no form fields in its text; so does one job's page on a myworkdayjobs.com board. The company's list of jobs on either goes as "page" or "list of links". A discussion (a question at stackoverflow.com) and a product page go whole, as "page" or "article": their kinds are not told yet (`Handoff.builtKindsInUse`).
- [ ] On an iPad, a video at youtube.com that has a transcript: Handoff without pressing anything. The page does not move and no panel shows; the sheet's card ends on "You'll share its transcript too."; the same for a video with chapters, whose transcript is in a panel with two tabs; the file has "What the recording says is at the end, under "Transcript", as the site's own transcript has it" and `## Transcript` with paragraphs that each begin with a time. With "Show transcript" already open, it is read and stays open. With the chapters panel open, that panel stays as it was and the transcript still comes, some seconds later (from the video's page loaded out of sight, as on an iPhone).
- [ ] On an iPhone, the same video at m.youtube.com: the sheet stays on "Reading this page…" for up to 14 seconds, then shows the transcript line, and the file has the transcript. Nothing is heard, the page does not change, and no second tab shows in the tab overview. With the sheet swiped down while it waits, nothing more is loaded (no sound, no new tab). A video with no transcript gives a file that says so, within the same time.
- [ ] On an iPhone, a long entry at en.wikipedia.org with its sections shut: the file has what is under each heading, not only the first paragraph, and for a very long one "The page went on past the 100,000 characters read" with "Headings past where it was read to: …" under "From the page".
- [ ] On an iPad, a post at blog.naver.com (one frame): the file has the post's text. Selecting a sentence in the post first puts it under "The reader selected this on the page:".
- [ ] A page of documentation with coloured code (docusaurus.io/docs/installation, fasterthanli.me): each block of code is fenced with its language, one line of code a line.
- [ ] A document at docs.google.com on an iPhone, with the "Open in the app" sheet up: the file has the document's text and "The page had a sheet over it when it was read". A sheet in the editor on an iPad (docs.google.com/spreadsheets) says "Most of what this page shows is drawn by the page and is not text".
- [ ] A shop's page for one thing (11st.co.kr, ikea.com): "It declares: a product, "…": price …" with the product's name, and the colour or size picked on the page marked "[chosen]" in the text.
- [ ] A board's post of a line with replies (clien.net): the replies are in the text, not under "Set aside, Comments", and the board's drawer of every other board is not in the file.
- [ ] Picked from the share sheet, Claude, ChatGPT and Gemini each open with the file attached and "URL: …" and "Question:" as the message, the question left for you to write. Settings › Handoff has its switch and no question field. Note which of them drop the file or the words.
- [ ] Time from the tap on Handoff to "Reading the page…" turning to its result, on an iPhone: note the seconds, with and without a picture (a page with under 1,500 characters of text is looked at too, on iOS 27).
- [ ] On accounts.google.com Handoff is not in the menu, and ⌃⌥H does nothing.
- [ ] A PDF or a picture open in a tab: the sheet's card says "Nothing to read here" and "You'll share the page's address.", and Share opens the share sheet with "URL: …" and "Question:" alone.


## 18. Chrome extensions on a Mac

On the signed DMG, not a build run from Xcode, and on each macOS the release names (26 has not been tried yet). Two spaces, Work and Personal.

- [ ] Dark Reader's page on the Chrome Web Store shows Add to Safience. It downloads, and the sheet asks what it reads, In This Space or In All Spaces, and On All Sites It Asks For or When I Click It. After Add, the puzzle button's list opens by itself with Dark Reader in it under "In Work", on, with nothing under its name.
- [ ] Dark Reader darkens example.com in Work only. In Personal it is in the list, off, and the page stays light.
- [ ] The puzzle button shows the extensions on in the space as glass tiles, four to a row, names under them; a tile darkens under the pointer and gives a little as it is pressed. Click one: the panel closes and its popup opens in a pane at the page's corner nearest the puzzle button, at its own size, and takes the keys; Esc, ×, another tab and another space put it away, and the keys go back to the page. Drag a tile before another: the order holds after a relaunch, in Manage Extensions and in Settings › Extensions. Right-click a tile, or hold it: its options, or its page.
- [ ] Manage Extensions: each row's switch is just before its chevron, and the whole row, switch included, highlights under the pointer; the row opens the extension's page (Use in This Space, Site Access, Version, which copies its number and says "Copied", Report a Problem…, removal last). Back comes back the way it went.
- [ ] Bitwarden, with the Bitwarden desktop app installed and unlocked: the extension unlocks with the app (biometrics), and fills a sign-in on a site. Its side panel opens beside the page.
- [ ] 1Password, with the 1Password app: its popup says it is connected to the app.
- [ ] uBlock Origin Lite: ads on a news site are blocked in the space it is on in, not in the other.
- [ ] Sign in to a site in Work with an extension that keeps a sign-in of its own (Bitwarden): Personal's copy of it is signed out.
- [ ] accounts.google.com: no extension's content script runs (Dark Reader leaves it light), no extension's items are in the page's menu, and clicking an extension in the list grants it nothing there.
- [ ] An extension that can't run on this Mac shows "Incompatible", with a warning triangle where its switch was; its … menu has This Looks Wrong, which brings the switch back, off.
- [ ] Report a Problem… shows the report in full, names no site and no account, and Copy and Save… work. Nothing is sent.
- [ ] Remove from This Space, then on again: its settings in that space are gone, the other space's are not. Remove from Safience asks first.
- [ ] Settings › Extensions: each extension's site access and its switch in each space; Check Now says "Everything is up to date." or how many it updated (an update it declined or that failed its trial isn't counted).
- [ ] Two Macs signed in to the same iCloud, sync on: an extension added on one is offered on the other under On Your Other Macs; Add shows that Mac's own sheet, and it goes on in the spaces it is on in on the first Mac too. Turned off in a space on one, it goes off on the other. Removed on one, it goes from the other. Don't Offer on This Mac stops an offer. In the CloudKit Console, the Extension and ExtensionUse records' fields are encrypted and their names say nothing about the extension; an open Chrome Web Store page isn't in the other devices' lists of open tabs.
- [ ] Narrow window (640 points), sidebar wide: the side panel narrows, then goes until there is room.

## 19. Peek and little windows on a Mac

Two spaces, Work and Personal; Figma pinned in Work and signed in there only.

- [ ] A site's Sign in with Google or Apple button (on a site that opens it as a pop-up): the sign-in opens in a Peek over the tab, at the size the site asked for, the tab dimmed behind it; it closes by itself once signed in, the site is signed in, and the keys are the page's again.
- [ ] In the pinned Figma tab, a link to github.com opens in a Peek, nearly the card's size; a link to help.figma.com stays in the tab; ⌘-click on the GitHub link still opens a tab behind. Settings › General › Links › Open other sites from pinned tabs in Peek off: the link goes in the tab, as before.
- [ ] A link's menu has Open Link in Peek after Open Link in New Tab; chosen, the link opens in a Peek over the tab. Not on accounts.google.com, nor in a Peek or a little window.
- [ ] A Peek goes with a click on the dimmed card beside it, its ×, and ⌘W, which leaves the tab open. A pop-up the Peek's page opened goes with it. Another tab and back: the Peek is where it was. Closing the tab closes it.
- [ ] ⌃⌥O, or the Peek's expand button: its page is a tab right after the one it came from, on screen, as it was in the Peek (scrolled, signed in, a form half filled), with no reload, and History (⌘Y) lists it; a sign-in page it was on is not listed. From an ordinary tab, the split button puts it beside that tab in Split View; from a pinned tab the button isn't there.
- [ ] Back in the Peek's header shows once it has gone on to a second page, and goes back.
- [ ] With Safience the default browser, a link clicked in Slack, Mail or Messages opens in a little window over the app in front, in the space of the browser window in front, signed in as that space is; the window's ground is that space's colour, its close, minimise and zoom buttons on the header's line, and its header drags the window. A second link opens a second little window, a step down and along.
- [ ] In a little window, ⌃⌥O, or the expand button: the page is a tab of a browser window showing that space, as it was, with no reload, and in History; the little window goes. The arrow beside it lists the spaces; Personal opens the page there, afresh and signed out of what only Work is signed in to.
- [ ] ⌃⌥N: an empty little window with its address field taking the keys; an address or a search, and Return, go there. A click on the address, or ⌘L, shows the whole address to change; Escape leaves it as it was.
- [ ] In a little window, ⌘W and ⇧⌘W close it and no browser tab; ⌘R reloads it; ⇧⌘C copies its link; a ⌘-click opens a tab of its space in a browser window behind; a pop-up opens over it in a window of its own.
- [ ] Settings › General › Links › Links from other apps open in A New Tab: a link from Slack opens in a new tab of the window in front, as before.
- [ ] Light and dark, Reduce Transparency, and VoiceOver: the Peek reads as "Peek" with its buttons named, and Escape from VoiceOver closes it.
