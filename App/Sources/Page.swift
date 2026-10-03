import PadCore
import UIKit
import WebKit

/// What a page asks of whoever is showing it: a window (Browser) or a
/// sign-in pop-up (Popup).
@MainActor
protocol PageHost: AnyObject {
    func pageDidChange(_ page: Page)
    func isShowing(_ page: Page) -> Bool
    /// A window the page opened (window.open, a link to a new window). The
    /// returned view must be made with `configuration`, as WebKit requires,
    /// for the new page to keep its tie to the one that opened it.
    func page(_ page: Page, open configuration: WKWebViewConfiguration, for action: WKNavigationAction,
              features: WKWindowFeatures) -> WKWebView?
    func pageDidClose(_ page: Page)
    /// Somewhere to show an alert, a sign-in prompt or a save sheet.
    var presenter: UIViewController? { get }
}

/// One tab's page while it is live: its web view, the scripts it gets, the
/// bridges between the iPad's input and it, and everything WebKit tells it.
///
/// This is the only place the app calls into a page or changes what goes
/// into one, and every such call first asks HandsOff whether it may
/// (PolicyTests keeps it that way).
@MainActor
final class Page: NSObject {
    /// The app's own content world: the bridge's variables live here, out of
    /// the page's sight, and the page can't reach its message handler.
    static let world = WKContentWorld.world(name: "Safience")
    static let handlerName = "safience"

    let tab: UUID
    let space: UUID
    let view: PageView
    private let controller: WKUserContentController
    weak var host: PageHost?

    private(set) var adapter = Adapters.standard
    private(set) var bridges = Bridges.standard
    /// The scripts installed for the next document: an adapter's id and its
    /// settings, "hands-off", or nil before the first page.
    private var installed: String?
    private(set) var committed: URL?
    private(set) var mimeType: String?
    private(set) var passwordField = false
    /// The focus is in a field someone types in (bridge.js decides).
    private(set) var editing = false
    private(set) var failure: String?
    private(set) var googleRefused = false
    /// The page's process kept ending; it waits for a click to load again.
    private(set) var exhausted = false
    private var crashes = CrashGuard()

    /// The colour of the page's top, which the bars above it take on.
    private(set) var siteColor: SiteColor?
    private var sampling: Task<Void, Never>?

    private(set) var pointer: Pointer?
    private var zoom: ZoomHold?
    private var observations: [NSKeyValueObservation] = []

    /// What Diagnostics shows.
    struct Stats {
        var pinchSteps = 0
        var commandZoomSteps = 0
        var bridgedWheels = 0
        var standAside = 0
        var webKitWheels = 0
        var relayedKeys = 0
        var processEnds = 0
        var userAgent: String?
        var lastOutcome = ""
    }
    var stats = Stats()

    /// `configuration`: WebKit's, for a page opened by another page; a new
    /// one in the space's store otherwise. Either way the page gets a script
    /// controller of its own, so the scripts swapped for one page (none at
    /// all on a hands-off host) never touch another's.
    init(tab: UUID, space: UUID, configuration: WKWebViewConfiguration? = nil) {
        self.tab = tab
        self.space = space
        let config = configuration ?? Page.configuration(space: space)
        let controller = WKUserContentController()
        config.userContentController = controller
        self.controller = controller
        view = PageView(frame: .zero, configuration: config)
        super.init()
        view.page = self
        view.navigationDelegate = self
        view.uiDelegate = self
        controller.add(Relay(self), contentWorld: Page.world, name: Page.handlerName)
        setUp()
    }

