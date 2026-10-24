import AppKit
import Combine
import PadCore
import WebKit

/// Safience's tabs and windows, as extensions see them.
///
/// Chrome's windows each hold tabs of their own. Safience's spaces hold the
/// tabs, and every window showing a space lists all of them; only the tab on
/// screen is the window's own. So, to extensions, each space is one window,
/// as the person sees it too, and a frozen tab, with no page until it is
/// shown again, is like a tab Chrome has discarded: listed, with its address
/// and title, and no page to send a message to.
///
/// What changes is told to each space's controller from the workspace's own
/// changes: tabs opened, closed and moved, the one selected, their titles,
/// addresses and pins.
@MainActor
final class ExtensionTabs {
    private var tabs: [UUID: ExtensionTab] = [:]
    private var windows: [UUID: SpaceWindow] = [:]
    private var last: Workspace?
    private var watching: AnyCancellable?
    private var keyWatch: NSObjectProtocol?

    func start() {
        last = Session.shared.workspace
        // @Published tells before the new workspace is in place, and the
        // tabs read the workspace: told on the turn after.
        watching = Session.shared.$workspace.receive(on: DispatchQueue.main).sink { [weak self] next in
            MainActor.assumeIsolated { self?.changed(to: next) }
        }
        keyWatch = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated { self?.focused(note.object as? NSWindow) }
        }
    }

    func tab(_ id: UUID, in space: UUID) -> ExtensionTab {
        if let tab = tabs[id], tab.space == space { return tab }
        let tab = ExtensionTab(id: id, space: space)
        tabs[id] = tab
        return tab
    }

    func window(for space: UUID) -> SpaceWindow {
        if let window = windows[space] { return window }
        let window = SpaceWindow(space: space)
        windows[space] = window
        return window
    }

    /// A tab an extension opened: in the space, loaded at once even off
    /// screen, since extensions open tabs behind and wait for them. One on
    /// an extension's own page gets a page made from the extension's
    /// configuration, as WebKit needs.
    func open(_ url: URL?, in space: UUID, active: Bool, pinned: Bool, context: WKWebExtensionContext) -> ExtensionTab? {
        let session = Session.shared
        let selected = session.workspace.space(space)?.selected
        guard let id = session.change({ $0.openTab(url, in: space) }), let record = session.workspace.tab(id) else { return nil }
        // Opening selects; a tab opened behind leaves the selection as it was.
        if !active, let selected { session.change { $0.select(selected) } }
        if pinned { session.change { _ = $0.pin(id) } }
        if let url, Extensions.shared.isExtensionPage(url), let configuration = context.webViewConfiguration {
            let page = session.pages.adopt(tab: id, space: space, configuration: configuration, extensionPage: true)
            page.load(url)
        } else if url != nil {
            _ = session.pages.page(for: record, in: space)
        }
        if active {
            let window = session.allWindows.first { $0.spaceID == space && $0.window?.isKeyWindow == true }
                ?? session.allWindows.first { $0.spaceID == space }
            window?.select(id)
        }
        return tab(id, in: space)
    }

    // MARK: Telling the controllers

    private func changed(to next: Workspace) {
        guard let before = last else { last = next; return }
        last = next
        let extensions = Extensions.shared
        for space in next.spaces {
            guard !extensions.on(in: space.id).isEmpty else { continue }
            let controller = extensions.controller(for: space.id)
            let old = before.space(space.id)
            let oldTabs = Dictionary(uniqueKeysWithValues: (old?.tabs ?? []).map { ($0.id, $0) })
            // Order among the tabs there before and after: a tab closed or
            // opened shifts the others' indexes without moving them.
            let kept = Set(space.tabs.map(\.id)).intersection(oldTabs.keys)
            let oldOrder = (old?.tabs ?? []).map(\.id).filter(kept.contains)
            let newOrder = space.tabs.map(\.id).filter(kept.contains)
            for record in space.tabs {
                let adapter = tab(record.id, in: space.id)
                guard let was = oldTabs[record.id] else {
                    controller.didOpenTab(adapter)
                    continue
                }
                var changes: WKWebExtension.TabChangedProperties = []
                if was.url != record.url { changes.insert(.URL) }
                if was.title != record.title { changes.insert(.title) }
                if was.isPinned != record.isPinned { changes.insert(.pinned) }
                if !changes.isEmpty { controller.didChangeTabProperties(changes, for: adapter) }
                if oldOrder.firstIndex(of: record.id) != newOrder.firstIndex(of: record.id),
                   let from = old?.tabs.firstIndex(where: { $0.id == record.id }) {
                    controller.didMoveTab(adapter, from: from, in: window(for: space.id))
                }
            }
            let now = Set(space.tabs.map(\.id))
            for record in old?.tabs ?? [] where !now.contains(record.id) {
                controller.didCloseTab(tab(record.id, in: space.id), windowIsClosing: false)
                tabs[record.id] = nil
            }
            if old?.selected != space.selected, let selected = space.selected {
                controller.didActivateTab(tab(selected, in: space.id), previousActiveTab: old?.selected.map { tab($0, in: space.id) })
            }
        }
    }

    /// A page started or finished loading: its tab's loading changed.
    func loadingChanged(_ page: Page) {
        guard !Extensions.shared.on(in: page.space).isEmpty else { return }
        Extensions.shared.controller(for: page.space).didChangeTabProperties(.loading, for: tab(page.tab, in: page.space))
    }

    private func focused(_ nsWindow: NSWindow?) {
        let model = Session.shared.allWindows.first { $0.window === nsWindow }
        for space in Session.shared.workspace.spaces where !Extensions.shared.on(in: space.id).isEmpty {
            let controller = Extensions.shared.controller(for: space.id)
            controller.didFocusWindow(model?.spaceID == space.id ? window(for: space.id) : nil)
        }
    }
}

