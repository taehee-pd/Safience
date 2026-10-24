import AppKit
import PadCore
import UniformTypeIdentifiers
import WebKit

/// What a page asks of whoever is showing it: a window (WindowModel), a
/// Peek over a tab (PeekPage), a little window (LittleWindow) or a sign-in
/// pop-up (Popup).
@MainActor
protocol PageHost: AnyObject {
    func pageDidChange(_ page: Page)
    func isShowing(_ page: Page) -> Bool
    /// A window the page opened (window.open, a link to a new window). The
    /// returned view must be made with `configuration`, as WebKit requires,
    /// for the new page to keep its tie to the one that opened it.
    func page(_ page: Page, open configuration: WKWebViewConfiguration, for action: WKNavigationAction,
              features: WKWindowFeatures) -> WKWebView?
    /// A ⌘-click's address, for a tab of its own (NewTabClick); false where
    /// there are no tabs, and the page goes there itself.
    func page(_ page: Page, openInNewTab url: URL, inFront: Bool) -> Bool
    func pageDidClose(_ page: Page)
    /// The window to put an alert or a sheet on.
    var hostWindow: NSWindow? { get }
}

/// A page's web view: WebKit's, with its menu saying "Tab" where WebKit's says
/// "Window", since a page asking for a window gets a tab here as in Safari.
final class PageView: WKWebView {
    weak var page: Page?

    private static let renamed: [String: String] = [
        "WKMenuItemIdentifierOpenLinkInNewWindow": "Open Link in New Tab",
        "WKMenuItemIdentifierOpenImageInNewWindow": "Open Image in New Tab",
        "WKMenuItemIdentifierOpenMediaInNewWindow": "Open Video in New Tab",
        "WKMenuItemIdentifierOpenFrameInNewWindow": "Open Frame in New Tab",
    ]

    /// One of WebKit's items for an extension: its own class, the one
    /// mark WebKit gives them.
    static func isExtensionItem(_ item: NSMenuItem) -> Bool {
        NSStringFromClass(type(of: item)) == "_WKWebExtensionMenuItem"
    }

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        for item in menu.items {
            if let id = item.identifier?.rawValue, let title = Self.renamed[id] { item.title = title }
        }
        // Open Link in Peek, after Open Link in New Tab, on a page in a
        // window's tab: WebKit's own item for the link under the pointer,
        // with the window it opens made a Peek (Page.peekAsked).
        if let page, page.canPeek, !page.isHandsOff,
           let newTab = menu.items.first(where: { $0.identifier?.rawValue == "WKMenuItemIdentifierOpenLinkInNewWindow" }) {
            let item = NSMenuItem(title: "Open Link in Peek", action: #selector(openLinkInPeek(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = newTab
            menu.insertItem(item, at: menu.index(of: newTab) + 1)
        }
        // WebKit puts the extensions' own items (contextMenus) in itself,
        // after the page's; on Google's sign-in they are taken out, with
        // the line WebKit drew above them.
        if page?.isHandsOff == true {
            for item in menu.items.reversed() where Self.isExtensionItem(item) {
                let index = menu.index(of: item)
                menu.removeItem(item)
                if index > 0, menu.items[index - 1].isSeparatorItem,
                   index == menu.items.count || menu.items[index].isSeparatorItem {
                    menu.removeItem(at: index - 1)
                }
            }
        }
        super.willOpenMenu(menu, with: event)
    }

    @objc private func openLinkInPeek(_ sender: NSMenuItem) {
        guard let newTab = sender.representedObject as? NSMenuItem, let action = newTab.action else { return }
        page?.peekAsked = Date()
        NSApp.sendAction(action, to: newTab.target, from: newTab)
    }
}

/// One tab's page while it is live: its web view, the content blocker's
/// lists and scripts it gets, and everything WebKit tells it.
///
/// On a Mac the trackpad, the mouse and every ⌘ key reach the page as they
/// do in Safari, so none of the iPad's bridges (bridge.js) go into a page
/// here. This is still the only place the app calls into a page or changes
/// what goes into one, and every such call first asks HandsOff whether it
/// may (PolicyTests keeps it that way).
@MainActor
final class Page: NSObject {
    /// The app's own content world: what it asks a page lives here, out of the page's sight.
    static let world = WKContentWorld.world(name: "Safience")

    let tab: UUID
    let space: UUID
    let view: PageView
    private let controller: WKUserContentController
    weak var host: PageHost?