    static func configuration(space: UUID) -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = Stores.store(for: space)
        // Safari on a Mac, by name and by layout: desktop pages, and the end
        // of the user agent that WebKit leaves to the app (Identity.swift).
        config.defaultWebpagePreferences.preferredContentMode = .desktop
        config.applicationNameForUserAgent = Identity.applicationName(for: ProcessInfo.processInfo.operatingSystemVersion)
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = .audio
        config.preferences.isElementFullscreenEnabled = true
        // window.open only from a click or a key, as Safari's pop-up
        // blocking has it; a sign-in window opened by its button opens.
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        return config
    }

    private func setUp() {
        // The page gets the trackpad and the keys; the system's own uses of
        // them in a web view are off.
        view.allowsLinkPreview = false
        view.allowsBackForwardNavigationGestures = false
        view.isFindInteractionEnabled = false
        view.isInspectable = true
        let scroll = view.scrollView
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.isScrollEnabled = false
        scroll.bouncesZoom = false
        scroll.pinchGestureRecognizer?.isEnabled = false
        zoom = ZoomHold(scroll)
        pointer = Pointer(page: self)
        observations = [
            view.observe(\.title) { [weak self] _, _ in MainActor.assumeIsolated { self?.changed() } },
            view.observe(\.url) { [weak self] _, _ in
                MainActor.assumeIsolated {
                    self?.changed()
                    // A page that changes its address without loading (Figma
                    // opening a file) may change its top too.
                    self?.sampleSoon()
                }
            },
            view.observe(\.themeColor) { [weak self] _, _ in MainActor.assumeIsolated { self?.sampleColor() } },
            view.observe(\.isLoading) { [weak self] _, _ in MainActor.assumeIsolated { self?.changed() } },
            view.observe(\.estimatedProgress) { [weak self] _, _ in MainActor.assumeIsolated { self?.changed() } },
            view.observe(\.canGoBack) { [weak self] _, _ in MainActor.assumeIsolated { self?.changed() } },
            view.observe(\.canGoForward) { [weak self] _, _ in MainActor.assumeIsolated { self?.changed() } },
        ]
    }

    private func changed() {
        if let url = view.url {
            Session.shared.record(tab, url: url, title: view.title)
        }
        host?.pageDidChange(self)
    }

    /// Lets the page go: the view out of its window, its scripts and
    /// handler gone, its gestures stopped. WebKit ends the page's process
    /// once nothing holds the view.
    func tearDown() {
        observations.forEach { $0.invalidate() }
        observations = []
        sampling?.cancel()
        sampling = nil
        pointer?.stop()
        pointer = nil
        zoom = nil
        controller.removeAllUserScripts()
        controller.removeScriptMessageHandler(forName: Page.handlerName, contentWorld: Page.world)
        view.stopLoading()
        view.navigationDelegate = nil
        view.uiDelegate = nil
        view.page = nil
        view.removeFromSuperview()
        host = nil
    }

    // MARK: Loading

    func load(_ url: URL) {
        failure = nil
        exhausted = false
        view.load(URLRequest(url: url))
    }

    /// `byHand`: asked for, so the count of endings starts over; a reload
    /// after an ending keeps counting (CrashGuard).
    func reload(byHand: Bool = true) {
        failure = nil
        exhausted = false
        if byHand { crashes.reset() }
        if view.url == nil, let url = committed ?? Session.shared.workspace.tab(tab)?.url {
            view.load(URLRequest(url: url))
        } else {
            view.reload()
        }
    }

    /// Whether the address bar has to show for this page (SignIn.swift).
    var isSignIn: Bool {
        passwordField || SignIn.isSignInPage(view.url)
    }

    var isHandsOff: Bool {
        HandsOff.covers(view.url) || HandsOff.covers(committed)
    }

    var isHeavy: Bool {
        adapter.isHeavy(view.url)
    }

    /// Only a live page can keep these going: a call, a recording, a
    /// download. A hands-off page can't be asked whether it holds anything
    /// typed, so it stays too; sign-in pages are light anyway.
    var mustStay: Bool {
        isHandsOff || view.cameraCaptureState != .none || view.microphoneCaptureState != .none
            || Downloads.shared.isDownloading(for: self)
    }

    /// Puts in the scripts for the page about to load at `url`: the bridge,
    /// the site's adapter, and nothing at all on a hands-off host. Called
    /// before each main-frame document is made, from the navigation's policy
    /// decisions, so the document starts with the right ones.
    private func prepare(for url: URL?) {
        let handsOff = HandsOff.covers(url)
        adapter = Adapters.adapter(for: url)
        bridges = Session.shared.preferences.bridges(for: adapter)
        view.customUserAgent = handsOff ? nil : adapter.userAgent
        let keys = bridges.keys.map(\.rawValue).sorted().joined(separator: ",")
        let wanted = handsOff ? "hands-off" : "\(adapter.id)|\(bridges.wheel.rawValue)|\(keys)|\(bridges.cursors)"
        guard wanted != installed else { return }
        installed = wanted
        controller.removeAllUserScripts()
        guard !handsOff else { return }
        controller.addUserScript(WKUserScript(source: Scripts.ours(for: adapter, bridges: bridges),
                                              injectionTime: .atDocumentStart, forMainFrameOnly: true, in: Page.world))
        if let script = Scripts.page(for: adapter) {
            controller.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentStart,
                                                  forMainFrameOnly: true, in: .page))
        }
    }

    /// After Settings changed: the bridges at once, the scripts from the next page.
    func settingsChanged() {
        bridges = Session.shared.preferences.bridges(for: adapter)
        installed = nil
        prepare(for: committed ?? view.url)
        if !bridges.cursors { pointer?.show(.system) }
    }

    /// WebKit's own scrolling, off unless no bridge can run (Scrolling.swift).
    private func applyScrolling() {
        view.scrollView.isScrollEnabled = Scrolling.isNative(url: view.url, mimeType: mimeType)
        view.scrollView.pinchGestureRecognizer?.isEnabled = false
        zoom?.hold()
    }

    // MARK: Calls into the page

    /// Calls bridge.js, and nothing else, in the app's own world. Never on a
    /// hands-off page, and never on a page that got no bridge.
    private func call(_ body: String, _ arguments: [String: Any], done: ((Any?) -> Void)? = nil) {
        guard !HandsOff.covers(view.url), !HandsOff.covers(committed),
              let installed, installed != "hands-off"
        else {
            done?(nil)
            return
        }
        view.callAsyncJavaScript(body, arguments: arguments, in: nil, in: Page.world) { result in
            if case .success(let value) = result { done?(value) } else { done?(nil) }
        }
    }

    /// One wheel event at `point`, in the page view's points. `guarded`
    /// names which of WebKit's own events make it stand aside: "scroll" for
    /// plain ones, "pinch" for ctrl ones. The outcome is bridge.js's.
    func wheel(at point: CGPoint, dx: Double, dy: Double, modifiers: UIKeyModifierFlags,
               zoom: Bool, guarded: String, done: ((String?) -> Void)? = nil) {
        let message: [String: Any] = [
            "x": Double(point.x), "y": Double(point.y), "width": Double(view.bounds.width),
            "dx": dx, "dy": dy,
            "ctrl": zoom || modifiers.contains(.control),
            "alt": modifiers.contains(.alternate),
            "shift": modifiers.contains(.shift),
            "meta": !zoom && modifiers.contains(.command),
            "guard": guarded,
            "force": bridges.wheel == .always && guarded == "scroll",
        ]
        call("return window.__safience ? window.__safience.wheel(m) : 'absent';", ["m": message]) { [weak self] value in
            let outcome = value as? String
            if let self, let outcome {
                self.stats.lastOutcome = outcome
                if outcome == "native" { self.stats.standAside += 1 } else { self.stats.bridgedWheels += 1 }
            }
            done?(outcome)
        }
    }

    /// Tab or an arrow, taken from the system, for the page (PageView).
    func relay(_ command: UIKeyCommand) {
        guard let input = command.input else { return }
        let key: String
        switch input {
        case "\t": key = "Tab"
        case UIKeyCommand.inputUpArrow: key = "ArrowUp"
        case UIKeyCommand.inputDownArrow: key = "ArrowDown"
        case UIKeyCommand.inputLeftArrow: key = "ArrowLeft"
        case UIKeyCommand.inputRightArrow: key = "ArrowRight"
        default: return
        }
        let flags = command.modifierFlags
        let message: [String: Any] = [
            "key": key, "code": key,
            "shift": flags.contains(.shift), "alt": flags.contains(.alternate),
            "ctrl": flags.contains(.control), "meta": flags.contains(.command),
        ]
        stats.relayedKeys += 1
        call("return window.__safience ? window.__safience.key(m) : 'absent';", ["m": message])
    }

    /// Whether freezing would lose something typed: nil when the page can't
    /// be asked, which counts as yes.
    func holdsTyping(_ done: @escaping (Bool?) -> Void) {
        call("return window.__safience ? window.__safience.unsaved() : null;", [:]) { value in
            done(value as? Bool)
        }
    }

    /// A picture of the page as it is now.
    func picture(_ done: @escaping (UIImage?) -> Void) {
        guard view.bounds.width > 0, view.bounds.height > 0 else {
            done(nil)
            return
        }
        let configuration = WKSnapshotConfiguration()
        configuration.afterScreenUpdates = false
        view.takeSnapshot(with: configuration) { image, _ in done(image) }
    }

    // MARK: The colour along the top

    /// The colour the page's top edge shows, so the bars run on into it;
    /// the page's theme-color when there is nothing to see yet, or the page
    /// is off screen. A theme-color can differ from what is drawn (GitHub's
    /// is grey over a navy top), which is why the picture comes first. A
    /// picture, not a script, so it is the same on a hands-off page.
    private func sampleColor() {
        let theme = view.themeColor.flatMap { SiteColor($0) }
        guard view.bounds.width > 0, view.window != nil else {
            if let theme { setSiteColor(theme) }
            return
        }
        let configuration = WKSnapshotConfiguration()
        configuration.rect = CGRect(x: 0, y: 0, width: view.bounds.width, height: 2)
        configuration.snapshotWidth = 64
        configuration.afterScreenUpdates = false
        view.takeSnapshot(with: configuration) { [weak self] image, _ in
            if let color = image.flatMap({ SiteColor(picture: $0) }) ?? theme {
                self?.setSiteColor(color)
            }
        }
    }

    /// Soon after a change, and twice more for pages that draw their top
    /// after they have loaded (Figma's file view takes seconds).
    private func sampleSoon() {
        sampling?.cancel()
        sampling = Task { [weak self] in
            for delay in [0.3, 1.5, 4.0] {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                self?.sampleColor()
            }
        }
    }

    private func setSiteColor(_ color: SiteColor) {
        guard color != siteColor else { return }
        siteColor = color
        host?.pageDidChange(self)
    }

    // MARK: Messages from the bridge

    fileprivate func received(_ message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, !isHandsOff,
              let body = message.body as? [String: Any], let kind = body["kind"] as? String
        else { return }
        switch kind {
        case "focus":
            editing = body["editing"] as? Bool ?? false
        case "password":
            passwordField = body["present"] as? Bool ?? false
            host?.pageDidChange(self)
        case "wheel":
            stats.webKitWheels = body["trusted"] as? Int ?? stats.webKitWheels
        case "hello":
            stats.userAgent = body["userAgent"] as? String
        case "cursor":
            pointer?.show(bridges.cursors ? PageCursor(message: body) : .system)
        case "icons":
            let urls = (body["urls"] as? [String] ?? []).compactMap(URL.init(string:))
            SiteIcons.shared.learn(urls, for: view.url)
        default:
            break
        }
    }

    // MARK: When the page's process ends

    /// The page's content process ended (out of memory, most often), and
    /// the page is blank. On screen it loads again by itself, unless it has
    /// kept ending (CrashGuard); off screen it freezes, to load when opened.
    fileprivate func processEnded() {
        stats.processEnds += 1
        guard let host, host.isShowing(self) else {
            Session.shared.pages.processEnded(self)
            return
        }
        if crashes.shouldReload(at: Date()) {
            reload(byHand: false)
        } else {
            exhausted = true
            host.pageDidChange(self)
        }
    }
}

