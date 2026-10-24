# Startup windows and extension language detection

The unreleased macOS fixes include two findings from the user's current build.

| Finding | Change | Verification |
| --- | --- | --- |
| Opening Safience after its last window closed produced two windows | The reopen delegate returns `false` after requesting its replacement window, preventing AppKit and SwiftUI from also handling the same event. Native default handling remains available if the launch callback is absent. | `Validation/mac-startup-windows.sh` compiles the production app/delegate and `WindowSeed` with synthetic collaborators. A real reopen AppleEvent produced two windows before the fix. The final fixture passes 7/7 checks, including fresh launch, visible-window reopen, reopening after the last close, two intentional windows and repeated reopen events. |
| `tabs.detectLanguage` had no host implementation | `ExtensionTab.detectWebpageLocale` samples only a live tab in its owning space, with a current per-tab website grant. It checks page identity, address, space membership and HandsOff protection before and after sampling. | The local sampler is exercised by `Validation/mac-extension-language.sh`, which extracts the production `Page.extensionLanguageText` method and compiles it with real HandsOff checks under Swift 6 MainActor isolation. The complete app build separately validates the tab delegate. |
| WebKit lacks `i18n.detectLanguage`, used by Chrome extensions | `ExtensionAnswers` detects the supplied text locally with Apple's NaturalLanguage framework and returns the expected result object. It reads no tab and grants no website access. The extension shim exposes this endpoint separately. | Native helper and nonpersistent synthetic WebKit fixtures pass 14/14 checks. The shim has its own callback, Promise and content-world checks. |

Only `Page.swift` calls into website content, preserving the existing source policy. The language detector caps input at 16,384 Unicode scalars. Tab sampling also caps DOM visits at 2,000 and checks the exact page address and protected host list inside the isolated content world before reading text. Hidden subtrees and editable/form values are excluded. No sampled or supplied text is stored or transmitted. Detection uses Apple's local model, so language estimates can differ from Chrome's model.

Logs retained for this run:

- `/private/tmp/safience-startup-windows-baseline.log`
- `/private/tmp/safience-startup-windows-fixed-final.log`
- `/private/tmp/safience-extension-language.log`

The startup fixture preserves two existing intentional windows. A separate direct-executable cold restoration experiment did not present a second-launch scene and timed out, so saved-window cold restoration is not claimed as runtime verified. The production `WindowGroup` and saved `WindowSeed` paths are unchanged. The fixtures launch no production Safience app and use no real workspace, accounts or CloudKit data.
