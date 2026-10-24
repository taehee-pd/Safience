# Safience remediation and release plan

Revised 23 October 2026. Current scope: unreleased fixes in an open PR, with no version bump or new build publication.

The 67 original UX findings and 17 additional safety findings now have implementation changes or a verified correction to the original interpretation. Completion of source work is separate from acceptance on real devices, accounts and assistive technologies. The evidence ledgers below name those limits per item.

## Current baseline

- PRs 43 through 48 were reviewed, corrected and merged through PR 49. PR 50 added the first safety fixes. PR 51 distributed 1.0.6 (36). PR 52 fixed blocked macOS startup during legacy-data migration and clipped page viewports; 1.0.7 (37) is published.
- The original checkout and its signing/project/scheme edits are preserved. All continuation work uses an isolated checkout and synthetic validation data.
- Open [PR 78](https://github.com/taehee-pd/Safience/pull/78) contains the broader audit remediation plus the newly reported window and Chrome extension defects. Version/build remain 1.0.7 (37); these changes are Unreleased. Its verification record is [RemediationValidation-2026-10-23.md](RemediationValidation-2026-10-23.md).
- [The baseline review](UXRemediationBaselineReview-2026-10-23.md), [PR review record](PRReview-2026-10-23.md) and [PR 50 safety review](UXSafetyReview-2026-10-23.md) retain historical findings. Their earlier open-status lists are superseded by this plan and current ledgers.

## Implementation and evidence

| Area | Current behavior | Evidence and acceptance limits |
| --- | --- | --- |
| Retained work | Failed workspace/history/download-index reads remain unavailable until recovery. Ordered workspace saves acknowledge committed revisions; failed saves expose Retry/export. Mac quit waits for saving or an explicit choice. History clearing commits before completion. | [Native and persistence ledger](UXResolutionEvidence-2026-10-23.md), [recovery ledger](UXRecoveryExtensionsEvidence-2026-10-23.md). Fault-injected storage tests and native save-failure recovery pass. Mac quit failure choices and actual storage exhaustion still need native acceptance. |
| Space and account boundaries | Remote unpin preserves live tabs. Last-space deletion creates a fresh identity. Equal names never merge automatically. Account changes pause sync until a saved choice. A workspace gate survives failed separate consent/state writes; explicit approval detaches identities and acknowledges its removal. History visits carry immutable upload epochs and separate metadata snapshots, so unverified or legacy visits remain local-only. | [Boundary ledger](UXBoundaryEvidence-2026-10-23.md). Focused policy, real SQLite failure/relaunch, workspace-save and native metadata-origin fixtures pass. Extension configuration also waits for the durable workspace gate before its separate file is saved. The final 698-test core suite and macOS/iOS Simulator SDK builds pass. Two-device CloudKit replay and live account switching remain unverified. |
| Moving and restoring tabs | Move explains reload/sign-in/draft loss and offers Open a Copy/Cancel. Cache keys include space, tab and address, with callback generations. Rich editors, observable canvases and unknown frames stay live under memory pressure. | [Transfer ledger](UXRecoveryExtensionsEvidence-2026-10-23.md), [core safety coverage](UXResolutionEvidence-2026-10-23.md). Canvas/browser/native probes pass. Reopening a URL cannot recover arbitrary JavaScript state after process death. |
| Reachable navigation | Visible space management, New Space in Settings, retained address bar when tabs are hidden, counted All Tabs, explicit command Go/Search/Cancel, and narrow Split View Switch/Exit controls. | [Native ledger](UXResolutionEvidence-2026-10-23.md). Touch and largest-text routes exercised on isolated iPhone/iPad simulators; physical keyboard and human screen-reader tasks remain separate. |
| Recovery and feedback | Durable download activity and supported Retry/Resume, attempted-address failure recovery, popup states, bounded authentication attempts, external-request review and typed Send to App failures. | [Recovery ledger](UXRecoveryExtensionsEvidence-2026-10-23.md). Model/storage fault tests and SDK builds pass. Real authenticated/resumable downloads and native external-handler journeys remain acceptance checks. |
| Accessible controls and motion | Semantic/scaled type, 44-point iOS targets, separate tab/menu controls, selected-row outlines, state-specific command names, human icon names and reduced-motion tab/press behavior. | [Native ledger](UXResolutionEvidence-2026-10-23.md). Automated accessibility queries do not establish human VoiceOver, Full Keyboard Access, measured contrast or physical motor access. |
| Trackpad View | Persistent help, Exit/zoom/keyboard controls, remembered minimap placement, gesture feedback and normal-browsing fallback for unsupported assistive input. Routine haptics removed. | [Boundary ledger](UXBoundaryEvidence-2026-10-23.md). Native controls and Chromium/WebKit bridge fixtures pass; real sites and physical assistive input remain unverified. |
| Settings, setup and language | Native Settings categories/Shortcuts page; import Retry/another-file outcomes; explicit setup skipping and save acknowledgement; primary commands, settings and recovery strings in English/Korean with count pluralization. | [Boundary ledger](UXBoundaryEvidence-2026-10-23.md), [verification record](RemediationValidation-2026-10-23.md). Current catalog validation covers 372 bilingual keys and matching core resources. Legacy strings may remain English; this release does not claim complete Korean translation. |
| Mac extensions | Shared removal/permission scope, owned Settings dialogs, truthful update outcomes, persistent options/reorder controls, popup preparation and narrow-panel recovery. Current follow-up resolves Chrome localized names and reevaluates failures after compatibility-engine changes. | [Extension ledger](UXRecoveryExtensionsEvidence-2026-10-23.md). Are.na and Translate worker startup, localized package names and local language results are verified in the [focused extension ledger](ExtensionCompatibilityEvidence-2026-10-23.md). Notion cookie sign-in and authenticated posting remain unsupported or unverified as recorded there. No universal Chrome-extension compatibility claim. |
| Product claims | Store PNGs use current isolated native captures; scaled derivatives and archived Duo/previews are labelled. Privacy copy describes actual sync and optional provider requests. | [Native capture ledger](UXResolutionEvidence-2026-10-23.md), `Marketing/AppStore/README.md`. No new App Store screenshot upload or unverified Duo claim. |

## New reported regressions

| Report | Resolution and verification |
| --- | --- |
| DMG opens but app does not launch | 1.0.7 moves the legacy-data migration off the initial window path, exposes progress/retry and resumes checked staging. Signed/notarized artifacts and isolated launch verified. |
| Sidebar width clips the page | 1.0.7 makes native page holders follow available bounds; split panes get separate viewport widths. Native resize tests and real CSS-width probes verified. |
| Command-W closes the window | The PR replaces SwiftUI's default Close command group with Close Tab for browser windows. The last/empty tab case keeps its window; Shift-Command-W closes the window. Actual-source native menu fixture passes. |
| Opening Safience creates two windows | Reopen handling requested a window and also allowed the framework default. The startup follow-up owns a single request while preserving saved multiwindow restoration; the actual-source fixture passes 7/7 checks. Saved-window cold restoration remains unverified. |
| Are.na rejected and Chrome Store names show IDs | Current Are.na worker startup succeeds in isolated WebKit. Names resolve from the original locale catalogs and existing installations refresh automatically. Environment-specific failures and duplicate-error recovery have regression coverage; the missing language API used by Google Translate is supplied locally. Full sign-in/posting workflows are not claimed. |

## Complete finding ownership

Each ID below has a source disposition and evidence owner. A shared row does not imply every native acceptance case passed.

| Workstream | Original audit IDs | Additional findings | Evidence owner |
| --- | --- | --- | --- |
| Work and data | X5, X8, X9 | N1, N2, N3, N4, N5, N6, N7, N8, N10, N11, N12, N14 | Native, boundary and recovery ledgers |
| Navigation | X4, T1, T2, T3, T4, T6, T7, T8 | N17 | Native ledger |
| Status/recovery | O5, D1, D2, D3, D5, D6, D7, D8, D9, D10, D11 | N15 | Boundary and recovery ledgers |
| Accessible controls | X1, X2, X7, X10, X11, X12, O3, T5, T9, D4 | N16 | Native ledger |
| Trackpad View | P1, P2, P3, P4, P5, P6, P7, P8, P9, P10 | None | Boundary ledger |
| Mac extensions | M1, M2, M3, M4, M5, M6, M7, M8, M9, M10, M11, M12, M13 | None | Recovery ledger |
| Setup/language | X3, X6, X13, X14, O1, O2, O4, O6, O7, O8, O9, D12 | N9, N13 | Native, boundary and release records |

## Remaining acceptance

| Check | Current disposition |
| --- | --- |
| Human VoiceOver, Full Keyboard Access, Switch Control and physical keyboard profile | Source alternatives and isolated AX/component checks exist. Human end-to-end acceptance is still open. |
| Two-device sync, offline replay and real Apple Account changes | Durable policy and storage tests pass. No live account data was accessed. Dedicated test accounts/devices are required for live acceptance. |
| Full light/dark/increased-contrast matrix and rendered Reduce Motion interruptions | Source policies implemented; selected native states inspected. No complete contrast or animation certification. |
| Physical iPad multiwindow setup ownership and owner closure | Source guard exists; exact runtime coverage is recorded in the native ledger. |
| Native extension/site and download compatibility | Test the named affected packages and synthetic pages; retain explicit limits for unsupported APIs and real account workflows. |
| Duo/hinge screenshots, native 6.3-inch screenshots and new preview recordings | Outside verified current capture coverage. Published metadata excludes the unverified promises. |

## PR scope and validation

1. Held source includes the per-visit history scope, metadata-origin and workspace-approval repairs. Focused checks pass for write failures, queued retries and A/B/A relaunch; exact counts and logs are in the [verification record](RemediationValidation-2026-10-23.md).
2. The final core suite passes 698 tests. macOS Direct and universal iOS Simulator SDK builds both pass. Localization parity and final diff checks pass.
3. Open PR 78 contains the evidence and acceptance limits. Main's 1.0.7 (37) version/build remains unchanged.
4. Leave merging, release versioning and macOS/TestFlight publication for a later instruction. The earlier release request is superseded by this scope change.
