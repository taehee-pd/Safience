import AppKit
import PadCore
import SwiftUI
import WebKit

/// A little window, as Arc's Little Arc: a link from another app (unless
/// Settings › General › Links says a tab), or one asked for with ⌃⌥N, in a
/// small window of its own with next to nothing round the page: back, the
/// site and its address to type into, Copy Link, and Open in New Tab (⌃⌥O),
/// which takes the page, as it is, into a tab of a browser window.
///
/// Its page is in a space's store from the start, the space of the window
/// in front, so a link to a site you're signed in to there opens signed in.
/// Open in New Tab's menu takes it to another space instead, where it loads
/// afresh in that space's store. The window's ground is its space's colour,
/// as a browser window's is. Until it is in a tab, its pages are in no tab
/// and so in no history, as a pop-up's aren't.
@MainActor
final class LittleWindow: NSObject, ObservableObject, PageHost, NSWindowDelegate {
    /// A page of no tab until Open in New Tab gives it one.
    let page: Page
    let space: UUID
    private let window: NSWindow

    // The page as the header shows it.
    @Published private(set) var url: URL?
    @Published private(set) var canGoBack = false
    @Published private(set) var loading = false
    @Published private(set) var progress = 0.0
    /// Why its page didn't load, shown in its place (FailureView).
    @Published private(set) var failure: String?
    /// Moves on for the address to take the keys: a new little window, or ⌘L.
    @Published private(set) var typingRequests = 0
    /// Closed, or its page given to a tab.
    private var over = false

    /// The window's size when the screen has room: a page of reading, as Little Arc's.
    static let standard = CGSize(width: 680, height: 780)

    /// A little window for `url`, in `space` or the space of the window in
    /// front; with no address, empty, its address field taking the keys.
    /// `configuration`: WebKit's, for a window a little window's page opened.
    @discardableResult
    static func open(_ url: URL?, in space: UUID? = nil, configuration: WKWebViewConfiguration? = nil) -> LittleWindow {
        let session = Session.shared
        let space = space.flatMap { session.workspace.space($0)?.id }
            ?? session.frontWindow?.spaceID ?? session.workspace.firstSpace.id
        let made = LittleWindow(url: url, space: space, configuration: configuration)
        LittleWindows.shared.opened(made)
        return made
    }

    private init(url: URL?, space: UUID, configuration: WKWebViewConfiguration?) {
        self.space = space
        page = Page(tab: UUID(), space: space, configuration: configuration)
        let screen = NSApp.keyWindow?.screen ?? NSScreen.main
        let room = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let size = CGSize(width: min(Self.standard.width, room.width * 0.9), height: min(Self.standard.height, room.height * 0.9))
        window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        super.init()
        self.url = url
        page.host = self
        window.delegate = self
        window.isReleasedWhenClosed = false
        // Not brought back at the next launch: a little window is for a look, now.
        window.isRestorable = false
        window.tabbingMode = .disallowed
        // Its green button zooms it: a little window is never the whole screen.
        window.collectionBehavior.insert(.fullScreenNone)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        // Clear, for its ground's glass to show what is behind it, as a browser window's (Backdrop).
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentMinSize = NSSize(width: 420, height: 320)
        window.title = url?.host() ?? "Little Window"
        let content = NSHostingView(rootView: LittleWindowView(little: self))
        content.sizingOptions = []
        window.contentView = content
        // AppKit's own buttons hidden: the header has them on its line (WindowButtons).
        for kind: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(kind)?.isHidden = true
        }
        place(in: room)
        if configuration == nil {
            if let url { page.load(url) } else { typingRequests += 1 }
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        if url != nil { focusPage() }
    }

    /// In the middle of the screen's room, a step down and along from a little window there already.
    private func place(in room: NSRect) {
        let size = window.frame.size
        var origin = NSPoint(x: room.midX - size.width / 2, y: room.midY - size.height / 2)
        let others = LittleWindows.shared.frames
        while others.contains(where: { abs($0.minX - origin.x) < 4 && abs($0.maxY - (origin.y + size.height)) < 4 }) {
            origin.x += 24
            origin.y -= 24
        }
        origin.x = min(max(origin.x, room.minX), room.maxX - size.width)
        origin.y = min(max(origin.y, room.minY), room.maxY - size.height)
        window.setFrameOrigin(origin)
    }

    var frame: NSRect {
        window.frame
    }

    // MARK: What the header does

    func back() {
        page.view.goBack()
    }

    func forward() {
        page.view.goForward()
    }

    /// ⌘R, and Try Again over a page that couldn't load: the address that failed.
    func reload() {
        if page.failure != nil { page.retry() } else { page.reload() }
    }