/// The bridge's messages, held weakly: the script controller keeps its
/// handlers for as long as it lives, and the page owns the controller.
private final class Relay: NSObject, WKScriptMessageHandler {
    weak var page: Page?

    init(_ page: Page) {
        self.page = page
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        MainActor.assumeIsolated { page?.received(message) }
    }
}

// MARK: - WebKit's questions

extension Page: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 preferences: WKWebpagePreferences,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
        preferences.preferredContentMode = .desktop
        if navigationAction.shouldPerformDownload {
            decisionHandler(.download, preferences)
            return
        }
        if let url = navigationAction.request.url, let scheme = url.scheme?.lowercased(),
           !["http", "https", "about", "data", "blob", "file", "javascript"].contains(scheme) {
            // mailto:, tel:, another app's link: theirs to open, and only
            // from a click, so a page or an ad can't send you off by itself.
            if navigationAction.navigationType == .linkActivated {
                UIApplication.shared.open(url)
            }
            decisionHandler(.cancel, preferences)
            return
        }
        if navigationAction.targetFrame?.isMainFrame == true {
            prepare(for: navigationAction.request.url)
        }
        decisionHandler(.allow, preferences)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void) {
        if navigationResponse.isForMainFrame {
            // After any redirects: the host whose document this will be.
            prepare(for: navigationResponse.response.url)
            mimeType = navigationResponse.response.mimeType
        }
        if !navigationResponse.canShowMIMEType {
            decisionHandler(.download)
            return
        }
        if let response = navigationResponse.response as? HTTPURLResponse,
           let disposition = response.value(forHTTPHeaderField: "Content-Disposition"),
           disposition.lowercased().hasPrefix("attachment") {
            decisionHandler(.download)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        failure = nil
        host?.pageDidChange(self)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        committed = webView.url
        passwordField = false
        editing = false
        // The last page's cursor goes with it; this one says its own.
        pointer?.show(.system)
        googleRefused = SignIn.googleRefused(webView.url)
        applyScrolling()
        host?.pageDidChange(self)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        applyScrolling()
        host?.pageDidChange(self)
        sampleSoon()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        failed(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        failed(error)
    }

    private func failed(_ error: Error) {
        let error = error as NSError
        // Stopped, replaced by another load, or turned into a download.
        if error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled { return }
        if error.domain == "WebKitErrorDomain" && (error.code == 102 || error.code == 204) { return }
        failure = error.localizedDescription
        host?.pageDidChange(self)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        processEnded()
    }

    func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge,
                 completionHandler: @escaping @MainActor (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // A server's own sign-in (Basic, Digest, NTLM): a company's single
        // sign-on behind it is one way in when Google's isn't.
        let method = challenge.protectionSpace.authenticationMethod
        let asks = [NSURLAuthenticationMethodHTTPBasic, NSURLAuthenticationMethodHTTPDigest,
                    NSURLAuthenticationMethodNTLM].contains(method)
        guard asks, challenge.previousFailureCount < 3, let presenter = host?.presenter else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        Dialogs.credentials(for: challenge.protectionSpace, on: presenter) { credential in
            if let credential {
                completionHandler(.useCredential, credential)
            } else {
                completionHandler(.cancelAuthenticationChallenge, nil)
            }
        }
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        Downloads.shared.adopt(download, for: self)
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        Downloads.shared.adopt(download, for: self)
    }
}

extension Page: WKUIDelegate {
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        host?.page(self, open: configuration, for: navigationAction, features: windowFeatures)
    }

    func webViewDidClose(_ webView: WKWebView) {
        host?.pageDidClose(self)
    }

    /// No menu of the system's on a long press or a secondary click: the
    /// page's own context menu is the one (Figma's, for one), and the
    /// system's link menu on top of it made two.
    func webView(_ webView: WKWebView, contextMenuConfigurationForElement elementInfo: WKContextMenuElementInfo,
                 completionHandler: @escaping @MainActor (UIContextMenuConfiguration?) -> Void) {
        completionHandler(nil)
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor () -> Void) {
        guard let presenter = host?.presenter, host?.isShowing(self) == true else {
            completionHandler()
            return
        }
        Dialogs.alert(message, from: frame, on: presenter, done: completionHandler)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor (Bool) -> Void) {
        guard let presenter = host?.presenter, host?.isShowing(self) == true else {
            completionHandler(false)
            return
        }
        Dialogs.confirm(message, from: frame, on: presenter, done: completionHandler)
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor (String?) -> Void) {
        guard let presenter = host?.presenter, host?.isShowing(self) == true else {
            completionHandler(nil)
            return
        }
        Dialogs.prompt(prompt, defaultText: defaultText, from: frame, on: presenter, done: completionHandler)
    }
}
