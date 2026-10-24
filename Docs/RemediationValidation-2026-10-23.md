# Unreleased remediation validation

Date: 23 October 2026. Status: final source checks complete for open PR 78; acceptance limits remain below. The user requested no version bump and no new build publication. Source retains main version 1.0.7 (37).

## Source and scope

Worktree: isolated `codex/resolve-open-audit-items`, based on merged PR 52. The original checkout and local signing/project/scheme edits are preserved. No production app or real CloudKit account is used for synthetic acceptance.

The [current remediation plan](UXRemediationPlan.md) maps all 84 audit IDs. Focused startup/language evidence is in the [startup and extension ledger](UXStartupExtensionsEvidence-2026-10-23.md). Detailed implementation and acceptance limits are in the [native ledger](UXResolutionEvidence-2026-10-23.md), [boundary ledger](UXBoundaryEvidence-2026-10-23.md) and [recovery/extension ledger](UXRecoveryExtensionsEvidence-2026-10-23.md).

## Current verification

| Check | Result |
| --- | --- |
| Durable history/account boundary | Current held source passes 8 per-visit SQLite eligibility tests and 18 workspace/account-choice XCTest cases. They cover denied consent/state writes with writable local storage, stale A/B/A relaunch, queued Retry, same-URL metadata, legacy migration and failed/stale workspace-gate removal. Native description-origin admission passes 28 checks; complete bridge fixtures pass 153/153 in Chromium and WebKit. The final core suite and both platform SDK builds pass. See the focused records below. |
| Canvas protection | Chromium 152/152, WebKit 152/152, native named-world nonpersistent WebKit 8/8. Blank, hidden, drawn and observable framed/shadow canvases remain live. |
| Korean resources | 372 bilingual catalog entries and 372 core keys with matching placeholders verified by `Validation/localization.py`. Core localization/plural tests pass. Integrated iPad Settings, History/Cancel and corrupt-workspace Retry routes pass in Korean; legacy toolbar AX labels remain English. |
| Command-W | Actual production Close commands and closeTab method in native SwiftUI fixture: 8/8 pass, including last tab, field-editor focus, empty selection and explicit Shift-Command-W. `Validation/mac-close-commands.sh`. |
| Reopen window creation | Actual-source native fixture passes 7/7, including rapid repeated reopen and two intentional windows. Baseline reproduced two windows. Cold saved-window restoration is not runtime verified. `Validation/mac-startup-windows.sh`. |
| Native iPhone/iPad tasks | Existing isolated save failure/Retry/export, damaged history, New Space, counted All Tabs, hidden-tab recovery, narrow split, loaded-address editing and largest-text command routes pass. Exact coverage and device skips remain in the native ledger. |
| Chrome extension names/language | Actual Are.na2.14.3, Notion0.2.20 and Translate2.0.18 archives resolve human names, with Korean Translate verified. Missing i18n.detectLanguage is supplied locally; shim55/55 and native language14/14 pass. Native tab sampling preserves the Page/HandsOff access policy. Sixteen focused name/environment/recovery tests pass. Duplicate historical errors cannot establish a failed restart; only its own confirmed failure can. Actual Are.na and Translate workers start without errors and return the local language result. Synthetic clipper integration is recorded in the extension ledger. |
| Previous integrated checkpoint | Before the final per-visit, metadata-origin and workspace-gate repairs: 562 XCTest and 122 Swift Testing tests passed without exclusions (684 total). The macOS Direct and universal iOS Simulator SDK builds for that checkpoint confirmed BUILD SUCCEEDED. Historical logs: `/private/tmp/safience-final-core-38-final.log`, `/private/tmp/safience-final-{mac,ios}-38-confirmed.log`. These results do not establish final-tree validation after the account repairs. |
| Final integrated checks | Complete core suite: 568 XCTest plus 130 Swift Testing cases, 698 total, zero failures. Log: `/private/tmp/safience-final-core-pr78.log`. macOS Direct SDK build confirms BUILD SUCCEEDED: `/private/tmp/safience-final-mac-pr78.log`. The universal iOS Simulator SDK build confirms BUILD SUCCEEDED: `/private/tmp/safience-final-ios-pr78.log`. Both final app Info.plists retain 1.0.7 (37). Current localization validation and `git diff --check` pass. |

