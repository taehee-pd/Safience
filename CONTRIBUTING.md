# Contributing

Small, focused changes are the easiest to take: one thing per pull request, readable start to finish. For anything bigger, open an issue first to say what you want to change and why.

## Building and testing

- Open `Safience.xcodeproj` in Xcode 16 or later. Your team ID goes in `Config/Local.xcconfig`, which git ignores (see README).
- After adding or removing a file, run `xcodegen` at the root and commit the regenerated project with your change.
- `cd PadCore && swift test`: the app's logic, on macOS or Linux.
- `node Tests/bridge.mjs`: the script that goes into pages, in a browser (needs Playwright).
- On an iPad, [Validation/CHECKLIST.md](Validation/CHECKLIST.md) covers what only a device can show.
- Builds clean: no warnings you introduced.

## What keeps Safience what it is

- **The page gets the input.** A key or a gesture the system takes from a page is a bug, unless iPadOS keeps it for itself. The browser's own shortcuts are ⌃⌥ only.
- **Hands off Google's sign-in.** On a host in `HandsOff.swift`, no script of ours runs, no JavaScript is called and no cookie is read. Calls into pages go through `Page.swift` only, and `PolicyTests` reads the source to keep it that way.
- **A site's needs go in its adapter** (`PadCore/Sources/PadCore/Adapters.swift`), not in the app.
- **No dependencies** beyond Apple's frameworks. XcodeGen and Playwright are tools for developers, not part of the app.
- **Nothing leaves the iPad** but the pages you open: no analytics, no telemetry, no server.
- **Comments say why**, not what the next line does. Read a couple of files before adding a new one. No force-unwraps on anything that can plausibly fail.
- **No real key or token anywhere**: in code, a test, an issue or a pasted log. `gitleaks git --pre-commit --staged` with the repository's `.gitleaks.toml` catches most before a commit.
- **A change that fixes or adds something adds its line** under Unreleased in [CHANGELOG.md](CHANGELOG.md).

## Reporting a bug

Open an issue with what you did, what you expected, what happened instead, your iPad and its iPadOS version, and the site. A screenshot of the Diagnostics panel (⌃⌥D) on the page helps with anything about the trackpad or the keyboard.
