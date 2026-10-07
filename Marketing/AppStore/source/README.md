# App Store screenshots

The pictures in `Marketing/AppStore` are the real app, captured in the simulator, set in Apple's own picture of the device with one line of copy; `Marketing/AppStore/previews` has the app previews, silent screen recordings of the app in use.

| Folder | Size | Captured in |
| --- | --- | --- |
| `Marketing/AppStore` (the iPad's) | 2064 × 2752 | iPad Pro 13-inch; or the iPad Air 13-inch, whose 2048 × 2732 capture the frame scales by under one percent |
| `iPhone-6.9` | 1320 × 2868 | iPhone 17 Pro Max |
| `iPhone-6.3` | 1206 × 2622 | the 6.9-inch pictures, scaled |
| `iPhone-Duo-inner` | 2007 × 2853 | iPad Pro 11-inch, cropped to the Duo's shape |
| `iPhone-Duo-outer` | 1398 × 2034 | iPhone 17 Pro Max, made shorter |

The Duo's are stand-ins, never seen on a Duo: Xcode 27.0 has no Duo simulator. Xcode 27.1 beta has one, folded and unfolded from Device Hub's buttons, and Apple's page says an app built with the 27.0 SDK runs there centred with empty space around it when open and beside the status bar when closed, while one built with the 27.1 SDK fills the display; so build with the 27.1 SDK, capture both postures in that simulator, and render the two Duo frame lists. Apple takes Duo screenshots now and requires them from April 2027 (developer.apple.com/iphone-duo/prepare, developer.apple.com/news/?id=kkphp5qo). Unfolded, the Duo is wider than 600 points, so it gets the iPad layout, and the iPad Pro 11-inch is the nearest screen. Folded, it gets the phone layout, so its pictures are the iPhone's cut to the shorter screen, the iPhone's bar laid over the bottom: the page under the bar's blur is this page's own, blurred by `duo-outer.py`, since the iPhone's is further down the page.

| File | What it is |
| --- | --- |
| `site/` | The demo web apps the app shows (Forma, Margin, Lanes and the rest): `*.src.html`, with `build.py` writing the served pages, and `icons/` the demo sites' icons, each under its host's name for the app's cache, and Forma's, Margin's and Lanes' also under the names their pages link (`forma.png`, and `localhost.png` for the Studio tab at that host) |
| `state.py` | Puts the simulator's app in one of the shots: `hero`, `split`, `client`, `start`, `palette`, `notes` |
| `cap.sh` | Quits the app, sets a shot with `state.py`, opens the app and captures it once its page is drawn (`ready.py`) or after a wait; `shot.sh` is the older form |
| `ready.py` | Says when an iPad 13-inch capture shows its page drawn |
| `duo-outer.py`, `duo-inner.py` | Make the Duo's stand-ins from the iPhone and iPad 11-inch captures |
| `raw/`, `raw-iphone/`, `raw-duo/` | The captures |
| `bezels.sh`, `bezels/` | Fetches Apple's pictures of the devices (Apple Design Resources, Product Bezels) into `bezels/`, which git leaves out: Apple's licence lets them be used in mock-ups for its platforms, not passed on |
| `frame.html` | The frame: the copy, Apple's picture of the device, and the capture in the hole it leaves for the screen, from the frames file's parameters (`bezel`, its size `bw` and `bh`, the screen's `hole` x,y,w,h and `corner` radius in it, and `sw`, the screen's width on the picture) |
| `frames.json`, `frames-iphone.json`, `frames-duo-inner.json`, `frames-duo-outer.json` | Each set's size, folder, and each shot's capture and line of copy |
| `render.mjs` | Renders a set in WebKit into `Marketing/AppStore` |
| `asc.py` | Puts the sets and the previews on the version in App Store Connect through its API, and the build once it has processed: `python3 asc.py state`, `screenshots`, `previews`, `build 8`, with `ASC_KEY_PATH`, `ASC_KEY_ID` and `ASC_ISSUER_ID` set. App Store Connect's own uploader needs a file picker, which no browser here has |
| `tighten.py` | Cuts the waiting out of a screen recording: stretches where nothing moves become a short hold |
| `preview.sh` | A simulator recording as App Store Connect takes an app preview: the size, 30 frames a second, H.264, a silent stereo track |

## Again from scratch

0. `./bezels.sh` once, for the devices' pictures.
1. Serve the demo pages: `python3 site/build.py`, then `python3 -m http.server 8765 --bind ::` in `site/`.
2. Copy `site/icons/*` into the app's `Library/Caches/Safience/SiteIcons` in the simulator (`xcrun simctl get_app_container <device> net.taehee.safience data`).
3. Clock and status bar: set the simulator to `en_US` with a 12-hour clock (`xcrun simctl spawn <device> defaults write -g AppleLocale en_US`, `AppleICUForce12HourTime -bool true`, `AppleICUForce24HourTime -bool false`), restart it, then `xcrun simctl status_bar <device> override --time 2026-10-03T00:41:00.000Z --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState discharging --batteryLevel 100`. The iPad Pro 11-inch shows the wrong weekday for that date; `duo-inner.py` redraws it.
4. For each shot: `./cap.sh <device> <shot> <capture> [ready mode | seconds]`. The palette shot is the hero with the palette opened (⌃⌥K, the ⌘ button, or on iPhone the page's menu), "tab" typed and, on iPad, the keyboard hidden. The iPhone's second shot is the notes page with the page's menu open.
5. `PLAYWRIGHT=<path to playwright/index.mjs> node render.mjs <frames file>`, or with the `playwright` package installed, `node render.mjs <frames file>`. Without a frames file it renders the iPad's.

The workspace these scripts edit is the one the simulator's app already has: three spaces (Studio, Client, Personal) whose tabs point at the demo pages.

## App previews

Silent screen recordings of the app in use, one for the iPhone (886 × 1920) and one for the iPad (1200 × 1600), 15 to 30 seconds, in `Marketing/AppStore/previews`. App Store Connect scales the iPhone's for the smaller iPhones.

1. Put the app in the hero shot (`cap.sh <device> hero /dev/null 5`), touch the simulator once so it is awake (its first touch after a while can take a minute to land), and open every tab and space the recording will show once, then come back to the hero: a tab opened for the first time in a run is white for a few seconds while its page loads, and after a visit it has a picture to show instead. On the iPad, leave the Client space on its board.
2. `xcrun simctl io <device> recordVideo --codec h264 --force <recording>.mov`, use the app by hand (the iPhone's: swipe up on the bar for the tabs, open the notes page, scroll, Desktop View from the page's menu, move the cursor, leave it, throw a tab away; the iPad's: tabs, split view, the palette, a space, a new tab), then stop the recording with control-C.
3. `python3 tighten.py <recording>.mov <tight>.mov 1.0 30`: the waits between touches go, the motion keeps its pace. It says how long is left; over 30 seconds, hold less or do less.
4. `./preview.sh <tight>.mov ../previews/iPhone-6.9.mp4 iphone`, or `ipad` for `iPad-13.mp4`.