    /// The site's adapter, for what its own reader can add to a handoff (a
    /// video's transcript) and how heavy its pages are; none of its bridges.
    private(set) var adapter = Adapters.standard
    /// The scripts installed for the next document: the scripted filters'
    /// stamp, `handsOffScripts`, or nil before the first page.
    private var installed: String?
    private static let handsOffScripts = "hands-off"
    /// The content blocker's lists on this page, by identifier: none on a
    /// hands-off page, or where Settings or the site's switch turns it off.
    private var blocking = PageBlocking()
    private(set) var committed: URL?
    /// Why the last load failed, to show in place of the page; nil once one loads.
    private(set) var failure: String?
    /// The address that failed, for retry: a page whose first load failed
    /// has nothing committed to reload, and one that failed going on would
    /// reload the page it was on. Only a request for a page (GET): a form
    /// sent again by its address alone would lose what it sent.
    private var failedURL: URL?
    private var askingForPage = true
    /// The failure shown is a form's sending (a POST), not the page's own:
    /// the form is still there under it, filled in.
    private var sendingFailed = false
    /// The page's process kept ending; it waits for a click to load again.
    private(set) var exhausted = false
    private var crashes = CrashGuard()
    /// The question about a link for another app, while it is up, and how
    /// often this page has been told no (openElsewhere).
    private var askingElsewhere = false
    private var refusedElsewhere = 0
    /// The screen's light or dark, to the sites that ask for it as a header
    /// (ColorSchemeHint): for every page, and for the run only.
    private static var colorHint = ColorSchemeHint()
    /// Whether the page's last request had that header, and could be made again.
    private var hintCarried = false
    private var hintRepeatable = false
    /// A page another page opened (window.open, a link to a new window).
    private var wasOpened = false
    /// One of an extension's own pages, in a view from the extension's
    /// configuration. It stays one: a navigation to a website goes to a new
    /// tab, as one from a website to an extension's page does.
    let isExtensionPage: Bool
    private var observations: [NSKeyValueObservation] = []
    /// The visit the document on screen is, in its space's history (PageHistory).
    private var history = PageHistory()

    /// The page is a tab coming back as it was (thawed, or at launch): its
    /// first document was visited already.
    func restoring() {
        history.restoring()
    }

    /// The document shows a password field (PasswordWatch): a sign-in page.
    private(set) var passwordField = false

    /// The page on screen has a password field, or no longer has
    /// (PasswordWatch): a sign-in page, whose visit history takes back and
    /// keeps nothing more of while the field is there, and which the open
    /// tabs other devices see leave out.
    func password(_ present: Bool) {
        if present { history.signInFound() } else { history.signInGone() }
        passwordField = present
    }

    /// The page over this one, while one is open (PeekPage): a pop-up it
    /// opened, or a link that left a pinned tab's site.
    private(set) var peek: PeekPage?
    /// When Open Link in Peek was chosen from the page's menu: the window
    /// WebKit opens for it, a moment later, is a Peek.
    fileprivate var peekAsked: Date?

    /// The site's picture-in-picture window, while one is open (DocumentPicture, PictureWindow).
    private(set) var picture: PictureWindow?
    /// The app is calling the site's handler for leaving the tab, so a window opened now is the app's doing.
    private var enteringPicture = false
    /// A video of the page is in macOS's picture in picture, put there as Safience went behind another app.
    private var videoFloated = false
    /// Safience is behind another app, as far as this page was told: a video
    /// that goes into picture in picture after it came back goes back at once.
    private var videoWanted = false
    /// The call that floats a video is on its way.
    private var floatingVideo = false
    /// Hosts given Document Picture-in-Picture besides DocumentPicture's, for
    /// a test build's own page: `-pictureHosts 127.0.0.1,localhost`. None in a release.
    private static let pictureTestHosts: [String] = {
        #if DEBUG
        (UserDefaults.standard.string(forKey: "pictureHosts") ?? "").split(separator: ",").map(String.init)
        #else
        []
        #endif
    }()

    /// `configuration`: WebKit's, for a page opened by another page; a new
    /// one in the space's store otherwise. Either way the page gets a script
    /// controller of its own, so the scripts swapped for one page (none at
    /// all on a hands-off host) never touch another's.
    init(tab: UUID, space: UUID, configuration: WKWebViewConfiguration? = nil, extensionPage: Bool = false) {
        self.tab = tab
        self.space = space
        isExtensionPage = extensionPage
        let config = configuration ?? Page.configuration(space: space)
        // An extension's page keeps the controller WebKit made for it.
        let controller = extensionPage ? config.userContentController : WKUserContentController()
        config.userContentController = controller
        self.controller = controller
        view = PageView(frame: .zero, configuration: config)
        super.init()
        view.page = self
        view.navigationDelegate = self
        view.uiDelegate = self
        setUp()
    }

