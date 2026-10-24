> Historical PR 50 review. The remaining-source-work list below is superseded by [the current remediation plan](UXRemediationPlan.md) and its evidence ledgers. The later canvas regression record is retained here.

# Safience safety implementation review

Date: 2026-10-23
Base: merged main `cf418e4`, including PR #49 and original PRs #43 through #48.
Branch: `codex/ux-safety-fixes`. Publication and merge record: [PR #50](https://github.com/taehee-pd/Safience/pull/50).

There were no new open PRs when this continuation began. The previous review covered all 49 PR records through the integration; this pass inspected the remaining safety journeys and applies the first fixes in the revised plan. It does not claim a new line-by-line audit of every historical PR.

## Native workflow and evidence

Safience is a browser workspace. Windows own focus/presentation; spaces own sign-ins, tabs, bookmarks and pins. Targets are iOS/iPadOS 17 and later plus macOS 26 and later, with UIKit/SwiftUI and AppKit/SwiftUI respectively. Touch, pointer, keyboard and native accessibility behavior need separate acceptance.

Applied the requested apple-native-ui, write-swift, better-ui, 12-principles-of-animation, ux-audit, better-writing and ui-skills-root guidance. UI Skills category lookup selected `dimillian/swiftui-ui-patterns`. The UX audit's trust/recovery criteria informed native journey tracing; its web route/click-count recipes were not treated as native evidence.

Current [Apple alert guidance](https://developer.apple.com/design/human-interface-guidelines/alerts) supports actionable recovery in context. The startup failure uses a persistent recovery screen. [WKWebView interactionState](https://developer.apple.com/documentation/webkit/wkwebview/interactionstate) supports restoring opaque navigation state; it is not a promise to preserve every site's JavaScript editor or survive process loss.

## Changes by root cause

| Severity | Location | Before | After | Why |
|---|---|---|---|---|
| HIGH | `PadCore/Sources/PadCore/Workspace.swift:771`, `App/Sources/Session.swift:134`, `Mac/Sources/Session.swift:170`, `Shared/WorkspaceRecoveryView.swift:6` | Failed reads created replacement identities, then startup cleanup could remove retained records. | Distinct load outcomes, native recovery gate, protected last-good backup and guarded services. Explicit restore archives original JSON, history/sidecars and snapshots before cleanup. | Preserve work and provide an actionable error; invalid source bytes are never silently overwritten. |
| HIGH | `PadCore/Sources/PadCore/PageSnapshotFiles.swift:55`, `App/Sources/Pages.swift:174`, `Mac/Sources/Pages.swift:122` | Tab-only disk caches and late callbacks survived moves; old frozen state could win after live navigation/relaunch. | Space/tab scope, URL checks, queue ordering, one-shot consumption and generation invalidation. | Sign-in/context boundaries and restoration must agree. |
| HIGH | `PadCore/Sources/PadCore/Scripts/draft.js:10`, `App/Sources/Pages.swift:210`, `Mac/Sources/Pages.swift:110`, `Mac/Sources/Page.swift:581` | Rich editors were missed, Mac never checked drafts, and pressure could bypass the iOS check. | Shared standalone read-only probe; rich/hidden/empty editors, changed fields, observable canvases and unknown frames stay live. Pressure does not override protection. | Closing a page must not silently discard recognizable work. |
| HIGH | `App/Sources/Browser.swift:461`, `App/Sources/AppDelegate.swift:79` | Closing the setup window left a global lock held. | Weak owner, owner-only release, foreground resumption. | Multiwindow cancellation must leave setup usable. |
| HIGH | `Mac/Sources/Page.swift:1153` | A background page could present an app-modal JavaScript dialog over unrelated work. | Only a showing host window may present its sheet; offscreen callbacks complete safely. | Presentation belongs to the originating visible window. |
| HIGH | `App/Sources/TabOverview.swift:545` | Reduce Motion still scaled presses and threw/bounced cards across the window. | 150 ms press fades and reduced-motion release fades/cross-fades; normal completion at most 250 ms. | Respect the motion setting without losing direct manipulation or close completion. |
| HIGH | `Mac/Sources/BrowserView.swift:156` | Custom command overlay had no modal AX boundary or overlay-level accessible cancellation. | Modal trait, background AX exclusion, named Close/Escape actions and container-level cancellation restore page focus. | Keyboard and assistive-technology dismissal must be part of the overlay contract. |
| MEDIUM | `Mac/Sources/Session.swift`, workspace write queue | Older concurrent saves could finish after termination's latest save. | Delayed and termination writes share one serial queue. | Ordering protects the last acknowledged state; error acknowledgement remains N2 work. |

The recovery review found and corrected two defects before publication: extension startup after a late restore missed the launch notification, and restoring an older backup could prune newer history before preserving it. The draft review also found that Mac has no installed iPad bridge; Mac now evaluates the shared probe directly in its named content world.

## Motion rule summary

| Rule | Root causes fixed | Native scope |
|---|---|---|
| `timing-under-300ms` | 1 | Tab-card release and press paths inspected. |
| `physics-subtle-deformation` | 1 | Normal pressed scale is 0.96; Reduce Motion uses opacity. |
| Reduced-motion contract | 1 | Card and pinned-cell press feedback and released-card transitions. |

No claim is made about animation paths outside those inspected controls. Rendered motion and haptics remain unverified.

## Verification

Core and browser results are complete. Native builds cover unsigned macOS Debug, iOS Simulator Debug and iOS device Release; signing and real-device installation are excluded. Only synthetic data and temporary stores are used. The separate simulator app ID is `net.taehee.safience.UXReview`; the developer's normal app/container is not used.

- Full PadCore: 485 XCTest tests and 84 Swift Testing tests pass, with no exclusions.
- Chromium and WebKit: 140/140 each. Native nonpersistent WKWebView in the named Safience world: 5/5. PiP: 5/5. Extension shim: 43/43.
- Focused recovery regressions cover missing/unreadable/invalid/future data, legacy compatibility, refused overwrites, previous-valid backups, rejected recovery candidates and retained-file archives.
- Snapshot regressions cover space boundaries, stale tokens, URL mismatches, queued state consumption, relaunch and legacy cache pruning.
- Browser regressions exercise both the installed iOS API and the standalone Mac probe, including no-global/no-listener behavior.
- Focused N11 canvas follow-up reproduces seven canvas failures before the guard. The updated checks cover blank/drawn/hidden canvases, open shadow roots, same-origin frames, unchanged pixels/private state and eligibility after canvas removal. Chromium and WebKit each pass 152/152. Native nonpersistent WebKit in the named Safience world passes 8/8, including three new canvas checks. An initial Chromium run passed all canvas checks but failed the existing trusted-wheel timing check; the rerun passed. The timing-failure log is `/private/tmp/safience-n11-canvas-chromium-wheel-timing.log`. Logs: `/private/tmp/safience-n11-canvas-{chromium,webkit,native}.log`; isolated harness: `/private/tmp/safience-native-draft-canvas-probe.swift`.
- A synthetic corrupt-workspace iPhone 17e simulator launch renders the recovery screen; source JSON, history and snapshot sentinels remain byte-for-byte unchanged. A largest-accessibility-text render exposed inefficient header wrapping and action placement; the final screen uses a full-width heading and puts recovery actions before secondary help. Retry, Restore Backup and Choose Backup replace the long action labels that clipped at the largest text size.

Local logs: `/private/tmp/safience-ux-safety-padcore-final.log`, `/private/tmp/safience-n11-standalone-chromium.log`, `/private/tmp/safience-n11-standalone-webkit.log`, `/private/tmp/safience-n11-native-draft.log`, and `/private/tmp/safience-ux-safety-{macos,ios,ios-release}-final.log`. Simulator renders: `/private/tmp/safience-recovery-iphone-final.png` and `/private/tmp/safience-recovery-iphone-large-text-final.png`.

## Remaining findings and limits

| Severity | Location | Remaining work |
|---|---|---|
| HIGH | `App/Sources/Session.swift`, `Mac/Sources/Session.swift`, N2 | Durable write failures still need visible status, Retry and quit behavior. |
| HIGH | Plan N4, N6, N7, N9, N10, N14 | Deletion semantics, same-name joins, account changes, import outcomes, history-store errors and partial-address suggestion policy remain open. |

Every observable canvas is now retained as unknown, including blank/hidden canvases and those in open shadow roots or same-origin frames. The probe does not recover canvas pixels or private app state. Closed shadow roots and private JavaScript state without an observable editor/canvas remain uninspectable; the OS can still terminate a process. Conservative editor/canvas/iframe detection can retain already-saved pages and increase memory use. Legacy unscoped snapshots are removed once and those tabs reopen at their saved URLs. Archive copies protect older recovery data but do not automatically merge an older backup's missing spaces/history into the restored workspace.

Not verified: VoiceOver, Full Keyboard Access, native freeze/thaw/move/Back, two-device sync, multiwindow onboarding, interrupted native gestures, recovery file-picker interaction, signing and installation on a real device. Runtime coverage is limited to iPhone 17e recovery renders at default and largest accessibility text sizes, byte-preservation checks, and the standalone WebKit probe. Scrolling and action activation at the largest text size were not automated.

Block. Remaining HIGH findings and native acceptance checks prevent a release approval. The code changes improve the reviewed paths and do not certify the entire app.
