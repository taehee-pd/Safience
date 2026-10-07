# App Store screenshots

The pictures in `Marketing/AppStore` are the real app, captured in the simulator, set in a frame with one line of copy.

| Folder | Size | Captured in |
| --- | --- | --- |
| `Marketing/AppStore` (the iPad's) | 2064 × 2752 | iPad Pro 13-inch |
| `iPhone-6.9` | 1320 × 2868 | iPhone 17 Pro Max |
| `iPhone-6.3` | 1206 × 2622 | the 6.9-inch pictures, scaled |
| `iPhone-Duo-inner` | 2007 × 2853 | iPad Pro 11-inch, cropped to the Duo's shape |
| `iPhone-Duo-outer` | 1398 × 2034 | iPhone 17 Pro Max, made shorter |

The Duo's are stand-ins: Xcode has no Duo simulator yet. Unfolded, the Duo is wider than 600 points, so it gets the iPad layout, and the iPad Pro 11-inch is the nearest screen. Folded, it gets the phone layout, so its pictures are the iPhone's with the page cut where a shorter screen cuts it (`duo-outer.py`). Capture them again on a Duo simulator once there is one.

| File | What it is |
| --- | --- |
| `site/` | The demo web apps the app shows (Forma, Margin, Lanes and the rest): `*.src.html`, with `build.py` writing the served pages, and `icons/` the demo sites' icons |
| `state.py` | Puts the simulator's app in one of the shots: `hero`, `split`, `client`, `start`, `palette`, `notes` |
| `shot.sh` | Quits the app, sets a shot with `state.py`, opens the app and captures it once its page is drawn |
| `ready.py` | Says when an iPad 13-inch capture shows its page drawn |
| `duo-outer.py`, `duo-inner.py` | Make the Duo's stand-ins from the iPhone and iPad 11-inch captures |
| `raw/`, `raw-iphone/`, `raw-duo/` | The captures |
| `frame.html` | The frame: the copy, the device and its screen's shape, from the frames file's parameters |
| `frames.json`, `frames-iphone.json`, `frames-duo-inner.json`, `frames-duo-outer.json` | Each set's size, folder, and each shot's capture and line of copy |
| `render.mjs` | Renders a set in WebKit into `Marketing/AppStore` |

## Again from scratch

1. Serve the demo pages: `python3 site/build.py`, then `python3 -m http.server 8765 --bind ::` in `site/`.
2. Copy `site/icons/*` into the app's `Library/Caches/Safience/SiteIcons` in the simulator (`xcrun simctl get_app_container <device> net.taehee.safience data`).
3. Clock and status bar: set the simulator to `en_US` with a 12-hour clock (`xcrun simctl spawn <device> defaults write -g AppleLocale en_US`, `AppleICUForce12HourTime -bool true`, `AppleICUForce24HourTime -bool false`), restart it, then `xcrun simctl status_bar <device> override --time 2026-10-03T00:41:00.000Z --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState discharging --batteryLevel 100`. The iPad Pro 11-inch shows the wrong weekday for that date; `duo-inner.py` redraws it.
4. For each shot: `./shot.sh <device> <shot> <capture>`. The palette shot is the hero with the palette opened (⌃⌥K, the ⌘ button, or on iPhone the page's menu), "tab" typed and, on iPad, the keyboard hidden. The iPhone's second shot is the notes page with the page's menu open.
5. `PLAYWRIGHT=<path to playwright/index.mjs> node render.mjs <frames file>`, or with the `playwright` package installed, `node render.mjs <frames file>`. Without a frames file it renders the iPad's.

The workspace these scripts edit is the one the simulator's app already has: three spaces (Studio, Client, Personal) whose tabs point at the demo pages.
