# App Store screenshots

The current iPad and iPhone PNG sets were regenerated on 2026-10-23 from the remediation source. The captures show the actual native interface in a separate QA app with fresh synthetic spaces. Forma, Margin, Lanes, Post and Week are repository demo pages served locally. Their pages and original icons are preserved.

## Current coverage

| Folder | Output size | Capture provenance |
| --- | --- | --- |
| `Marketing/AppStore/` | 2064 x 2752 | Current native iPad Pro 13-inch (M5) simulator, iPadOS 27.0. |
| `Marketing/AppStore/iPhone-6.9/` | 1320 x 2868 | Current native iPhone 17 Pro Max simulator, iOS 27.0. |
| `Marketing/AppStore/iPhone-6.3/` | 1206 x 2622 | Existing renderer's scaled derivative of the current 6.9-inch set. This is not a separate 6.3-inch device capture. |
| `Marketing/AppStore/iPhone-Duo-inner/` | Historical stand-ins | Archived iPad-based composites. Not current Duo posture captures; excluded from current coverage. |
| `Marketing/AppStore/iPhone-Duo-outer/` | Historical stand-ins | Archived shortened iPhone composites. Not current Duo posture captures; excluded from current coverage. |
| `Marketing/AppStore/previews/` | Historical videos | Not recaptured for this source. Excluded from current visual verification. |

No current folded/unfolded Duo capture is claimed. A Duo simulator exists locally, but this run did not validate its postures, hinge transitions, system strip or viewport behavior. The App Store description omits the unverified Duo behavior promise. Do not present the archived Duo images or previews as current capture evidence.

## Files and reproduction

| File | Purpose |
| --- | --- |
| `raw-current/ipad/`, `raw-current/iphone/` | Current unframed native captures. Five feature shots plus a notes reference per platform. |
| `raw-current/manifest.json` | Device coverage, QA provenance, source checkpoint and image hashes. |
| `site/` | Original synthetic demo pages and icons. The current run used distinct `*.localhost:9426` hosts, so each site retains its own icon. |
| `frame.html`, `frames.json`, `frames-iphone.json` | Existing frame layout, current capture inputs and current feature copy. The iPhone frame list also emits the scaled 6.3-inch set. |
| `render.mjs` | Renders the existing HTML frames in WebKit, writes opaque PNGs and creates the declared scaled derivatives. |
| `bezels/`, `bezels.sh` | Apple's licensed local device artwork. The current run reused existing local iPad/iPhone artwork; these ignored assets are not redistributed. |
| `state.py`, `cap.sh`, `shot.sh` | Legacy production-bundle capture helpers. They were not used for the current captures and must be adapted to a separate QA bundle/data root before reuse. |
| `frames-duo-*.json`, `duo-*.py` | Historical stand-in production files. They are not inputs to the current render. |
| `asc.py` | App Store Connect uploader. Local capture/render verification does not authorize an upload. Current screenshot sets are iPad 13-inch and iPhone 6.9/6.3 only. |

The current native tests used bundle `net.taehee.safience.RemediationQA`, `SAFIENCE_ISOLATED_QA=1`, and fresh absolute `/private/tmp/SafienceMarketingQA/...` roots. Sync, remote suggestions and filter downloads were off. Local HTTP pages correctly show an unsecured-site indicator. No signed-in user site, production app container, Apple Account or real workspace was captured.

See `Docs/UXResolutionEvidence-2026-10-23.md` for native route results and acceptance gaps. Capture fixtures and the temporary XCUITest runner are local evidence under `/private/tmp/safience-remediation-ui`; the tracked raw PNGs make frame rendering reproducible without reopening the app.

With matching Playwright/WebKit installed and the licensed bezels present:

```sh
PLAYWRIGHT=/absolute/path/to/playwright/index.mjs node Marketing/AppStore/source/render.mjs frames.json
PLAYWRIGHT=/absolute/path/to/playwright/index.mjs node Marketing/AppStore/source/render.mjs frames-iphone.json
```

The renderer's inputs are `raw-current`, not the historical `raw`, `raw-iphone` or Duo composites. All current framed PNGs were opened for visual review. Pixel dimensions and opacity were checked after rendering. No App Store upload was performed.