## Held account-safety behavior and focused records

- `HistoryStore` schema 4 captures a validated sync epoch with each visit and its upload-only title/summary. Visits recorded before account verification, during sign-out or without durable approval remain local-only. Retried writes keep their captured grant. Remote merges and legacy rows never acquire upload eligibility later; local history is retained.
- All history upload paths query the current epoch explicitly. A shared URL's local title/summary cannot supply another epoch's outgoing metadata. Both native page readers bind delayed descriptions to the originating visit, address and account context; the unbound bridge description route is removed.
- History day records use an account-epoch writer identity, preserving older writers instead of replacing them with a newly eligible subset. Ordinary orphan cleanup affects only the current writer. Explicit space deletion captures its cloud identity and approved account context before local deletion, then targets this device's known writers for that exact space after local commit.
- The workspace saves `syncApprovalRequired` with syncable edits made under an unverified account. Known account changes stamp the gate before separate consent/state writes. Old consent alone cannot authorize that workspace after relaunch. Keep Local retains it. Explicit Sync preserves local content, detaches cloud identities, saves consent and waits for an acknowledged matching gate removal plus account revalidation. A stale choice cannot clear a newer boundary.
- Store-extension configuration is a separate file. Its changes require an acknowledged workspace-gate save before that list is written while account approval is unresolved. Failed saving keeps the change in memory with visible Retry and does not notify remote sync. Localized-name refreshes and presentation order do not create an account gate. Ordinary tab navigation also does not create one.

| Focused check | Current result and record |
| --- | --- |
| Per-visit upload eligibility | 8 Swift Testing cases pass: `/private/tmp/safience-visit-eligibility-tests.log`; source `PadCore/Tests/PadCoreTests/HistoryUploadEligibilityTests.swift`. Includes actual SQLite migration/write denial and persisted stale-account relaunch. |
| Workspace and extension account gate | 6 new workspace cases plus 12 consent cases pass: `/private/tmp/safience-workspace-approval-tests.log`; source `PadCore/Tests/PadCoreTests/WorkspaceSyncApprovalTests.swift`. Includes denied consent/sync-state replacement with a writable workspace, failed gate removal, stale nonce and syncable-change comparisons. |
| Native description origin | 28 actual-source admission checks pass: `Validation/history-description-origin.sh`, `/private/tmp/safience-history-description-origin.log`. Complete browser runs: `/private/tmp/safience-history-description-bridge-{chromium,webkit}.log`, each 153/153. |
| Audit disposition coverage | All 67 original IDs plus N1 through N17 appear exactly once in the plan's ownership map, with no missing or extra IDs. Each has a direct disposition in the native, boundary or recovery ledger. Counts by prefix: X: 14, O: 9, T: 9, P: 10, D: 12, M: 13 and N: 17, 84 total. This is source/evidence coverage, not complete manual acceptance. |

## Existing distribution and current scope

Version 1.0.7 (37) is already published at [GitHub](https://github.com/taehee-pd/Safience/releases/tag/v1.0.7); it fixes migration-blocked macOS startup and page viewport clipping. Version 1.0.6 (36) is already available to the existing internal TestFlight group.

The current task created [open PR 78](https://github.com/taehee-pd/Safience/pull/78). It will not merge the PR or publish another release/TestFlight build. Earlier isolated QA artifacts labelled 1.0.8 (38) remain evidence of those tested source states; project version/build are restored to match main. Final source/build checks after the account-boundary changes are recorded separately. No archive or upload of build 38 occurred.


## Acceptance limits

Human VoiceOver/Full Keyboard Access, complete measured contrast, physical keyboards/assistive input, live account switching/two-device CloudKit, real authenticated clipping/downloads and Duo posture remain outside synthetic verification. Reopening a URL does not recover arbitrary unsaved web-app memory after process death. The ledgers retain each exact gap; passing builds do not remove it.

## Repository scope at PR creation

Main remains `5b36c5a8e545fa6f84ea08c19b08baaa05e7e9be`. Twenty-five additional cleanup PRs, 53 through 77, opened while this work was in progress. They remain unmerged and are outside the completed original PR 43 through 48 review. PR 78 contains this task's remediation; it does not claim those newer sibling PRs were reviewed or integrated.
