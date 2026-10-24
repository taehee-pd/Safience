import AppKit
import PadCore
import SwiftUI
import WebKit

/// What the command bar was opened for.
enum CommandBarPurpose: Equatable {
    /// ⌘T: what is chosen opens in a new tab, as in Arc.
    case newTab
    /// ⌘L, or a click on the address: the page on screen goes there.
    case here
}

/// One window: the space it shows, the tab of it on screen, and everything
/// the window's sidebar, command bar and find bar show about that tab.
@MainActor
final class WindowModel: ObservableObject, PageHost {
    @Published private(set) var spaceID: UUID {
        // Another space's bookmarks are not the ones asked for: they go. The
        // panel's own watch is in the sidebar's space, which goes with it.
        didSet { if spaceID != oldValue, bookmarksOpen { bookmarksOpen = false } }
    }
    @Published private(set) var tabID: UUID?
    /// The tab's page on screen; nil for a tab that has gone nowhere yet,
    /// and for a window whose space has no tab to show.
    @Published private(set) var page: Page?
    /// The page beside it while the tab on screen is in a split (Split View,
    /// the iPad's, shown as the Mac's Search shows two pages): the bars, the
    /// menus and the keys act on the tab on screen, and a click in this one
    /// gives it them (`focus(pane:)`).
    @Published private(set) var partner: Page?
    /// Moves on as the page beside says something new, for its card to draw again.
    @Published private(set) var partnerRevision = 0

    // The page as the sidebar and the card show it.
    @Published private(set) var url: URL?
    @Published private(set) var title = ""
    @Published private(set) var loading = false
    @Published private(set) var progress = 0.0
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var secure = false
    @Published private(set) var failure: String?

    /// The words, when the page is a search with the chosen engine: the
    /// address shows them in its place (Destination.searchWords).
    var searchWords: String? {
        url.flatMap { Destination.searchWords(in: $0, engine: Session.shared.preferences.engine) }
    }

    /// The sidebar down the window's side; hidden, it slides out over the
    /// page when the pointer reaches the window's left edge (peeking).
    @Published var sidebarShown: Bool {
        didSet {
            UserDefaults.standard.set(sidebarShown, forKey: Self.sidebarKey)
            // The bookmarks go with the sidebar, and don't come back out with it.
            if !sidebarShown, bookmarksOpen { bookmarksOpen = false }
        }
    }
    @Published var sidebarWidth: CGFloat {
        didSet { UserDefaults.standard.set(Double(sidebarWidth), forKey: Self.widthKey) }
    }
    @Published var peeking = false
    /// The space's bookmarks are out over the sidebar's list, as a popover
    /// is (BookmarksPanel), till one is chosen or they are put away.
    @Published var bookmarksOpen = false {
        didSet {
            if !bookmarksOpen { bookmarksFrame = .null }
            watchBookmarkClicks()
        }
    }
    /// Where the bookmarks are, in the window's own coordinates from its
    /// top (BookmarksPanel): a click anywhere else puts them away.
    var bookmarksFrame = CGRect.null
    private var bookmarksWatch: Any?
    /// What a command just did that leaves nothing to see, said for a
    /// moment over the page's top right (ActionToast).
    @Published var toast: ActionToast?
    private var toastWait: Task<Void, Never>?
    /// The peeking sidebar going back in, a moment after the pointer left it.
    private var unpeeking: Task<Void, Never>?
    @Published var commandBar: CommandBarPurpose?
    @Published var finding = false
    /// Moves on with each ⌘F, so the find bar takes the keys again when it is already open.
    @Published private(set) var findRequests = 0
    @Published var findText = ""
    /// The words looked for are nowhere on the page.
    @Published var findMissed = false
    /// Space Settings, open at the sidebar's foot: the list of spaces, or one space's own.
    @Published var spacesPanel: SpacesPanel?
    @Published var downloadsShown = false
    /// The page's own commands, open by the share symbol beside the address (PageActions).
    @Published var pageActionsShown = false
    /// The space's history (HistoryView), and Clear History, as sheets over the window.
    @Published var historyShown = false
    @Published var historyClearing = false
    /// The puzzle button's list of extensions (ExtensionBar.swift).
    @Published var extensionsShown = false
    /// The handoff being made ready, its sheet over the window while it is (HandoffSheet).
    @Published private(set) var handoff: HandoffJob?
    /// A handoff asked for, waiting to hear whether the model is there.
    private var startsHandoff = false
    let sharing = Sharing()

    let suggestions = Suggestions()
    weak var window: NSWindow?
    /// Tabs opened behind this one by ⌘-clicks, in a row: each next one goes after the last.
    private var openedBehind: (from: UUID, last: UUID)?