    func focusPage() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.window.makeFirstResponder(self.page.view)
        }
    }

    /// The address field takes the keys (⌘L).
    func startTyping() {
        typingRequests += 1
    }

    /// A line typed in the address field: an address, or a search with the chosen engine.
    func go(_ typed: String) {
        guard let url = Destination.url(for: typed, engine: Session.shared.preferences.engine) else { return }
        page.load(url)
        focusPage()
    }

    func copyLink() {
        guard let url = page.view.url ?? url else { return }
        WindowModel.copy(url)
    }

    /// The page in a tab of a browser window. In its own space it goes as it
    /// is, signed in, scrolled and all; in another (`other`) it loads afresh
    /// in that space's store. The window that shows the space comes forward,
    /// or the window in front goes to the space; with no window open, a new one.
    func openInTab(space other: UUID? = nil) {
        guard !over else { return }
        let session = Session.shared
        let target = other ?? space
        let address = page.view.url ?? url
        let id: UUID?
        if target == space {
            over = true
            page.host = nil
            session.pages.adopt(page)
            id = session.change { workspace -> UUID? in
                guard let id = workspace.openTab(address, in: target, id: page.tab) else { return nil }
                workspace.record(id, url: nil, title: page.view.title)
                return id
            }
            if id == nil { session.pages.close(page.tab) } else { page.becameTab() }
        } else {
            guard let address else { return }
            id = session.change { $0.openTab(address, in: target) }
        }
        window.close()
        guard let id else { return }
        if let shower = session.allWindows.first(where: { $0.spaceID == target }) ?? session.frontWindow {
            shower.select(id)
            NSApp.activate()
            shower.window?.makeKeyAndOrderFront(nil)
        } else {
            session.openWindow?(target)
        }
    }

    func close() {
        window.performClose(nil)
    }

    // MARK: NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        if !over {
            over = true
            page.tearDown()
        }
        window.delegate = nil
        // Its view holds it, as it holds the window: let go, so it goes.
        window.contentView = nil
        LittleWindows.shared.closed(self)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        LittleWindows.shared.becameKey(self)
    }

    func windowDidResignKey(_ notification: Notification) {
        LittleWindows.shared.resignedKey(self)
    }

    // MARK: PageHost

    var hostWindow: NSWindow? {
        window
    }

    func pageDidChange(_ page: Page) {
        guard !over else { return }
        let view = page.view
        url = view.url ?? page.committed ?? url
        canGoBack = view.canGoBack
        loading = view.isLoading
        progress = view.estimatedProgress
        failure = page.failure
        let title = view.title ?? ""
        window.title = title.isEmpty ? (url?.host() ?? "Little Window") : title
    }

    func isShowing(_ page: Page) -> Bool {
        window.isVisible && !window.isMiniaturized
    }

    /// A pop-up stands over the little window; a link that asks for a
    /// window of its own gets a little window of its own, tied to this page.
    func page(_ page: Page, open configuration: WKWebViewConfiguration, for action: WKNavigationAction,
              features: WKWindowFeatures) -> WKWebView? {
        if features.width != nil || features.height != nil {
            return Popup.open(from: page, configuration: configuration, features: features, over: window)
        }
        return LittleWindow.open(action.request.url, in: space, configuration: configuration).page.view
    }

    /// A ⌘-click: a tab of the space, in a browser window, which comes
    /// forward with ⇧; without, the space's tab on screen stays so.
    func page(_ page: Page, openInNewTab url: URL, inFront: Bool) -> Bool {
        let session = Session.shared
        let selected = session.workspace.space(space)?.selected
        guard let id = session.change({ $0.openTab(url, in: space) }) else { return false }
        guard let shower = session.allWindows.first(where: { $0.spaceID == space }) ?? session.frontWindow else {
            session.openWindow?(space)
            return true
        }
        if inFront {
            shower.select(id)
            NSApp.activate()
            shower.window?.makeKeyAndOrderFront(nil)
        } else if let selected {
            session.change { $0.select(selected) }
        }
        return true
    }

    func pageDidClose(_ page: Page) {
        close()
    }
}

/// The little windows open, each held here until it closes, and the one
/// with the keys, for the menu bar's ⌃⌥O, ⌘W, ⌘L, ⌘R, ⌘[, ⌘] and ⇧⌘C.
@MainActor
final class LittleWindows: ObservableObject {
    static let shared = LittleWindows()

    private var open: [LittleWindow] = []
    @Published private(set) var key: LittleWindow?

    var frames: [NSRect] {
        open.map(\.frame)
    }

    fileprivate func opened(_ little: LittleWindow) {
        open.append(little)
    }

    fileprivate func closed(_ little: LittleWindow) {
        open.removeAll { $0 === little }
        if key === little { key = nil }
    }

    fileprivate func becameKey(_ little: LittleWindow) {
        key = little
    }

    fileprivate func resignedKey(_ little: LittleWindow) {
        if key === little { key = nil }
    }
}

// MARK: What it shows

/// The window: the space's colour as its ground, the header's one row, and
/// the page as a card under it, as a browser window's page is.
private struct LittleWindowView: View {
    @ObservedObject var little: LittleWindow
    @ObservedObject private var session = Session.shared

