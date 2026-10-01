# Changelog

What changes in Safience from one version to the next, newest first. A change that fixes or adds something adds its line under **Unreleased** the day it is merged.

## Unreleased

### Added

- Safience, a WebKit browser for iPad, made for Figma and web apps used with a trackpad and keyboard. Pages are asked for in desktop mode as Mac Safari. A trackpad pinch and ⌘ with two fingers reach the page as ctrl+wheel at the pointer, as on a Mac, and two-finger scrolling is bridged when WebKit sends the page nothing; iPad's own page zoom, scrolling, swipe back and callouts are off. The system's ⌘ menus are gone, so ⌘Z, ⌘F and the rest are the page's; the browser's own shortcuts are all ⌃⌥, with a command palette on ⌃⌥K. Each space signs in with a WebKit store of its own; windows work with Stage Manager; one heavy tab stays live and other tabs freeze to a picture, loading again when opened, and a page whose process ends reloads by itself. Sign-in pages always show the address, and Google's sign-in is never touched: no script, no cookie read.

### Removed

- The Mac app this repository began as, Search by Office Commun: its sources, build and release scripts, tests, AI engine, installer, roadmap and release notes. It stays in the git history.
