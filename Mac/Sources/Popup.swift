import AppKit
import PadCore
import WebKit

/// A window a page opened at a size of its own (a sign-in with Google or
/// Apple, a share dialog) where no Peek can have it: from a page in a Peek,
/// a little window or a pop-up itself, or from a tab not on screen. A tab's
/// page on screen has its pop-ups in a Peek (PeekPage). It sits over the
/// window that opened it, in the same space's store, and closes by itself
/// when the page closes it.
@MainActor
final class Popup: NSObject, PageHost, NSWindowDelegate {
    /// The pop-ups open now: each holds itself until its window closes.
    private static var open: Set<Popup> = []

    let page: Page
    /// The page that opened it, so a Peek going takes its pop-ups with it (close(openedBy:)).
    private weak var opener: Page?
    private let panel: NSWindow
    /// The window it stands over closing: it closes too.
    private var parentClosing: NSObjectProtocol?

    static func open(from opener: Page, configuration: WKWebViewConfiguration, features: WKWindowFeatures,
                     over parent: NSWindow?) -> WKWebView {
        let popup = Popup(opener: opener, configuration: configuration, features: features, over: parent)
        open.insert(popup)
        return popup.page.view
    }

    /// Each pop-up `opener` opened, closed: a Peek's, as the Peek goes, so
    /// none is left over the window with nothing under it that opened it.
    static func close(openedBy opener: Page) {
        for popup in open where popup.opener === opener {
            popup.panel.close()
        }
    }

    private init(opener: Page, configuration: WKWebViewConfiguration, features: WKWindowFeatures, over parent: NSWindow?) {
        // A page of no tab: what it says about itself is kept nowhere.
        page = Page(tab: UUID(), space: opener.space, configuration: configuration)
        self.opener = opener
        let width = CGFloat(features.width?.doubleValue ?? 520)
        let height = CGFloat(features.height?.doubleValue ?? 640)
        panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: max(width, 320), height: max(height, 240)),
                         styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        super.init()
        page.host = self
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.contentView = page.view
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
        let title = page.view.title ?? ""
        panel.title = title.isEmpty ? (page.view.url?.host ?? "") : title
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
