import AppKit
import Darwin
import WebKit

// Compiled with the production ExtensionLanguage implementation only.
// All WebKit fixtures use nonpersistent stores and synthetic HTML.
@main
struct ExtensionLanguageAcceptance {
    @MainActor
    static func main() async {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        var checks = 0, failures = 0
        func check(_ passed: Bool, _ label: String) {
            checks += 1
            print("\(passed ? "PASS" : "FAIL") \(label)")
            if !passed { failures += 1 }
        }
        let english = "This browser page contains an article written in English. The reader can collect useful links and save them in a collection for later reading."
        let korean = "이 페이지에는 한국어로 작성한 글이 있습니다. 브라우저에서 페이지의 언어를 확인하고 필요한 링크를 모아서 나중에 다시 읽을 수 있습니다."
        let french = "Cette page contient un article écrit en français. Le lecteur peut enregistrer des liens intéressants dans une collection pour les consulter plus tard."
        let en = ExtensionLanguage.detect(english)
        check(en.languages.first?.language == "en" && en.isReliable, "English supplied text is detected locally")
        check(ExtensionLanguage.detect(korean).languages.first?.language == "ko", "Korean supplied text is detected locally")
        check(ExtensionLanguage.detect(french).languages.first?.language == "fr", "French supplied text is detected locally")
        let empty = ExtensionLanguage.detect(" 12345 \n ")
        check(empty.languages.isEmpty && !empty.isReliable && empty.locale == nil, "Empty and numeric input remain undetermined")
        check(!ExtensionLanguage.detect("Hello").isReliable, "Very short input is not reported reliable")
        let mixed = ExtensionLanguage.detect(english + "\n" + korean)
        check(Set(mixed.languages.map(\.language)) == ["en", "ko"] && mixed.languages.allSatisfy { (0...100).contains($0.percentage) }, "Mixed paragraphs retain bounded language percentages")
        let prefix = String(repeating: english + " ", count: 150)
        let long = ExtensionLanguage.detect(prefix + String(repeating: korean, count: 10_000))
        check(long.languages.first?.language == "en" && long.languages.count <= 3, "Oversized supplied text is capped before detection")
        check((en.json["languages"] as? [[String: Any]])?.first?["language"] as? String == "en", "JSON follows the extension API result shape")

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 600, height: 400), configuration: config)
        let load = FixtureLoad()
        view.navigationDelegate = load
        let page = Page(view: view)
        await load.html("<body><p>\(english)</p><div hidden>\(String(repeating: korean, count: 100))</div><textarea>\(korean)</textarea><div contenteditable>\(korean)</div></body>", in: view)
        do {
            let detected = try await ExtensionLanguage.webpage(isAllowed: { true }, sample: { try await page.extensionLanguageText() })
            check(detected?.languages.first?.language == "en", "Tab detection samples rendered text and excludes hidden and editable values")
            let denied = try await ExtensionLanguage.webpage(isAllowed: { false }, sample: { try await page.extensionLanguageText() })
            check(denied == nil, "A denied page is not sampled")
            let protected = try await view.callAsyncJavaScript(ExtensionLanguage.sampleText,
                arguments: ["limit": ExtensionLanguage.maximumScalars, "expectedURL": view.url!.absoluteString, "protectedHosts": ["language-fixture.invalid"]],
                contentWorld: Page.world)
            check(protected as? String == nil, "The isolated-world script independently rejects a protected host")
            var calls = 0
            let revoked = try await ExtensionLanguage.webpage(isAllowed: { calls += 1; return calls == 1 }, sample: { try await page.extensionLanguageText() })
            check(revoked == nil && calls == 2, "Revocation or navigation during sampling discards its answer")
            let huge = (0..<2200).map { _ in "<span></span>" }.joined() + "<p>\(korean)</p>"
            await load.html("<body>\(huge)</body>", in: view)
            let bounded = try await ExtensionLanguage.webpage(isAllowed: { true }, sample: { try await page.extensionLanguageText() })
            check(bounded?.languages.isEmpty == true, "DOM sampling stops at its node budget")
            await load.html("<body contenteditable><p>\(english)</p></body>", in: view)
            let editable = try await ExtensionLanguage.webpage(isAllowed: { true }, sample: { try await page.extensionLanguageText() })
            check(editable?.languages.isEmpty == true, "A page-wide editor is excluded")
        } catch { check(false, "Synthetic WebKit sampling completes: \(error)") }
        print("Extension language: \(checks - failures)/\(checks) native checks passed")
        fflush(stdout)
        exit(failures == 0 ? 0 : 1)
    }
}

@MainActor
private final class FixtureLoad: NSObject, WKNavigationDelegate {
    private var done: CheckedContinuation<Void, Never>?
    func html(_ html: String, in view: WKWebView) async {
        await withCheckedContinuation { done in
            self.done = done
            view.loadHTMLString(html, baseURL: URL(string: "https://language-fixture.invalid"))
        }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { done?.resume(); done = nil }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) { done?.resume(); done = nil }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) { done?.resume(); done = nil }
}

@MainActor
private final class Page {
    static let world = WKContentWorld.world(name: "Safience")
    let view: WKWebView
    var committed: URL? { view.url }
    init(view: WKWebView) { self.view = view }
}