    var body: some View {
        let colour = session.workspace.space(little.space)?.color ?? .blue
        let shape = RoundedRectangle(cornerRadius: Metrics.card, style: .continuous)
        ZStack {
            SpaceWash(color: colour)
                .accessibilityHidden(true)
            VStack(spacing: Metrics.bezel) {
                LittleHeader(little: little)
                ZStack(alignment: .top) {
                    shape
                        .fill(Color(nsColor: .textBackgroundColor))
                        .shadow(color: .black.opacity(0.16), radius: 1, y: 0.5)
                        .shadow(color: .black.opacity(0.08), radius: 14, y: 6)
                    PageSurface(page: little.page)
                        .clipShape(shape)
                    if let failure = little.failure {
                        FailureView(message: failure, url: little.url) { little.reload() }
                            .clipShape(shape)
                    }
                    if little.loading {
                        GeometryReader { box in
                            Capsule()
                                .fill(colour.color.opacity(0.8))
                                .frame(width: max(box.size.width * little.progress, 12), height: 2)
                                .animation(.easeOut(duration: 0.2), value: little.progress)
                        }
                        .frame(height: 2)
                        .padding(.horizontal, Metrics.card)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                    }
                }
                .animation(.bar, value: little.loading)
            }
            .padding(Metrics.bezel)
        }
        .ignoresSafeArea()
        .environment(\.spaceColor, colour)
    }
}

/// The header: the window's buttons, back, the address, Copy Link and Open
/// in New Tab, whose menu has the other spaces. Its ground moves the window.
private struct LittleHeader: View {
    @ObservedObject var little: LittleWindow
    @ObservedObject private var session = Session.shared

    var body: some View {
        HStack(spacing: 6) {
            WindowButtons()
                .frame(width: WindowButtons.width, height: WindowButtons.side)
                .padding(.leading, Metrics.gap - Metrics.bezel)
                .padding(.trailing, 6)
            if little.canGoBack {
                PlainIcon("chevron.left", help: "Back") { little.back() }
            }
            LittleAddress(little: little)
            Spacer(minLength: 0)
            PlainIcon("link", help: "Copy Link (⇧⌘C)", enabled: little.url != nil) { little.copyLink() }
            PlainIcon("arrow.up.left.and.arrow.down.right", help: "Open in New Tab (⌃⌥O)", enabled: little.url != nil) {
                little.openInTab()
            }
            .contextMenu { spacesMenu }
            Menu { spacesMenu } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: Metrics.control)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(little.url == nil)
            .help("Open in Another Space")
            .accessibilityLabel("Open in Another Space")
        }
        .frame(height: Metrics.control)
        .padding(.top, Metrics.gap - Metrics.bezel)
        .padding(.trailing, 2)
        .background {
            Color.clear
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())
        }
    }

    /// Each space, the little window's own first, for the page to open in.
    @ViewBuilder
    private var spacesMenu: some View {
        let spaces = session.workspace.spaces
        ForEach(spaces.filter { $0.id == little.space } + spaces.filter { $0.id != little.space }) { space in
            Button {
                little.openInTab(space: space.id)
            } label: {
                Label("Open in \u{201C}\(space.name)\u{201D}", systemImage: space.symbol)
            }
        }
    }
}

/// The page's site, as a person reads its host; clicked, or with ⌘L, its
/// whole address to change, as the browser's address is. Return goes there,
/// Escape leaves it as it was.
private struct LittleAddress: View {
    @ObservedObject var little: LittleWindow
    @State private var typed = ""
    @State private var editing = false
    @FocusState private var focused: Bool
    @State private var hovering = false

    var body: some View {
        let shape = Capsule()
        HStack(spacing: 6) {
            SiteIconView(url: little.url, size: 14)
            if editing {
                TextField("Search or enter address", text: $typed)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit {
                        editing = false
                        little.go(typed)
                    }
                    .onExitCommand {
                        editing = false
                        little.focusPage()
                    }
            } else {
                Text(host)
                    .foregroundStyle(little.url == nil ? HierarchicalShapeStyle.tertiary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .font(.system(size: 12.5))
        .padding(.horizontal, 10)
        .frame(height: Metrics.control - 2)
        .frame(minWidth: 160, maxWidth: 360, alignment: .leading)
        .contentShape(shape)
        .background(Highlight(hovering: hovering && !editing, shape: shape))
        .glassEffect(.regular, in: shape)
        .onHover { inside in withAnimation(.hover) { hovering = inside } }
        .onTapGesture { if !editing { startTyping() } }
        .onChange(of: little.typingRequests) { _, _ in startTyping() }
        .onChange(of: focused) { _, now in if !now { editing = false } }
        .onAppear { if little.typingRequests > 0 { startTyping() } }
        .help(little.url.map(Destination.pretty) ?? "")
        .accessibilityElement(children: .combine)
        .accessibilityLabel(editing ? "Address" : "Address, \(host)")
        .accessibilityAddTraits(editing ? [] : .isButton)
    }

    private var host: String {
        guard let host = little.url?.host() else { return little.loading ? "Loading…" : "Search or enter address" }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private func startTyping() {
        typed = little.url.map { Destination.editable($0, engine: Session.shared.preferences.engine) } ?? ""
        editing = true
        DispatchQueue.main.async { focused = true }
    }
}