    static func configuration(space: UUID) -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = Stores.store(for: space)
        // Safari, by name: the end of the user agent that WebKit leaves to
        // the app (Identity.swift). Without it sites read the app as a web
        // view inside an app, and Google refuses to sign in.
        config.applicationNameForUserAgent = Identity.applicationName(for: ProcessInfo.processInfo.operatingSystemVersion)
        config.mediaTypesRequiringUserActionForPlayback = .audio
        config.preferences.isElementFullscreenEnabled = true
        // window.open only from a click or a key, as Safari's pop-up
        // blocking has it; a sign-in window opened by its button opens.
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        // macOS's own picture in picture for a video (appWentBehind, and a
        // site's own button): WebKit has it, and turns it off in an app's
        // web views on macOS, with no public switch. This one is private: a
        // DMG has no App Review, and a macOS that takes it away leaves
        // picture in picture off, as it was. With the underscore the key
        // finds no setter and throws; without it, `_setAllows…:` is found.
        if config.preferences.responds(to: Selector(("_setAllowsPictureInPictureMediaPlayback:"))) {
            config.preferences.setValue(true, forKey: "allowsPictureInPictureMediaPlayback")
        }
        // The space's extensions (Extensions): WebKit takes a page's
        // controller only before the page's view is made.
        config.webExtensionController = Extensions.shared.controller(for: space)
        return config
    }

    private func setUp() {
        // Safari's own: a two-finger swipe goes back and forward, a pinch zooms.
        view.allowsBackForwardNavigationGestures = true
        view.allowsMagnification = true
        view.isInspectable = true
        observations = [
            view.observe(\.title) { [weak self] _, _ in MainActor.assumeIsolated { self?.changed() } },
            view.observe(\.url) { [weak self] _, _ in MainActor.assumeIsolated { self?.changed() } },
            // How a load is going is the window's to show and not the workspace's to keep.
            view.observe(\.isLoading) { [weak self] _, _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.progressed()
                    Extensions.shared.tabs.loadingChanged(self)
                }
            },
            view.observe(\.estimatedProgress) { [weak self] _, _ in MainActor.assumeIsolated { self?.progressed() } },
            view.observe(\.canGoBack) { [weak self] _, _ in MainActor.assumeIsolated { self?.progressed() } },
            view.observe(\.canGoForward) { [weak self] _, _ in MainActor.assumeIsolated { self?.progressed() } },
            view.observe(\.hasOnlySecureContent) { [weak self] _, _ in MainActor.assumeIsolated { self?.progressed() } },
        ]
        // The Chrome Web Store's button asks through this, from the app's
        // own world (StoreButton).
        if !isExtensionPage {
            controller.add(StoreButton(page: self), contentWorld: Page.world, name: StoreButton.name)
            // A password field on the page, for history (PasswordWatch).
            controller.add(PasswordWatch(page: self), contentWorld: Page.world, name: PasswordWatch.name)
        }
    }

    /// Where the page is, or what it is called, is another: kept, and shown.
    private func changed() {
        Session.shared.pages.navigationChanged(self)
        if let url = view.url {
            Session.shared.record(tab, url: url, title: view.title)
        }
        history.changed(url: view.url, title: view.title, entry: view.backForwardList.currentItem,
                        loading: view.isLoading, space: space, tab: tab)
        host?.pageDidChange(self)
    }

    private func progressed() {
        host?.pageDidChange(self)
    }

    /// Lets the page go: the view out of its window, its scripts gone.
    /// WebKit ends the page's process once nothing holds the view.
    func tearDown() {
        picture?.close()
        peek?.close()
        observations.forEach { $0.invalidate() }
        observations = []
        controller.removeAllUserScripts()
        blocking.remove(from: controller)
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
        failedURL = nil
        sendingFailed = false
        exhausted = false
        request(url)
    }

    /// Try Again where the page couldn't load (a Peek's, a little window's,
    /// which no tab of the workspace keeps an address for): the address that
    /// failed; for a form whose sending failed, the form again as it was,
    /// its fields still filled in, to send again, which a reload would empty;
    /// otherwise the page again.
    func retry() {
        if let failedURL, view.url != failedURL { return load(failedURL) }
        if sendingFailed, view.url != nil {
            failure = nil
            sendingFailed = false
            host?.pageDidChange(self)
            return
        }
        reload()
    }

    /// A site by request; a file opened from Finder with leave for the page
    /// to read it, and only it, which a request for its address is refused,
    /// and readable again through its bookmark after a relaunch (FileAccess).
    private func request(_ url: URL) {
        if url.isFileURL {
            FileAccess.open(url)
            view.loadFileURL(url, allowingReadAccessTo: url)
        } else {
            view.load(URLRequest(url: url))
        }
    }

    /// `byHand`: asked for, so the count of endings starts over.
    func reload(byHand: Bool = true) {
        failure = nil
        exhausted = false
        if byHand { crashes.reset() }
        if view.url == nil, let url = committed ?? Session.shared.workspace.tab(tab)?.url {
            request(url)
        } else {
            view.reload()
        }
        host?.pageDidChange(self)
    }

    var isHandsOff: Bool {
        HandsOff.covers(view.url) || HandsOff.covers(committed)
    }

    #if DEBUG
    /// What the store page's button says, for the command-line check.
    func storeButtonLabel() async -> String? {
        guard StoreButton.isStore(view.url) else { return nil }
        let script = "const b = document.querySelector('button[data-safience=\"add\"]'); return b ? b.textContent.trim() + (b.disabled ? ' (off)' : '') : 'none'"
        return (try? await view.callAsyncJavaScript(script, contentWorld: Page.world)) as? String
    }

    /// A line of the test page's own script, in the page's world, for the
    /// picture test's run of Tests/picture.html (PictureTest.swift), which
    /// goes through here as every call into a page does. Never on a hands-off page.
    func pictureTestCall(_ body: String, arguments: [String: Any] = [:]) async -> Any? {
        guard !isHandsOff else { return nil }
        return try? await view.callAsyncJavaScript(body, arguments: arguments, in: nil, contentWorld: .page)
    }
    #endif

    /// The Chrome Web Store page's button told what is installed and what
    /// is on its way (StoreButton), in the app's own world; only there.
    func tellStore(_ state: String) {
        guard !isHandsOff, StoreButton.isStore(view.url) else { return }
        view.evaluateJavaScript("window.__safienceStore && window.__safienceStore.state(\(state))", in: nil, in: Page.world)
    }

    var isSignIn: Bool {
        SignIn.isSignInPage(view.url)
    }

    var isHeavy: Bool {
        adapter.isHeavy(view.url)
    }

    /// Only a live page can keep these going: a call, a recording, a download,
    /// a picture-in-picture window, whose page is this one's.
    var mustStay: Bool {
        isHandsOff || view.cameraCaptureState != .none || view.microphoneCaptureState != .none
            || Downloads.shared.isDownloading(for: self) || picture != nil || videoFloated || peek != nil
    }

    /// Puts in what the page about to load at `url` gets: the content
    /// blocker's lists and the scripts for what its filters ask that WebKit's
    /// rules can't do (ScriptedFilters), and nothing at all on a hands-off
    /// host. Called before each main-frame document is made, from the
    /// navigation's policy decision, so the document starts with them.
    private func prepare(for url: URL?) {
        let handsOff = HandsOff.covers(url)
        blocking.apply(for: url, to: controller)
        adapter = Adapters.adapter(for: url)
        let filters = blocksContent ? ContentBlocker.shared.scriptedRules(for: url) : PageRules()
        let store = StoreButton.isStore(url)
        let picture = Self.offersPicture(url)
        let wanted = handsOff ? Self.handsOffScripts
            : (filters.isEmpty ? "" : filters.stamp) + (store ? "+store" : "") + (picture ? "|picture" : "")
        guard wanted != installed else { return }
        installed = wanted
        controller.removeAllUserScripts()
        guard !handsOff else { return }
        if !isExtensionPage {
            controller.addUserScript(WKUserScript(source: PasswordWatch.script, injectionTime: .atDocumentEnd,
                                                  forMainFrameOnly: true, in: Page.world))
        }
        // Document Picture-in-Picture, in the page's own world before its
        // scripts look for it, on the sites given it.
        if picture {
            controller.addUserScript(WKUserScript(source: Scripts.picture, injectionTime: .atDocumentStart,
                                                  forMainFrameOnly: true, in: .page))
        }
        controller.addFilterScripts(for: filters)
        if store {
            controller.addUserScript(WKUserScript(source: Scripts.extensionStore, injectionTime: .atDocumentEnd,
                                                  forMainFrameOnly: true, in: Page.world))
        }
    }

    /// Whether the page on screen has ads and trackers blocked, for its menu.
    var blocksContent: Bool {
        blocking.isOn
    }

    /// The content blocker has new lists: this page's next load has them.
    func blockingChanged() {
        blocking.apply(for: committed ?? view.url, to: controller)
    }

    /// After Settings changed: from the next page.
    func settingsChanged() {
        prepare(for: committed ?? view.url)
    }

    /// Whether a navigation is a ⌘-click (or ⌘⇧, or a middle click) to open
    /// in a new tab (NewTabClick), from the keys and the button WebKit says made it.
    private func newTabChoice(for action: WKNavigationAction) -> NewTabClick.Choice {
        let flags = action.modifierFlags
        return NewTabClick.choice(for: action, command: flags.contains(.command), shift: flags.contains(.shift),
                                  middleButton: action.buttonNumber == 2)
    }

    // MARK: Find, zoom, print

    /// The next place the words are on the page, after the selection or
    /// before it; `found` hears whether there is one.
    func find(_ text: String, backwards: Bool = false, found: @escaping (Bool) -> Void) {
        guard !text.isEmpty else { return found(false) }
        let configuration = WKFindConfiguration()
        configuration.backwards = backwards
        configuration.caseSensitive = false
        configuration.wraps = true
        view.find(text, configuration: configuration) { result in found(result.matchFound) }
    }

    /// Safari's steps of zoom, from half to three times.
    private static let zooms: [CGFloat] = [0.5, 0.67, 0.75, 0.8, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2, 2.5, 3]

    func zoom(by step: Int) {
        guard step != 0 else {
            view.pageZoom = 1
            return
        }
        let now = view.pageZoom
        let next = step > 0 ? Self.zooms.first { $0 > now + 0.01 } : Self.zooms.last { $0 < now - 0.01 }
        if let next { view.pageZoom = next }
    }

    func print() {
        guard let window = host?.hostWindow else { return }
        let operation = view.printOperation(with: NSPrintInfo.shared)
        operation.view?.frame = view.bounds
        operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }

    // MARK: Calls into the page

    /// Whether letting the page go could lose a draft. The read-only probe
    /// needs no input bridge. An unavailable result is unsafe to release.
    func holdsTyping(_ done: @escaping (Bool?) -> Void) {
        guard !isHandsOff, let installed, installed != Self.handsOffScripts else {
            done(nil)
            return
        }
        view.callAsyncJavaScript(Scripts.draftCall,
                                 arguments: ["handsOff": HandsOff.hosts], in: nil, in: Page.world) { result in
            if case .success(let value) = result { done(value as? Bool) } else { done(nil) }
        }
    }

    /// The page as it looks, `pixels` wide, for Apple Intelligence's model
    /// to look at a page with too few words to go by (HandoffJob). A picture,
    /// not a script: nil when the page is not in a window.
    func picture(pixels: CGFloat) async -> CGImage? {
        guard view.window != nil, view.bounds.width > 0, view.bounds.height > 0 else { return nil }
        let configuration = WKSnapshotConfiguration()
        configuration.afterScreenUpdates = false
        configuration.snapshotWidth = NSNumber(value: Double(pixels / max(1, view.window?.backingScaleFactor ?? 2)))
        return await withCheckedContinuation { continuation in
            view.takeSnapshot(with: configuration) { image, _ in
                continuation.resume(returning: image?.cgImage(forProposedRect: nil, context: nil, hints: nil))
            }
        }
    }

    /// The icons the page names, best first, as bridge.js's siteIcons() has
    /// them on the iPad: the site's own icon, as browsers show it, a drawing
    /// before its largest picture; then Apple's touch icon, a square for a
    /// Home Screen; then /favicon.ico, the one every site had before <link>
    /// did. SiteIcons fetches the first that loads.
    private static let iconsCall = """
        const found = [];
        for (const link of document.querySelectorAll('link[rel][href]')) {
          const rel = String(link.rel || '').toLowerCase().split(/\\s+/);
          const touch = rel.includes('apple-touch-icon') || rel.includes('apple-touch-icon-precomposed');
          if (!touch && !rel.includes('icon')) continue;
          if (rel.includes('mask-icon')) continue;
          const href = link.href;
          if (!/^(https?:|data:image\\/)/i.test(href)) continue;
          const type = String(link.type || '').toLowerCase();
          const svg = type.includes('svg') || /^data:image\\/svg/i.test(href) || /\\.svg([?#]|$)/i.test(href);
          const sizes = String(link.getAttribute('sizes') || '').toLowerCase().split(/\\s+/);
          const size = Math.min(Math.max(0, ...sizes.map((each) => parseInt(each, 10) || 0)), 512);
          // The site's own icon first, as browsers show it: a drawing, then one
          // for any size (an .ico of several), then its largest picture, then an
          // alternate; Apple's touch icon (a square for a Home Screen) after them,
          // and a speck under 32 pixels after that.
          let score;
          if (touch) score = 1000 + size;
          else if (svg) score = 3000;
          else if (sizes.includes('any')) score = 2600;
          else if (size && size < 32) score = 500 + size;
          else score = (rel.includes('alternate') ? 1500 : 2000) + size;
          // One for a dark screen, or for another kind of screen, after the rest:
          // the icon kept is the one for a light screen.
          const media = String(link.media || '').toLowerCase();
          const scheme = /prefers-color-scheme/.test(media);
          if ((scheme && /prefers-color-scheme:\\s*dark/.test(media)) || (media && !scheme && !window.matchMedia(media).matches)) {
            score -= 2900;
          }
          found.push({ href, score });
        }
        found.sort((a, b) => b.score - a.score);
        const urls = found.map((icon) => icon.href);
        if (/^https?:$/.test(location.protocol)) urls.push(location.origin + '/favicon.ico');
        return Array.from(new Set(urls)).slice(0, 6);
        """

    /// Asks the page for its icons once it has loaded, unless SiteIcons has
    /// the site's already. Never on a hands-off host.
    private func learnIcons() {
        guard let url = view.url, ["http", "https"].contains(url.scheme ?? ""), !HandsOff.covers(url),
              SiteIcons.shared.needs(url) else { return }
        view.callAsyncJavaScript(Self.iconsCall, arguments: [:], in: nil, in: Page.world) { result in
            guard case .success(let value) = result, let strings = value as? [String] else { return }
            SiteIcons.shared.learn(strings.compactMap(URL.init(string:)), for: url)
        }
    }

    /// What the page says it is about (its meta description), for its
    /// history to be found by; never its own text, never on a hands-off host.
    private func learnAbout() {
        guard let url = view.url, ["http", "https"].contains(url.scheme ?? ""), !HandsOff.covers(url) else { return }
        let call = """
            const meta = document.querySelector('meta[name="description" i], meta[property="og:description" i]');
            return meta && meta.content ? String(meta.content).trim().slice(0, 400) : '';
            """
        view.callAsyncJavaScript(call, arguments: [:], in: nil, in: Page.world) { [weak self] result in
            guard let self, case .success(let value) = result, let text = value as? String else { return }
            history.described(text, url: url, space: space)
        }
    }

    // MARK: Another app's link

    fileprivate func openElsewhere(_ url: URL, clicked: Bool, mainFrame: Bool) {
        switch AppLink.answer(clicked: clicked, mainFrame: mainFrame, showing: host?.isShowing(self) == true,
                              asking: askingElsewhere, refusals: refusedElsewhere) {
        case .leave:
            closeIfOpenedForThis()
        case .open:
            hand(url)
        case .ask:
            guard let window = host?.hostWindow else { return }
            let alert = NSAlert()
            let asker = (committed ?? view.url)?.host ?? "This page"
            alert.messageText = "Open in Another App?"
            alert.informativeText = "\(asker) is opening a link for another app (\(url.scheme ?? ""):)."
            alert.addButton(withTitle: "Open")
            alert.addButton(withTitle: "Cancel")
            askingElsewhere = true
            alert.beginSheetModal(for: window) { [weak self] answer in
                guard let self else { return }
                askingElsewhere = false
                if answer == .alertFirstButtonReturn {
                    hand(url)
                } else {
                    refusedElsewhere += 1
                    closeIfOpenedForThis()
                }
            }
        }
    }

    /// To whichever app opens it.
    private func hand(_ url: URL) {
        NSWorkspace.shared.open(url)
        closeIfOpenedForThis()
    }

    /// A window a page opened only to go to another app has nothing to
    /// show, and goes, as one that closed itself would.
    private func closeIfOpenedForThis() {
        guard wasOpened, committed == nil else { return }
        host?.pageDidClose(self)
    }

    // MARK: Peek

    /// Whether a window this page opens can be a Peek over it: a page in a
    /// window's tab, not one in a Peek, a little window or a pop-up itself.
    var canPeek: Bool {
        host is WindowModel
    }

    /// A Peek over the page, in place of the one open. `configuration`:
    /// WebKit's, for a window the page opened, which WebKit loads itself;
    /// nil for a link, loaded here.
    @discardableResult
    func openPeek(_ url: URL?, configuration: WKWebViewConfiguration? = nil, width: Double? = nil,
                  height: Double? = nil) -> PeekPage {
        peek?.close()
        let made = PeekPage(opener: self, configuration: configuration, url: url, width: width, height: height)
        peek = made
        if configuration != nil {
            made.page.wasOpened = true
        } else if let url {
            made.page.load(url)
        }
        host?.pageDidChange(self)
        return made
    }

    /// The page is a tab's now, as it was: a Peek's or a little window's,
    /// opened in a tab. What it shows goes into the space's history.
    func becameTab() {
        history.adopted(url: view.url, title: view.title, entry: view.backForwardList.currentItem, space: space, tab: tab)
    }

    /// The Peek is gone, closed or given a tab. The tab may freeze now.
    func peekDidEnd(_ ended: PeekPage) {
        guard peek === ended else { return }
        peek = nil
        host?.pageDidChange(self)
        Task { @MainActor in Session.shared.pages.enforce() }
    }

    /// Whether a navigation leaves a pinned tab's site, for a Peek over the
    /// tab (Peek.opensFromPinned), as Arc keeps a pinned tab on its own site.
    private func peeksFromPinned(_ action: WKNavigationAction) -> Bool {
        let session = Session.shared
        guard canPeek, session.preferences.peekFromPinnedTabs, session.workspace.tab(tab)?.isPinned == true,
              host?.isShowing(self) == true else { return false }
        let kind: NewTabClick.Kind
        switch action.navigationType {
        case .linkActivated: kind = .link
        case .formSubmitted: kind = .form
        case .other: kind = .script
        default: kind = .history
        }
        return Peek.opensFromPinned(from: committed ?? view.url, to: action.request.url, kind: kind,
                                    method: action.request.httpMethod, mainFrame: action.targetFrame?.isMainFrame ?? true)
    }

    // MARK: Picture in picture

    /// Whether the page at `url` is given Document Picture-in-Picture (DocumentPicture).
    static func offersPicture(_ url: URL?) -> Bool {
        DocumentPicture.covers(url, extra: pictureTestHosts)
    }

    /// The window picture.js asked for, in place of the one open: one at a time, as in Chrome.
    private func openPicture(_ configuration: WKWebViewConfiguration, features: WKWindowFeatures,
                             request: DocumentPicture.Request) -> WKWebView {
        picture?.close()
        let window = PictureWindow(opener: self, configuration: configuration, features: features, request: request)
        window.automatic = enteringPicture
        picture = window
        return window.view
    }

    /// The window is gone, however it went. The tab may freeze now, once
    /// whatever closed the window (a tab closing, the freezer) is done.
    func pictureDidClose(_ window: PictureWindow) {
        guard picture === window else { return }
        picture = nil
        Task { @MainActor in Session.shared.pages.enforce() }
    }

    /// The tab is no longer on screen. Mid-call, a site that asked to be
    /// told (MediaSession's "enterpictureinpicture", Google Meet's way) is,
    /// and may open its window: Chrome does so on a tab switch for a page
    /// using the camera or microphone. The app's call counts as a click in
    /// WebKit while it runs, so the window the site opens in it is let open.
    func leftScreen() {
        guard view.cameraCaptureState != .none || view.microphoneCaptureState != .none else { return }
        enterPicture()
    }

    /// The site's handler for leaving the tab, called, if it has one.
    /// `otherwise`: what to do when the site has no handler to call.
    func enterPicture(otherwise: (() -> Void)? = nil) {
        guard picture == nil, !enteringPicture, !HandsOff.covers(view.url), !HandsOff.covers(committed),
              Self.offersPicture(committed ?? view.url)
        else { return }
        enteringPicture = true
        view.callAsyncJavaScript("return typeof __safienceEnterPicture === 'function' ? __safienceEnterPicture() : false",
                                 arguments: [:], in: nil, in: .page) { [weak self] result in
            self?.enteringPicture = false
            if case .success(let called) = result, called as? Bool == true { return }
            otherwise?()
        }
    }

    /// The tab is on screen again: a window the app opened for it goes, as Chrome's does.
    func cameOnScreen() {
        if picture?.automatic == true { picture?.close() }
    }

    /// Safience went behind another app, with this page on screen
    /// (Session.appWentBehind). A call on a site given Document
    /// Picture-in-Picture is told, as on a tab switch, and floats its own
    /// window; otherwise a video playing with sound, or in a call any
    /// playing video, goes into macOS's own picture in picture (VideoPicture).
    func appWentBehind() {
        guard picture == nil, !videoFloated, !floatingVideo, !enteringPicture,
              !HandsOff.covers(view.url), !HandsOff.covers(committed) else { return }
        videoWanted = true
        let inCall = view.cameraCaptureState != .none || view.microphoneCaptureState != .none
        // A site with no handler for it (Meet with its own setting off) gets its video floated instead.
        if inCall, Self.offersPicture(committed ?? view.url) {
            return enterPicture { [weak self] in self?.floatVideo(anyPlaying: true) }
        }
        floatVideo(anyPlaying: inCall)
    }

    private func floatVideo(anyPlaying: Bool) {
        guard videoWanted, !videoFloated, !floatingVideo else { return }
        floatingVideo = true
        view.callAsyncJavaScript(VideoPicture.float, arguments: ["anyPlaying": anyPlaying], in: nil, in: Page.world) { [weak self] result in
            guard let self else { return }
            self.floatingVideo = false
            guard case .success(let floated) = result, floated as? Bool == true else { return }
            self.videoFloated = true
            // Safience came back while the video went: back it comes.
            if !self.videoWanted { self.sinkVideo() }
        }
    }

    /// Safience is in front again, with this page on screen: what floated as it went behind comes back.
    func appCameBack() {
        cameOnScreen()
        sinkVideo()
    }

    /// The video that floated as Safience went behind, back in its page:
    /// for every live page as Safience comes back, on screen or not.
    func sinkVideo() {
        videoWanted = false
        guard videoFloated else { return }
        videoFloated = false
        guard !HandsOff.covers(view.url), !HandsOff.covers(committed) else { return }
        view.callAsyncJavaScript(VideoPicture.sink, arguments: [:], in: nil, in: Page.world) { _ in }
    }

    // MARK: When the page's process ends

    /// The page went blank: loaded again by itself unless it keeps ending,
    /// when it waits for Reload.
    fileprivate func processEnded() {
        picture?.close()
        videoFloated = false
        if crashes.shouldReload(at: Date()) {
            reload(byHand: false)
        } else {
            exhausted = true
            // Its own failure, not a form's nor an earlier address's: Try Again loads it again.
            sendingFailed = false
            failedURL = nil
            failure = "This page used too much memory and was closed several times. Reload to try again."
            host?.pageDidChange(self)
        }
    }
}

