import AppKit
import PadCore
import WebKit

/// A window a page opened at a size of its own: a sign-in with Google or
/// Apple, a share dialog. It sits over the window that opened it, in the
/// same space's store, and closes by itself when the page closes it.
@MainActor
final class Popup: NSObject, PageHost, NSWindowDelegate {
    /// The pop-ups open now: each holds itself until its window closes.
    private static var open: Set<Popup> = []

    let page: Page
    private let panel: NSWindow
    private let address = NSTextField(labelWithString: "Loading…")
    private let security = NSImageView()
    private let status = NSTextField(wrappingLabelWithString: "Loading page…")
    private let progress = NSProgressIndicator()
    private let recovery = NSButton(title: "Reload", target: nil, action: nil)
    private let statusBox = NSStackView()
    private var announced: String?
    /// The window it stands over closing: it closes too.
    private var parentClosing: NSObjectProtocol?

    static func open(from opener: Page, configuration: WKWebViewConfiguration, features: WKWindowFeatures,
                     over parent: NSWindow?) -> WKWebView {
        let popup = Popup(opener: opener, configuration: configuration, features: features, over: parent)
        open.insert(popup)
        return popup.page.view
    }

    private init(opener: Page, configuration: WKWebViewConfiguration, features: WKWindowFeatures, over parent: NSWindow?) {
        // A page of no tab: what it says about itself is kept nowhere.
        page = Page(tab: UUID(), space: opener.space, configuration: configuration)
        let width = CGFloat(features.width?.doubleValue ?? 520)
        let height = CGFloat(features.height?.doubleValue ?? 640)
        panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: max(width, 320), height: max(height, 240)),
                         styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        super.init()
        page.host = self
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        makeContent()
        panel.title = "Loading…"
        if let parent {
            let frame = parent.frame
            panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.midY - panel.frame.height / 2))
            parent.addChildWindow(panel, ordered: .above)
            parentClosing = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: parent,
                                                                   queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.panel.close() }
            }
        } else {
            panel.center()
        }
        panel.makeKeyAndOrderFront(nil)
    }

    private func makeContent() {
        let close = NSButton(title: "Close", target: self, action: #selector(closePopup))
        security.imageScaling = .scaleProportionallyDown
        security.setAccessibilityElement(true)
        address.lineBreakMode = .byTruncatingMiddle
        address.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let header = NSStackView(views: [security, address, close])
        header.spacing = 8
        header.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        statusBox.orientation = .vertical
        statusBox.alignment = .leading
        statusBox.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        statusBox.spacing = 6
        recovery.target = self
        recovery.action = #selector(recoverPage)
        progress.style = .bar
        progress.minValue = 0
        progress.maxValue = 1
        [status, progress, recovery].forEach(statusBox.addArrangedSubview)
        let stack = NSStackView(views: [header, statusBox, page.view])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        let content = NSView()
        panel.contentView = content
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
            statusBox.widthAnchor.constraint(equalTo: stack.widthAnchor),
            page.view.widthAnchor.constraint(equalTo: stack.widthAnchor),
            progress.widthAnchor.constraint(equalTo: statusBox.widthAnchor, constant: -24),
            security.widthAnchor.constraint(equalToConstant: 16),
        ])
    }

    @objc private func closePopup() { panel.close() }
    @objc private func recoverPage() {
        if page.googleRefused, page.view.canGoBack { page.view.goBack() } else { page.reload() }
    }

    func windowWillClose(_ notification: Notification) {
        if let parentClosing { NotificationCenter.default.removeObserver(parentClosing) }
        panel.parent?.removeChildWindow(panel)
        page.tearDown()
        Popup.open.remove(self)
    }

    // MARK: PageHost

    var hostWindow: NSWindow? {
        panel
    }

    func pageDidChange(_ page: Page) {
        let url = page.displayURL
        let title = page.view.title ?? ""
        panel.title = title.isEmpty ? (url?.host ?? "Loading…") : title
        address.stringValue = url.map(Destination.pretty) ?? "Loading…"
        address.setAccessibilityLabel(url?.absoluteString ?? "Loading page")
        let secure = url?.scheme == "https" && page.view.hasOnlySecureContent && page.failure == nil
        security.image = NSImage(systemSymbolName: secure ? "lock.fill" : "exclamationmark.triangle", accessibilityDescription: nil)
        security.contentTintColor = secure ? .systemGreen : .systemOrange
        security.setAccessibilityLabel(secure ? "Secure connection" : "Connection is not verified as secure")
        security.isHidden = url == nil
        let problem = page.googleRefused ? SignIn.fallback : page.failure
            ?? (page.exhausted ? "This page stopped after repeated memory problems. Close another tab, then reload." : nil)
        status.stringValue = problem ?? "Loading page…"
        statusBox.isHidden = problem == nil && !page.view.isLoading
        progress.isHidden = problem != nil || !page.view.isLoading
        progress.doubleValue = page.view.estimatedProgress
        recovery.isHidden = problem == nil
        recovery.title = page.googleRefused && page.view.canGoBack ? "Go Back" : "Reload"
        if let problem, problem != announced {
            announced = problem
            NSAccessibility.post(element: panel, notification: .announcementRequested,
                                 userInfo: [.announcement: problem, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        } else if problem == nil { announced = nil }

    }

    func isShowing(_ page: Page) -> Bool {
        panel.isVisible
    }

    func page(_ page: Page, open configuration: WKWebViewConfiguration, for action: WKNavigationAction,
              features: WKWindowFeatures) -> WKWebView? {
        Popup.open(from: page, configuration: configuration, features: features, over: panel)
    }

    /// No tabs here: the page goes there itself.
    func page(_ page: Page, openInNewTab url: URL, inFront: Bool) -> Bool {
        false
    }

    func pageDidClose(_ page: Page) {
        panel.close()
    }
}
