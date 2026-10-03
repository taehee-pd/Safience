# App Store screenshots

The five pictures in `Marketing/AppStore` are the real app, captured in the iPad Pro 13-inch simulator, set in a frame with one line of copy.

| File | What it is |
| --- | --- |
| `site/` | The demo web apps the app shows (Forma, Margin, Lanes and the rest): `*.src.html`, with `build.py` writing the served pages, and `icons/` the demo sites' icons |
| `state.py` | Puts the simulator's app in one of the shots: `hero`, `split`, `client`, `start`, `palette` |
| `ready.py` | Says when a capture shows its page drawn |
| `raw/` | The captures, 2064 × 2752 |
| `frame.html`, `frames.json` | The frame and each shot's line of copy |
| `render.mjs` | Renders the frames in WebKit into `Marketing/AppStore` |

## Again from scratch

1. Serve the demo pages: `python3 site/build.py`, then `python3 -m http.server 8765 --bind ::` in `site/`.
2. Copy `site/icons/*` into the app's `Library/Caches/Safience/SiteIcons` in the simulator (`xcrun simctl get_app_container <device> net.taehee.safience data`).
3. Status bar: `xcrun simctl status_bar <device> override --time 2026-10-03T00:41:00.000Z --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState discharging --batteryLevel 100`.
4. For each shot: quit the app, `python3 state.py <container> <shot>`, launch it, wait for `ready.py`, capture with `xcrun simctl io <device> screenshot raw/<n>-<shot>.png`. The palette shot is the hero with ⌃⌥K, "tab" typed and the keyboard hidden.
5. `PLAYWRIGHT=<path to playwright/index.mjs> node render.mjs`, or with the `playwright` package installed, `node render.mjs`.

The workspace these scripts edit is the one the simulator's app already has: three spaces (Studio, Client, Personal) whose tabs point at the demo pages.