// MARK: - WebKit's questions

extension Page: WKNavigationDelegate, WKUIDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        let mainFrame = navigationAction.targetFrame?.isMainFrame ?? true
        if let url = navigationAction.request.url, AppLink.isOne(scheme: url.scheme), !Extensions.shared.isExtensionPage(url) {
            decisionHandler(.cancel)
            openElsewhere(url, clicked: navigationAction.navigationType == .linkActivated, mainFrame: mainFrame)
            return
        }
        if navigationAction.shouldPerformDownload {
            return decisionHandler(.download)
        }
        // Between a website and an extension's own page: WebKit needs a view
        // of the other kind, so the page opens in a new tab.
        if mainFrame, let url = navigationAction.request.url,
           ["http", "https", Extensions.scheme].contains(url.scheme?.lowercased() ?? ""),
           Extensions.shared.isExtensionPage(url) != isExtensionPage,
           host?.page(self, openInNewTab: url, inFront: true) == true {
            return decisionHandler(.cancel)
        }
        let choice = newTabChoice(for: navigationAction)
        if choice != .here, let url = navigationAction.request.url,
           host?.page(self, openInNewTab: url, inFront: choice == .inFront) == true {
            return decisionHandler(.cancel)
        }
        if let url = navigationAction.request.url, peeksFromPinned(navigationAction) {
            decisionHandler(.cancel)
            openPeek(url)
            return
        }
        if mainFrame { history.decided(navigationAction.navigationType, url: navigationAction.request.url) }
        if mainFrame, let request = askingInLightOrDark(navigationAction) {
            decisionHandler(.cancel)
            webView.load(request)
            return
        }
        if mainFrame {
            prepare(for: navigationAction.request.url)
            askingForPage = (navigationAction.request.httpMethod ?? "GET").uppercased() == "GET"
        }
        decisionHandler(.allow)
    }

    /// The request again with the screen's light or dark, for a host that
    /// asks for it as a header and a request without it; nil otherwise. A
    /// step back or a reload goes as it was made, and a hands-off page is
    /// never asked for twice. Notes what the request was, for its answer.
    private func askingInLightOrDark(_ action: WKNavigationAction) -> URLRequest? {
        let request = action.request
        let repeatable = ![.backForward, .reload, .formResubmitted].contains(action.navigationType)
            && (request.httpMethod ?? "GET").uppercased() == "GET" && !HandsOff.covers(request.url)
        hintCarried = ColorSchemeHint.carries(request.allHTTPHeaderFields)
        hintRepeatable = repeatable
        guard repeatable, let value = Self.colorHint.missing(url: request.url, method: request.httpMethod,
                                                             headers: request.allHTTPHeaderFields, dark: isDark)
        else { return nil }
        var again = request
        again.setValue(value, forHTTPHeaderField: ColorSchemeHint.header)
        return again
    }

    private var isDark: Bool {
        view.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void) {
        // A page from a host that asks for the screen's light or dark, which came light on a dark screen: again, dark.
        if navigationResponse.isForMainFrame, let response = navigationResponse.response as? HTTPURLResponse,
           let url = response.url, !HandsOff.covers(url),
           let value = Self.colorHint.answered(url: url, acceptCH: response.value(forHTTPHeaderField: "Accept-CH"),
                                               criticalCH: response.value(forHTTPHeaderField: "Critical-CH"),
                                               requestCarried: hintCarried, repeatable: hintRepeatable, dark: isDark) {
            decisionHandler(.cancel)
            var again = URLRequest(url: url)
            again.setValue(value, forHTTPHeaderField: ColorSchemeHint.header)
            webView.load(again)
            return
        }
        // What WebKit can't show (a ZIP, an installer) and what the server says to save is a download.
        let attachment = (navigationResponse.response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Content-Disposition")?.lowercased().hasPrefix("attachment") == true
        decisionHandler(navigationResponse.canShowMIMEType && !attachment ? .allow : .download)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        downloading(download)
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        downloading(download)
    }

    /// A tab that was only ever the file's way in, with no page of its own
    /// to show, goes once the download has begun, as Safari's does.
    private func downloading(_ download: WKDownload) {
        Downloads.shared.adopt(download, from: self)
        if committed == nil, !view.canGoBack { host?.pageDidClose(self) }
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        Session.shared.pages.navigationChanged(self, committed: true)
        // A new document: the old one's picture-in-picture window goes with it,
        // as in Chrome, and WebKit takes the old document's video out of its own.
        picture?.close()
        videoFloated = false
        committed = webView.url
        failure = nil
        failedURL = nil
        sendingFailed = false
        refusedElsewhere = 0
        history.committed(url: webView.url, title: webView.title, entry: webView.backForwardList.currentItem,
                          space: space, tab: tab)
        passwordField = false
        changed()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        learnIcons()
        learnAbout()
        host?.pageDidChange(self)
        #if DEBUG
        testPictureIfAsked()
        #endif
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        failed(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        failed(error)
    }

    /// A load that failed for a reason worth telling: not one that was
    /// stopped, nor one that became a download.
    private func failed(_ error: Error) {
        let error = error as NSError
        let quiet = (error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled)
            || (error.domain == "WebKitErrorDomain" && [102, 204].contains(error.code))
        guard !quiet else { return }
        history.failed()
        failure = error.localizedDescription
        failedURL = askingForPage ? error.userInfo[NSURLErrorFailingURLErrorKey] as? URL : nil
        sendingFailed = !askingForPage
        host?.pageDidChange(self)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        processEnded()
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // Another app's link asked for in a window of its own: theirs to
        // open, with no tab made for a page that will never be.
        if let url = navigationAction.request.url, AppLink.isOne(scheme: url.scheme), !Extensions.shared.isExtensionPage(url) {
            openElsewhere(url, clicked: navigationAction.navigationType == .linkActivated,
                          mainFrame: navigationAction.targetFrame?.isMainFrame ?? true)
            return nil
        }
        // picture.js's window, from the page itself and not a frame in it: it floats (PictureWindow).
        // Anywhere else, the same address is an ordinary pop-up.
        if let request = DocumentPicture.Request(url: navigationAction.request.url), navigationAction.sourceFrame.isMainFrame,
           Self.offersPicture(committed ?? view.url) {
            // Asked for on leaving the tab, but the tab is back on screen, with Safience in front, by now: no window.
            if enteringPicture, host?.isShowing(self) == true, NSApp.isActive { return nil }
            return openPicture(configuration, features: windowFeatures, request: request)
        }
        // While the app calls the site's handler for leaving the tab, the
        // click WebKit grants the call opens the site's picture window only.
        if enteringPicture { return nil }
        // Open Link in Peek, chosen from the page's menu a moment ago.
        if let asked = peekAsked {
            peekAsked = nil
            if Date().timeIntervalSince(asked) < 5, canPeek {
                return openPeek(navigationAction.request.url, configuration: configuration).page.view
            }
        }
        let made = host?.page(self, open: configuration, for: navigationAction, features: windowFeatures)
        if let child = (made as? PageView)?.page, child !== self {
            child.wasOpened = true
        }
        return made
    }

    func webViewDidClose(_ webView: WKWebView) {
        host?.pageDidClose(self)
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor () -> Void) {
        let alert = NSAlert()
        alert.messageText = frame.securityOrigin.host.isEmpty ? "This page says" : "\(frame.securityOrigin.host) says"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        present(alert) { _ in completionHandler() }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = frame.securityOrigin.host.isEmpty ? "This page asks" : "\(frame.securityOrigin.host) asks"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        present(alert) { completionHandler($0 == .alertFirstButtonReturn) }
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor (String?) -> Void) {
        let alert = NSAlert()
        alert.messageText = frame.securityOrigin.host.isEmpty ? "This page asks" : "\(frame.securityOrigin.host) asks"
        alert.informativeText = prompt
        let field = NSTextField(string: defaultText ?? "")
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        present(alert) { completionHandler($0 == .alertFirstButtonReturn ? field.stringValue : nil) }
    }

    /// A page's dialog belongs to its visible window. Offscreen pages answer
    /// as cancelled instead of interrupting another window with an app-modal alert.
    private func present(_ alert: NSAlert, _ done: @escaping (NSApplication.ModalResponse) -> Void) {
        guard let host, host.isShowing(self), let window = host.hostWindow else {
            done(.cancel)
            return
        }
        alert.beginSheetModal(for: window, completionHandler: done)
    }

    /// A page's upload field: the files chosen in the system's panel, which
    /// the sandbox then lets the page read.
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        let done: (NSApplication.ModalResponse) -> Void = { response in
            completionHandler(response == .OK ? panel.urls : nil)
        }
        if let window = host?.hostWindow {
            panel.beginSheetModal(for: window, completionHandler: done)
        } else {
            done(panel.runModal())
        }
    }
}