    /// Narrowest, the top row's buttons still fit beside the window's own.
    static let widths: ClosedRange<CGFloat> = 220...420
    private static let sidebarKey = "sidebarShown"
    private static let widthKey = "sidebarWidth"

    init(space: UUID?) {
        let workspace = Session.shared.workspace
        let space = space.flatMap(workspace.space) ?? workspace.spaces[0]
        spaceID = space.id
        tabID = space.selected
        let defaults = UserDefaults.standard
        sidebarShown = defaults.object(forKey: Self.sidebarKey) == nil || defaults.bool(forKey: Self.sidebarKey)
        let width = defaults.double(forKey: Self.widthKey)
        sidebarWidth = width > 0 ? min(max(CGFloat(width), Self.widths.lowerBound), Self.widths.upperBound) : 248
    }

    var space: Space? {
        Session.shared.workspace.space(spaceID)
    }

    /// The tabs down the window's side, as the Mac has them unless Settings
    /// puts them along the top.
    var tabsInSidebar: Bool {
        (Session.shared.preferences.tabsPlacement ?? .sidebar) == .sidebar
    }

    var tab: TabRecord? {
        tabID.flatMap(Session.shared.workspace.tab)
    }

    /// The window is on screen: it shows its tab, unless another window does already.
    func appear() {
        Session.shared.register(self)
        if let tabID, let other = Session.shared.window(showing: tabID), other !== self {
            show(tab: nil, inSpace: spaceID)
        } else {
            show(tab: tabID, inSpace: spaceID)
        }
        #if DEBUG
        // For pictures of the window in a given state: `open Safience.app --args -showing peek`.
        switch UserDefaults.standard.string(forKey: "showing") {
        case "commandBar": commandBar = .newTab
        case "address": commandBar = .here
        case "peek": peeking = true
        case "top": Session.shared.preferences.tabsPlacement = .top
        case "sidebar": Session.shared.preferences.tabsPlacement = .sidebar
        case "space":
            spacesPanel = .list
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.spacesPanel = .edit(self.spaceID) }
        case "spaces": spacesPanel = .list
        // Popovers once the window is up: asked for as it appears, some never showed.
        case "actions": DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.pageActionsShown = true }
        case "handoff":
            Session.shared.preferences.handoff = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { self.startHandoff() }
        case "find": startFinding()
        case "settings": Session.shared.openSettings?()
        // The tab on screen beside the next of the space's own tabs.
        case "split":
            if let other = space?.tabs.first(where: { !$0.isPinned && $0.id != tabID && $0.url != nil })?.id {
                split(with: other)
            }
        default: break
        }
        // In front, as a window in use is: one behind shows its tinted glass grey (`-front YES`).
        if UserDefaults.standard.bool(forKey: "front") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { NSApp.activate(ignoringOtherApps: true) }
        }
        // Over other apps' windows without being in front, for a picture of the
        // glass with what is behind it while another app is in use (`-floating YES`).
        if UserDefaults.standard.bool(forKey: "floating") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.window?.level = .floating }
        }
        #endif
    }

    /// The window closed: its page stays live a while, as another tab off screen.
    func disappear() {
        // Its watch on clicks goes with it: AppKit keeps a monitor for the app's life.
        bookmarksOpen = false
        attach(nil)
        setPartner(nil)
        // At once: the window is going, and won't be here to look later.
        checkScreen()
        // Its extension popup and side panel go with it.
        ExtensionPopups.shared.close(in: self)
        ExtensionSidePanels.shared.close(in: self)
        Session.shared.unregister(self)
        Session.shared.pages.enforce()
    }

    // MARK: Showing a tab

    /// `tab` of `space` on screen; nil shows the space's start. A tab that
    /// has gone nowhere yet gets no page until it goes somewhere.
    func show(tab: UUID?, inSpace space: UUID) {
        let session = Session.shared
        spaceID = space
        showing = true
        defer {
            showing = false
            syncSplit()
        }
        guard let tab, let record = session.workspace.tab(tab), session.workspace.spaceID(of: tab) == space else {
            tabID = nil
            attach(nil)
            return
        }
        tabID = tab
        session.change { $0.select(tab) }
        let live = session.pages.isLive(tab)
        // A tab of a split gets its page even before it has gone anywhere: its pane is on screen.
        let paired = session.workspace.split(containing: tab) != nil
        attach(record.url == nil && !live && !paired ? nil : session.pages.page(for: record, in: space))
        session.pages.enforce()
    }

    /// Showing a tab: the workspace changes on the way, and the page beside
    /// is worked out once the tab is on screen, not halfway.
    private var showing = false

    private func attach(_ next: Page?) {
        if next !== page {
            let old = page
            page = next
            release(old)
            next?.host = self
            screenMayHaveChanged()
        }
        refresh()
    }

    /// The pages on screen when last looked at (`checkScreen`).
    private var lastOnScreen: [Page] = []
    private var screenCheckWaiting = false

    /// Which pages are on screen may have changed: looked at once the change
    /// has settled, since a tab and the page beside it in a split change one
    /// after the other (`show` syncs the split last), and a page passing
    /// from one to the other hasn't left the screen.
    private func screenMayHaveChanged() {
        guard !screenCheckWaiting else { return }
        screenCheckWaiting = true
        DispatchQueue.main.async { [weak self] in self?.checkScreen() }
    }

    /// Tells each page that left the screen, and isn't shown in another
    /// window, and each that came onto it (Page.leftScreen, cameOnScreen).
    private func checkScreen() {
        screenCheckWaiting = false
        let now = [page, partner].compactMap { $0 }
        for old in lastOnScreen where !now.contains(where: { $0 === old }) && Session.shared.window(showing: old.tab) == nil {
            old.leftScreen()
        }
        for new in now where !lastOnScreen.contains(where: { $0 === new }) {
            new.cameOnScreen()
            new.reviewPendingDialog()
        }
        lastOnScreen = now
    }

    /// A page this window no longer shows hears from it no more.
    private func release(_ old: Page?) {
        guard let old, old !== page, old !== partner, old.host === self else { return }
        old.host = nil
    }

    /// The page's state, read again for the sidebar and the card.
    func refresh() {
        let record = tab
        let view = page?.view
        url = page?.displayURL ?? record?.url
        title = view?.title.flatMap { $0.isEmpty ? nil : $0 } ?? record?.label ?? ""
        loading = view?.isLoading ?? false
        progress = view?.estimatedProgress ?? 0
        canGoBack = view?.canGoBack ?? false
        canGoForward = view?.canGoForward ?? false
        secure = page?.failure == nil && url?.scheme == "https" && (view?.hasOnlySecureContent ?? true)
        failure = page?.failure
        window?.title = record == nil ? (space?.name ?? "Safience") : title
    }

    /// The keys go to the page, as they do after a click on it.
    func focusPage() {
        guard let view = page?.view else { return }
        DispatchQueue.main.async { [weak self] in self?.window?.makeFirstResponder(view) }
    }

    /// A tab chosen in the sidebar or the command bar: shown here, or the
    /// window that shows it comes forward.
    func select(_ tab: UUID) {
        let session = Session.shared
        if let other = session.window(showing: tab), other !== self {
            other.window?.makeKeyAndOrderFront(nil)
            return
        }
        guard let space = session.workspace.spaceID(of: tab) else { return }
        show(tab: tab, inSpace: space)
        focusPage()
    }

    func showSpace(_ id: UUID) {
        guard let space = Session.shared.workspace.space(id), id != spaceID || tabID == nil else { return }
        var tab = space.selected
        if let shown = tab, let other = Session.shared.window(showing: shown), other !== self { tab = nil }
        withAnimation(.bar) { show(tab: tab, inSpace: id) }
        focusPage()
    }

    func showSpace(by offset: Int) {
        guard let next = Session.shared.workspace.spaceNeighbour(of: spaceID, by: offset) else { return }
        showSpace(next)
    }

    func showSpace(number: Int) {
        let spaces = Session.shared.workspace.spaces
        guard spaces.indices.contains(number - 1) else { return }
        showSpace(spaces[number - 1].id)
    }

    // MARK: Split View

    /// The split the tab on screen is in.
    var split: Split? {
        tabID.flatMap { Session.shared.workspace.split(containing: $0) }
    }

    /// Whether `tab` is on screen in this window, with the keys or beside.
    func shows(_ tab: UUID) -> Bool {
        (tabID == tab && page != nil) || partner?.tab == tab
    }

    /// The workspace changed: the page beside, as the split now has it.
    func workspaceChanged() {
        guard !showing else { return }
        syncSplit()
    }

    /// The page beside, as the workspace's split has it: found or made when
    /// the tab on screen is in one, let go when it isn't, or when another
    /// window has that tab on screen.
    func syncSplit() {
        let session = Session.shared
        let workspace = session.workspace
        guard let tab = tabID, page != nil, let other = workspace.split(containing: tab)?.partner(of: tab),
              let record = workspace.tab(other), let space = workspace.spaceID(of: other),
              !session.allWindows.contains(where: { $0 !== self && $0.shows(other) })
        else {
            if partner != nil {
                setPartner(nil)
                session.pages.enforce()
            }
            return
        }
        if partner?.tab != other || session.pages.live[other] !== partner {
            setPartner(session.pages.page(for: record, in: space))
            session.pages.enforce()
        }
    }

    private func setPartner(_ next: Page?) {
        guard next !== partner else { return }
        let old = partner
        partner = next
        release(old)
        next?.host = self
        watchClicks()
        screenMayHaveChanged()
    }

    /// The page beside takes the keys, and the bars with them.
    func focus(pane tab: UUID) {
        guard tab != tabID, tab == partner?.tab else { return }
        show(tab: tab, inSpace: spaceID)
        focusPage()
    }

    /// `other` beside the tab on screen, on its right; the tab on screen keeps the keys.
    func split(with other: UUID) {
        guard let tab = tabID, Session.shared.change({ $0.split(tab, with: other) }) else { return }
        syncSplit()
        focusPage()
    }

    /// A new tab beside the one on screen, on its right, with the keys and
    /// the command bar open for it.
    func splitWithNewTab() {
        guard let tab = tabID, let new = Session.shared.change({ $0.splitWithNewTab(tab) }) else { return }
        withAnimation(.bar) { show(tab: new, inSpace: spaceID) }
        commandBar = .newTab
    }

    /// The tab on screen and the one beside go back to being tabs of their own.
    func separate(_ tab: UUID? = nil) {
        guard let tab = tab ?? tabID else { return }
        withAnimation(.bar) { Session.shared.change { $0.separate(tab) } }
    }

    func swapSides(_ tab: UUID? = nil) {
        guard let tab = tab ?? tabID else { return }
        withAnimation(.bar) { Session.shared.change { $0.swapSides(tab) } }
    }

    /// The left page's share of the room, once the divider is let go.
    func setSplitRatio(_ ratio: Double) {
        guard let tab = tabID else { return }
        Session.shared.change { $0.setSplitRatio(tab, to: ratio) }
    }

    /// Both tabs of the split close.
    func closeSplit() {
        guard let tab = tabID, let other = partner?.tab else { return }
        requestCloseTabs([other, tab])
    }

    /// With two pages up, a click in the one without the keys gives it them,
    /// and is still the page's click. Watched, not taken: the click is WebKit's.
    private var clickWatch: Any?

    private func watchClicks() {
        if partner != nil, clickWatch == nil {
            clickWatch = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
                self?.clicked(event)
                return event
            }
        } else if partner == nil, let watch = clickWatch {
            NSEvent.removeMonitor(watch)
            clickWatch = nil
        }
    }

    /// While the bookmarks are out, every click in the window is watched, not
    /// taken, as clickWatch watches for the pane beside.
    private func watchBookmarkClicks() {
        if bookmarksOpen, bookmarksWatch == nil {
            bookmarksWatch = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
                self?.clickedAway(event)
                return event
            }
        } else if !bookmarksOpen, let watch = bookmarksWatch {
            NSEvent.removeMonitor(watch)
            bookmarksWatch = nil
        }
    }

    /// A click in the window off the bookmarks, on the page, the address or
    /// a pinned tab, puts them away, as one outside a popover does; the
    /// click still goes where it was meant to.
    private func clickedAway(_ event: NSEvent) {
        guard bookmarksOpen, let window, event.window === window, let content = window.contentView else { return }
        let point = event.locationInWindow
        // The window counts from its foot, SwiftUI from its top.
        guard !bookmarksFrame.contains(CGPoint(x: point.x, y: content.bounds.height - point.y)) else { return }
        DispatchQueue.main.async { [weak self] in withAnimation(.bar) { self?.bookmarksOpen = false } }
    }

    private func clicked(_ event: NSEvent) {
        guard let partner, let window, event.window === window, partner.view.window === window else { return }
        let view = partner.view
        guard view.bounds.contains(view.convert(event.locationInWindow, from: nil)) else { return }
        // What lies over the page (the command bar, the find bar) is not the page: a click there moves nothing.
        if let hit = window.contentView?.hitTest(event.locationInWindow), hit !== view, !hit.isDescendant(of: view) { return }
        let tab = partner.tab
        DispatchQueue.main.async { [weak self] in self?.focus(pane: tab) }
    }

    // MARK: Going places

    /// A line typed: an address when it is one, a search otherwise.
    func go(_ typed: String, newTab: Bool) {
        guard let url = Destination.url(for: typed, engine: Session.shared.preferences.engine) else { return }
        HistoryRecorder.shared.expect(.typed, url)
        open(url, newTab: newTab)
    }

    /// `url` in a new tab, or in the tab on screen. A tab that has gone
    /// nowhere yet takes it either way.
    func open(_ url: URL, newTab: Bool) {
        let session = Session.shared
        if let record = tab, !newTab || record.url == nil {
            let page = session.pages.page(for: record, in: spaceID)
            attach(page)
            page.load(url)
            focusPage()
            return
        }
        guard let id = session.change({ $0.openTab(url, in: spaceID) }) else { return }
        withAnimation(.bar) { show(tab: id, inSpace: spaceID) }
        focusPage()
    }

    func back() {
        page?.view.goBack()
    }

    func forward() {
        page?.view.goForward()
    }

    func reload() {
        if let page {
            page.reload()
        } else if let tabID {
            show(tab: tabID, inSpace: spaceID)
        }
    }

    func stop() {
        page?.view.stopLoading()
    }

    // MARK: Tabs

    func closeTab(_ id: UUID? = nil) {
        guard let id = id ?? tabID else { return }
        withAnimation(.bar) { Session.shared.closeTab(id) }
        focusPage()
    }

    /// Arc's Clear: every tab of the space that isn't pinned.
    func clearTabs() {
        let ids = space?.tabs.filter { !$0.isPinned }.map(\.id) ?? []
        requestCloseTabs(ids)
    }

    func requestCloseTabs(_ ids: [UUID]) {
        let plan = TabClosePlan(workspace: Session.shared.workspace, requested: ids)
        guard !plan.ids.isEmpty else { return }
        guard plan.needsConfirmation else { Session.shared.closeTabs(plan.ids); return }
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = plan.title
        alert.informativeText = plan.message
        alert.addButton(withTitle: plan.actionTitle)
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        alert.beginSheetModal(for: window) { answer in
            if answer == .alertFirstButtonReturn { Session.shared.closeTabs(plan.ids) }
        }
    }

    func resetPinnedTab(_ id: UUID) {
        guard Session.shared.workspace.tab(id)?.isPinned == true, let window else { return }
        let alert = NSAlert()
        alert.messageText = BrowserText.localized("Reset Pinned Tab?")
        alert.informativeText = BrowserText.localized("This discards the page's unsaved changes and reloads its pinned address. The pinned shortcut stays.")
        alert.addButton(withTitle: BrowserText.localized("Reset Pinned Tab"))
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        alert.beginSheetModal(for: window) { [weak self] answer in
            guard answer == .alertFirstButtonReturn else { return }
            let session = Session.shared
            guard session.change({ $0.resetPinnedTab(id) }) else { return }
            if let live = session.pages.live[id], let url = session.workspace.tab(id)?.pinned { live.load(url) }
            else { session.pages.close(id) }
            self?.focusPage()
        }
    }

    func reopenTab() {
        let session = Session.shared
        guard let id = session.change({ $0.reopen() }), let space = session.workspace.spaceID(of: id) else { return }
        withAnimation(.bar) { show(tab: id, inSpace: space) }
        focusPage()
    }

    /// The next tab along in the sidebar, going round: past the pinned tabs this Mac hides, as the sidebar is.
    func selectTab(by offset: Int) {
        let shows = Session.shared.preferences.shows
        guard let tabID, let next = Session.shared.workspace.neighbour(of: tabID, by: offset, among: shows) else {
            if let first = space?.tabs.first(where: shows) { select(first.id) }
            return
        }
        select(next)
    }

    /// ⌘1 to ⌘8, the tab in that place in the sidebar; ⌘9 the last, as in every browser.
    func selectTab(number: Int) {
        guard let tabs = space?.tabs.filter(Session.shared.preferences.shows), !tabs.isEmpty else { return }
        let index = number == 9 ? tabs.count - 1 : number - 1
        guard tabs.indices.contains(index) else { return }
        select(tabs[index].id)
    }

    func togglePin(_ id: UUID? = nil) {
        guard let id = id ?? tabID else { return }
        withAnimation(.bar) {
            Session.shared.change { workspace in
                if !workspace.pin(id) { workspace.unpin(id) }
            }
        }
    }

    /// A pinned tab pinned anew at the page it is on.
    func repin(_ id: UUID) {
        Session.shared.change { _ = $0.repin(id) }
    }

    /// A pinned tab back at the address it was pinned with.
    func backToPinned(_ id: UUID) {
        let session = Session.shared
        guard let url = session.change({ $0.backToPinned(id) }) else { return }
        HistoryRecorder.shared.expect(.bookmark, url)
        if id == tabID, let record = tab {
            let page = page ?? session.pages.page(for: record, in: spaceID)
            attach(page)
            page.load(url)
        } else {
            session.pages.unload(id)
        }
    }

    func duplicate(_ id: UUID? = nil) {
        guard let id = id ?? tabID, let url = Session.shared.workspace.tab(id)?.url,
              let space = Session.shared.workspace.spaceID(of: id),
              let copy = Session.shared.change({ $0.openTab(url, in: space, after: id) })
        else { return }
        withAnimation(.bar) { show(tab: copy, inSpace: space) }
    }

    func move(_ id: UUID, to space: UUID) {
        Session.shared.moveTab(id, to: space, from: self)
    }

    /// Same-space drops reorder immediately; cross-space drops wait for an explicit choice.
    func place(_ id: UUID, pinned: Bool, before target: UUID?) {
        let session = Session.shared
        let destination = spaceID
        guard let from = session.workspace.spaceID(of: id),
              target.map({ session.workspace.spaceID(of: $0) == destination }) ?? true else { return }
        if from != destination {
            session.moveTab(id, to: destination, from: self, before: target) { [weak self] moved in
                guard let self, let moved, self.spaceID == destination else { return }
                self.placeMovedTab(moved, pinned: pinned, before: target, in: destination)
            }
        } else {
            placeMovedTab(id, pinned: pinned, before: target, in: destination)
        }
    }

    private func placeMovedTab(_ id: UUID, pinned: Bool, before target: UUID?, in destination: UUID) {
        let session = Session.shared
        guard session.workspace.spaceID(of: id) == destination,
              target.map({ session.workspace.spaceID(of: $0) == destination }) ?? true else { return }
        withAnimation(.bar) {
            session.change { workspace in
                guard let isPinned = workspace.tab(id)?.isPinned else { return }
                if pinned != isPinned, !(pinned ? workspace.pin(id) : workspace.unpin(id)) { return }
                guard let tabs = workspace.space(destination)?.tabs, target != id else { return }
                let others = tabs.filter { $0.id != id }
                let index = target.flatMap { t in others.firstIndex { $0.id == t } }
                    ?? (pinned ? others.filter(\.isPinned).count : others.count)
                workspace.moveTab(id, toIndex: index)
            }
        }
    }

    /// The address as Share sends it, without the tags that follow whoever opens it (Tracking.clean).
    func copyLink(_ id: UUID? = nil) {
        guard let link = id.flatMap({ Session.shared.workspace.tab($0)?.url }) ?? url else { return }
        copyAddress(link)
    }

    /// An address to the pasteboard, and a toast to say so: nothing else shows it.
    func copyAddress(_ address: URL) {
        Self.copy(address)
        show(.linkCopied)
    }

    /// What a command did that leaves nothing to see, said for a moment over
    /// the page and to VoiceOver; a new one takes the last one's place.
    func show(_ toast: ActionToast) {
        self.toast = toast
        if let window {
            NSAccessibility.post(element: window, notification: .announcementRequested,
                                 userInfo: [.announcement: toast.text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
        }
        toastWait?.cancel()
        toastWait = Task { [weak self] in
            try? await Task.sleep(for: ActionToast.shown)
            guard !Task.isCancelled, let self, self.toast?.id == toast.id else { return }
            self.toast = nil
        }
    }

    /// An address to the pasteboard, without the tags that follow whoever opens it (Tracking.clean).
    static func copy(_ address: URL) {
        let link = Tracking.clean(address)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([link as NSURL])
        NSPasteboard.general.setString(link.absoluteString, forType: .string)
    }

    /// A bookmark's page: here, or in a new tab with ⌘ held, as a ⌘-click on a link does.
    func open(bookmark url: URL) {
        HistoryRecorder.shared.expect(.bookmark, url)
        open(url, newTab: NSEvent.modifierFlags.contains(.command))
    }

    func toggleBookmark() {
        guard let url, url.scheme?.hasPrefix("http") == true else { return }
        let session = Session.shared
        let known = session.workspace.bookmark(for: url, in: spaceID)
        if let known {
            session.change { $0.removeBookmark(known.id, in: spaceID) }
        } else {
            session.change { $0.addBookmark(url, title: title, in: spaceID) }
        }
        // The star says so only where the address shows it.
        show(.bookmark(added: known == nil))
    }

    var isBookmarked: Bool {
        url.flatMap { Session.shared.workspace.bookmark(for: $0, in: spaceID) } != nil
    }

    // MARK: Spaces

    func newSpace() {
        let session = Session.shared
        let id = session.change { $0.addSpace(named: "Space \(session.workspace.spaces.count + 1)") }
        showSpace(id)
        spacesPanel = .edit(id)
    }

    // MARK: The page

    func toggleSidebar() {
        guard tabsInSidebar else { return }
        unpeeking?.cancel()
        withAnimation(.bar) {
            sidebarShown.toggle()
            peeking = false
        }
    }

    /// The pointer came to the hidden sidebar's strip or pane, or left them both.
    func peek(_ inside: Bool) {
        unpeeking?.cancel()
        if inside {
            if !peeking { withAnimation(.bar) { peeking = true } }
            return
        }
        unpeeking = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            // Not from under a popover opened from it: the popover would lose what it stands on.
            guard !Task.isCancelled, let self, spacesPanel == nil, !downloadsShown, !pageActionsShown, !extensionsShown else { return }
            withAnimation(.bar) { self.peeking = false }
        }
    }

    // MARK: Handoff

    /// Whether Handoff can be asked for here: on in Settings, on a Mac with
    /// Apple Intelligence, for a page that isn't hands-off.
    var canHandoff: Bool {
        let session = Session.shared
        return session.preferences.handoff && session.hasIntelligence && page?.view.url != nil && page?.isHandsOff == false
    }

    /// The page on screen handed to another app (HandoffJob, the iPad's):
    /// its sheet comes up as soon as it is known whether Apple
    /// Intelligence's model is there to ask, and says how far it is.
    func startHandoff() {
        guard canHandoff, handoff == nil, !startsHandoff, let page else { return }
        startsHandoff = true
        Task { [weak self, weak page] in
            let mind = await PageMinds.mind()
            guard let self else { return }
            startsHandoff = false
            // Asked after the wait: the page may have gone, or another taken its place.
            guard let page, self.page === page, !page.isHandsOff, let url = page.view.url else { return }
            handoff = HandoffJob(page: page, url: url, title: page.view.title ?? "", mind: mind)
        }
    }

    /// The share menu for the handoff, from its sheet's button: the file and
    /// the words beside it, or the words alone for a page with nothing to read.
    func shareHandoff(from view: NSView) {
        guard let job = handoff else { return }
        let items: [Any] = job.stage.hasFile ? [job.file as NSURL, job.prompt] : [job.prompt]
        sharing.show(items, from: view) { [weak self] service in
            guard service != nil else { return }
            // From now on the file stays as it is: an app is reading it.
            job.give()
            self?.endHandoff(taken: true)
        }
    }

    /// The handoff over: given to an app, or put away. What no app took is removed.
    func endHandoff(taken: Bool) {
        handoff?.finish(taken: taken)
        handoff = nil
        focusPage()
    }

    func startFinding() {
        finding = true
        findRequests += 1
    }

    func find(backwards: Bool = false) {
        guard let page else { return }
        page.find(findText, backwards: backwards) { [weak self] found in
            self?.findMissed = !found && !(self?.findText.isEmpty ?? true)
        }
    }

    func endFinding() {
        finding = false
        findMissed = false
        focusPage()
    }

    var blocksContentHere: Bool {
        Session.shared.preferences.blocksContent(onHost: url?.host)
    }

    /// Whether this site's ads can be blocked or allowed: only while
    /// Settings blocks them at all, as the menu bar and the page's actions
    /// have it; otherwise blocking it here would change nothing.
    var offersBlocking: Bool {
        Session.shared.preferences.blocksContent && url?.host != nil
    }

    /// Ads blocked or allowed on this site, from its next load: loaded again now.
    func toggleBlocking() {
        guard offersBlocking, let host = url?.host else { return }
        let blocked = !blocksContentHere
        Session.shared.preferences.setBlocksContent(blocked, onHost: host)
        page?.blockingChanged()
        page?.reload()
        show(.ads(blocked: blocked))
    }

    /// A command from the menu bar or the command bar.
    func perform(_ command: Command) {
        switch command {
        case .everything, .newTab: commandBar = .newTab
        case .address: commandBar = .here
        case .closeTab: closeTab()
        case .reopenTab: reopenTab()
        case .reload: reload()
        case .stop: stop()
        case .back: back()
        case .forward: forward()
        case .nextTab: selectTab(by: 1)
        case .previousTab: selectTab(by: -1)
        case .nextSpace: showSpace(by: 1)
        case .previousSpace: showSpace(by: -1)
        case .newSpace: newSpace()
        case .newWindow: Session.shared.openWindow?(spaceID)
        case .closeWindow: window?.performClose(nil)
        case .tabBar: toggleSidebar()
        case .settings: Session.shared.openSettings?()
        case .pinTab: togglePin()
        case .bookmark: toggleBookmark()
        case .spaceSettings: spacesPanel = .edit(spaceID)
        case .contentBlocking: toggleBlocking()
        case .find: startFinding()
        case .focusPage: focusPage()
        case .handoff: startHandoff()
        case .history: historyShown = true
        case .share: pageActionsShown = true
        case .copyLink: copyLink()
        case .splitTab: if split != nil { separate() } else { splitWithNewTab() }
        case .importBookmarks:
            if let window { Session.shared.chooseBookmarksFile(into: spaceID, in: window) }
        case .diagnostics, .siteMode, .linkMenu: break
        }
    }

    /// What the Mac offers of the browser's commands: the iPad's that a Mac has a use for.
    static let commands: [Command] = [
        .newTab, .closeTab, .reopenTab, .reload, .stop, .back, .forward, .nextTab, .previousTab,
        .nextSpace, .previousSpace, .newSpace, .newWindow, .closeWindow, .tabBar, .settings, .pinTab,
        .bookmark, .spaceSettings, .contentBlocking, .find, .handoff, .splitTab, .history, .copyLink,
    ]

    /// Each command's keys, as the menu bar has them.
    static func keys(for command: Command) -> String? {
        switch command {
        case .newTab: return "⌘T"
        case .closeTab: return "⌘W"
        case .reopenTab: return "⇧⌘T"
        case .address: return "⌘L"
        case .reload: return "⌘R"
        case .stop: return "⌘."
        case .back: return "⌘["
        case .forward: return "⌘]"
        case .nextTab: return "⌃⇥"
        case .previousTab: return "⌃⇧⇥"
        case .nextSpace: return "⌥⌘→"
        case .previousSpace: return "⌥⌘←"
        case .newWindow: return "⌘N"
        case .closeWindow: return "⇧⌘W"
        case .tabBar: return "⌃⌘S"
        case .settings: return "⌘,"
        case .pinTab: return "⇧⌘D"
        case .bookmark: return "⌘D"
        case .find: return "⌘F"
        case .history: return "⌘Y"
        case .copyLink: return "⇧⌘C"
        default: return nil
        }
    }

    /// A row of the command bar, chosen.
    func run(_ suggestion: Suggestion, purpose: CommandBarPurpose) {
        commandBar = nil
        switch suggestion.action {
        case .tab(let id): select(id)
        case .open(let url):
            HistoryRecorder.shared.expect(.typed, url)
            open(url, newTab: purpose == .newTab)
        case .space(let id): showSpace(id)
        case .command(let command): perform(command)
        case .setting: Session.shared.openSettings?()
        case .go(let text): go(text, newTab: purpose == .newTab)
        }
    }

    // MARK: PageHost

    var hostWindow: NSWindow? {
        window
    }

    func pageDidChange(_ page: Page) {
        if page === self.page {
            refresh()
        } else if page === partner {
            partnerRevision += 1
        }
    }

    func isShowing(_ page: Page) -> Bool {
        (page === self.page || page === partner) && window?.isVisible == true
            && page.view.window === window && !page.view.isHiddenOrHasHiddenAncestor
    }

    func page(_ page: Page, open configuration: WKWebViewConfiguration, for action: WKNavigationAction,
              features: WKWindowFeatures) -> WKWebView? {
        // A window with a size asked for is a pop-up: a sign-in, a share
        // dialog. It opens over this window and closes by itself when done.
        if features.width != nil || features.height != nil {
            return Popup.open(from: page, configuration: configuration, features: features, over: window)
        }
        // Anything else is a tab, right after the one it came from; behind
        // this one when a ⌘-click asked for it, live there with its tie to this page.
        let session = Session.shared
        let behind = action.modifierFlags.contains(.command) && !action.modifierFlags.contains(.shift)
        guard let id = session.change({ $0.openTab(action.request.url, in: page.space, after: behind ? behindAfter(page) : page.tab) })
        else { return nil }
        let child = session.pages.adopt(tab: id, space: page.space, configuration: configuration)
        if behind {
            session.change { $0.select(page.tab) }
            openedBehind = (page.tab, id)
            session.pages.enforce()
            return child.view
        }
        openedBehind = nil
        withAnimation(.bar) {
            tabID = id
            spaceID = page.space
            session.change { $0.select(id) }
            attach(child)
        }
        focusPage()
        session.pages.enforce()
        return child.view
    }

    func page(_ page: Page, openInNewTab url: URL, inFront: Bool) -> Bool {
        let session = Session.shared
        guard let id = session.change({ $0.openTab(url, in: page.space, after: inFront ? page.tab : behindAfter(page)) }) else {
            return false
        }
        if inFront {
            openedBehind = nil
            withAnimation(.bar) { show(tab: id, inSpace: page.space) }
            focusPage()
        } else {
            session.change { $0.select(page.tab) }
            openedBehind = (page.tab, id)
        }
        return true
    }

    /// Where a tab opened behind goes: after the last one opened behind
    /// from the same tab, so a row of ⌘-clicks keeps its order.
    private func behindAfter(_ page: Page) -> UUID {
        if let openedBehind, openedBehind.from == page.tab, Session.shared.workspace.tab(openedBehind.last) != nil {
            return openedBehind.last
        }
        return page.tab
    }

    func pageDidClose(_ page: Page) {
        guard Session.shared.workspace.tab(page.tab) != nil else { return }
        closeTab(page.tab)
    }
}