/// One tab, kept by its id apart from its page, which freezing lets go.
@MainActor
final class ExtensionTab: NSObject, WKWebExtensionTab {
    let id: UUID
    let space: UUID

    init(id: UUID, space: UUID) {
        self.id = id
        self.space = space
    }

    private var record: TabRecord? {
        Session.shared.workspace.tab(id)
    }

    private var view: WKWebView? {
        Session.shared.pages.live[id]?.view
    }

    func window(for context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        Extensions.shared.tabs.window(for: space)
    }

    func indexInWindow(for context: WKWebExtensionContext) -> Int {
        Session.shared.workspace.space(space)?.tabs.firstIndex { $0.id == id } ?? 0
    }

    func webView(for context: WKWebExtensionContext) -> WKWebView? {
        view
    }

    func title(for context: WKWebExtensionContext) -> String? {
        view?.title ?? record?.title
    }

    func url(for context: WKWebExtensionContext) -> URL? {
        view?.url ?? record?.url
    }

    func isPinned(for context: WKWebExtensionContext) -> Bool {
        record?.isPinned ?? false
    }

    func isSelected(for context: WKWebExtensionContext) -> Bool {
        Session.shared.workspace.space(space)?.selected == id
    }

    func isLoadingComplete(for context: WKWebExtensionContext) -> Bool {
        !(view?.isLoading ?? false)
    }

    /// No grant from a click on Google's sign-in, which comes before the
    /// denials in WebKit's order (ExtensionPolicy).
    func shouldGrantPermissionsOnUserGesture(for context: WKWebExtensionContext) -> Bool {
        ExtensionPolicy.grantsOnClick(url(for: context))
    }

    func detectWebpageLocale(for context: WKWebExtensionContext, completionHandler: @escaping (Locale?, (any Error)?) -> Void) {
        guard let page = Session.shared.pages.live[id], page.space == space,
              Session.shared.workspace.space(space)?.tabs.contains(where: { $0.id == id }) == true,
              let url = page.view.url, !page.isHandsOff, context.hasAccess(to: url, in: self) else {
            completionHandler(nil, nil)
            return
        }
        Task { @MainActor in
            do {
                let result = try await ExtensionLanguage.webpage(isAllowed: {
                    Session.shared.pages.live[self.id] === page && page.space == self.space &&
                        Session.shared.workspace.space(self.space)?.tabs.contains(where: { $0.id == self.id }) == true &&
                        page.view.url == url && !page.isHandsOff && context.hasAccess(to: url, in: self)
                }, sample: { try await page.extensionLanguageText() })
                completionHandler(result?.locale, nil)
            } catch { completionHandler(nil, error) }
        }
    }

    func activate(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        let session = Session.shared
        let window = session.allWindows.first { $0.spaceID == space } ?? session.frontWindow
        window?.select(id)
        window?.window?.makeKeyAndOrderFront(nil)
        completionHandler(nil)
    }

    func close(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        Session.shared.closeTab(id)
        completionHandler(nil)
    }

    func loadURL(_ url: URL, for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        guard let record else { return completionHandler(nil) }
        Session.shared.pages.page(for: record, in: space).load(url)
        completionHandler(nil)
    }

    func reload(fromOrigin: Bool, for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        if fromOrigin { view?.reloadFromOrigin() } else { view?.reload() }
        completionHandler(nil)
    }

    func goBack(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        view?.goBack()
        completionHandler(nil)
    }

    func goForward(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        view?.goForward()
        completionHandler(nil)
    }
}

/// A space, as the one window extensions see it in.
@MainActor
final class SpaceWindow: NSObject, WKWebExtensionWindow {
    let space: UUID

    init(space: UUID) {
        self.space = space
    }

    /// The Safience window last used on the space, if one shows it.
    private var shower: WindowModel? {
        let windows = Session.shared.allWindows.filter { $0.spaceID == space }
        return windows.first { $0.window?.isKeyWindow == true } ?? windows.first
    }

    func tabs(for context: WKWebExtensionContext) -> [any WKWebExtensionTab] {
        let tabs = Extensions.shared.tabs
        return (Session.shared.workspace.space(space)?.tabs ?? []).map { tabs.tab($0.id, in: space) }
    }

    func activeTab(for context: WKWebExtensionContext) -> (any WKWebExtensionTab)? {
        let selected = shower?.tabID ?? Session.shared.workspace.space(space)?.selected
        return selected.map { Extensions.shared.tabs.tab($0, in: space) }
    }

    func windowType(for context: WKWebExtensionContext) -> WKWebExtension.WindowType {
        .normal
    }

    func windowState(for context: WKWebExtensionContext) -> WKWebExtension.WindowState {
        guard let window = shower?.window else { return .minimized }
        if window.styleMask.contains(.fullScreen) { return .fullscreen }
        return window.isMiniaturized ? .minimized : .normal
    }

    func isPrivate(for context: WKWebExtensionContext) -> Bool {
        false
    }

    func frame(for context: WKWebExtensionContext) -> CGRect {
        shower?.window?.frame ?? .null
    }

    func screenFrame(for context: WKWebExtensionContext) -> CGRect {
        (shower?.window?.screen ?? NSScreen.main)?.frame ?? .null
    }

    func focus(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        if let window = shower?.window {
            window.makeKeyAndOrderFront(nil)
        } else {
            Session.shared.openWindow?(space)
        }
        completionHandler(nil)
    }

    /// A space isn't an extension's to close.
    func close(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        completionHandler(NSError(domain: "Safience", code: 2, userInfo: [NSLocalizedDescriptionKey: "A space can't be closed by an extension."]))
    }
}
