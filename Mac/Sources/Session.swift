import AppKit
import Combine
import PadCore
import Security
import os

/// What every window shares: the spaces and their tabs, the settings, the
/// pages, and the windows themselves. The iPad's Session, for a Mac.
///
/// Each window shows one space and one tab of it. A tab is on screen in one
/// window at a time; choosing a tab that another window shows brings that
/// window forward instead.
@MainActor
final class Session: ObservableObject {
    static let shared = Session()
    /// What went wrong where nothing is shown for it, for Console.
    nonisolated private static let log = Logger(subsystem: "net.taehee.safience", category: "Session")

    @Published private(set) var workspace: Workspace
    @Published private(set) var workspaceProblem: WorkspaceFile.Failure?
    /// The last workspace write failed: the workspace on screen is newer
    /// than the one on disk until a write succeeds.
    @Published private(set) var workspaceSaveFailed = false
    var canUseWorkspace: Bool { workspaceProblem == nil }
    @Published var preferences: Preferences {
        didSet {
            guard preferences != oldValue else { return }
            preferencesChanged(from: oldValue)
        }
    }

    /// Whether this Mac has Apple Intelligence to ask (PageMinds.intelligence),
    /// without which Handoff is in no menu and not in Settings. What the
    /// last look found, kept across launches so the menus are right from
    /// the first; looked at again whenever the app comes to the front.
    @Published private(set) var hasIntelligence = UserDefaults.standard.bool(forKey: Session.intelligenceKey) {
        didSet { UserDefaults.standard.set(hasIntelligence, forKey: Session.intelligenceKey) }
    }
    private static let intelligenceKey = "hasIntelligence"
    private var intelligenceWatch: NSObjectProtocol?

    let pages = Pages()
    private let windows = NSHashTable<WindowModel>.weakObjects()
    private let store = WorkspaceStore(folder: Session.folder, snapshots: Snapshots.folder) { Session.written($0) }
    /// Addresses another app asked to open before any window was there to take them.
    private var waiting: [URL] = []
    /// A new window showing a space, and the Settings window, through
    /// SwiftUI: set by the first window that appears.
    var openWindow: ((UUID?) -> Void)?
    var openSettings: (() -> Void)?

    static let preferencesKey = "preferences"

    /// Whether this build may use iCloud: signed with the app's iCloud
    /// container. A build signed only to run on this Mac isn't, and CloudKit
    /// would stop it at the first call; Settings says so instead.
    static let canSync: Bool = {
        guard dataRootOverride == nil else { return false }
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(task, "com.apple.developer.icloud-container-identifiers" as CFString, nil)
        else { return false }
        return ((value as? [String]) ?? []).isEmpty == false
    }()

    /// Asked from any thread: the filter lists are read and written away from the main one.
    nonisolated static var dataRootOverride: URL? {
        let value = ProcessInfo.processInfo.environment["SAFIENCE_DATA_ROOT"]
            ?? Bundle.main.object(forInfoDictionaryKey: "SAFIENCE_DATA_ROOT") as? String
        guard let value, value.hasPrefix("/"), !value.isEmpty else { return nil }
        return URL(fileURLWithPath: value, isDirectory: true)
    }

    nonisolated static var folder: URL {
        if let override = dataRootOverride { return override }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return support.appendingPathComponent("Safience", isDirectory: true)
    }

    static var workspaceFile: URL {
        WorkspaceStore.file(in: folder)
    }

    private init() {
        let opened = store.open()
        workspace = opened.workspace
        workspaceProblem = opened.problem
        preferences = Preferences.stored(in: .standard, key: Session.preferencesKey)
    }

    /// Once, at launch, before the first window.
    func start(afterLaunch: Bool = false) {
        startWorkspaceServices(afterLaunch: afterLaunch)
        lookForIntelligence()
        // Coming to the front includes the launch's own.
        intelligenceWatch = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                                                   object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.lookForIntelligence() }
        }
        appWatch = [
            NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil,
                                                   queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.appWentBehind() }
            },
            NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil,
                                                   queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.appCameBack() }
            },
        ]
    }

    // MARK: Picture in picture as Safience goes behind

    private var appWatch: [NSObjectProtocol] = []
    private var goingBehind: Task<Void, Never>?

    /// The pages on screen, in every window: each tab's and the one beside it.
    private var pagesOnScreen: [Page] {
        allWindows.flatMap { [$0.page, $0.partner].compactMap { $0 } }
    }

    /// Another app came in front: once it has stayed there a moment, each
    /// page on screen floats its call or its video (Page.appWentBehind). A
    /// quick ⌘-Tab out and back floats nothing.
    private func appWentBehind() {
        goingBehind?.cancel()
        goingBehind = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, !Task.isCancelled, !NSApp.isActive else { return }
            for page in self.pagesOnScreen { page.appWentBehind() }
        }
    }

    /// Safience in front again: what floated goes back (Page.appCameBack),
    /// a video even of a page no longer on screen (a tab switched or a
    /// window closed meanwhile), and a tab it kept from freezing may freeze.
    private func appCameBack() {
        goingBehind?.cancel()
        goingBehind = nil
        let shown = pagesOnScreen
        for page in shown { page.appCameBack() }
        for page in pages.live.values where !shown.contains(where: { $0 === page }) { page.sinkVideo() }
        pages.enforce()
    }

    private func startWorkspaceServices(afterLaunch: Bool = false) {
        guard canUseWorkspace else { return }
        Stores.sweep()
        HistoryRecorder.shared.prune()
        Snapshots.prune(keeping: Set(workspace.spaces.flatMap { $0.tabs.map(\.id) }))
        pages.watchMemory()
        ContentBlocker.shared.start()
        Extensions.shared.start(afterLaunch: afterLaunch)
        if preferences.iCloudSync, Session.canSync { Sync.shared.start(join: false) }
    }

    /// Retry never creates replacement identities after a failed read.
    @discardableResult
    func retryWorkspace() -> Bool {
        guard !canUseWorkspace else { return true }
        let retried: WorkspaceStore.Opened?
        do {
            retried = try store.retry(workspace)
        } catch {
            NSLog("Safience: the workspace couldn't be written on retry: \(error.localizedDescription)")
            return false
        }
        guard let opened = retried else { return false }
        workspace = opened.workspace
        workspaceProblem = nil
        startWorkspaceServices(afterLaunch: true)
        return true
    }

    func restoreWorkspace(from file: URL) throws {
        guard !canUseWorkspace else { return }
        // No history writes or snapshot writes run while recovery is showing.
        workspace = try store.restore(from: file)
        workspaceProblem = nil
        startWorkspaceServices(afterLaunch: true)
    }

    private func lookForIntelligence() {
        Task {
            let has = await PageMinds.intelligence()
            if hasIntelligence != has { hasIntelligence = has }
        }
    }

    // MARK: The workspace

    /// Every change to the workspace goes through here: saved a moment
    /// later, and every window hears of it.
    @discardableResult
    func change<T>(_ edit: (inout Workspace) -> T) -> T {
        var copy = workspace
        let result = edit(&copy)
        if Sync.shared.assigns { SyncPlan.assignIDs(&copy) }
        if canUseWorkspace, copy != workspace {
            let old = workspace
            workspace = copy
            save()
            Sync.shared.changed(from: old, to: copy)
            // A split begun, ended or changed: each window's page beside, as it now is.
            for window in allWindows { window.workspaceChanged() }
        }
        return result
    }

    private func save() {
        guard canUseWorkspace else { return }
        store.save(workspace)
    }

    /// Whatever is waiting to be saved, now: the app is quitting.
    func saveNow() {
        guard canUseWorkspace else { return }
        store.saveAndWait(workspace)
    }

    /// After each workspace write: a failure is logged for Console and
    /// marked in workspaceSaveFailed, which the next success clears.
    private static func written(_ error: (any Error)?) {
        if let error { log.error("Workspace not saved: \(error.localizedDescription, privacy: .public)") }
        let failed = error != nil
        if shared.workspaceSaveFailed != failed { shared.workspaceSaveFailed = failed }
    }

    /// What a page says about itself, its address and title, saved with
    /// everything else half a second after the last change.
    func record(_ tab: UUID, url: URL?, title: String?) {
        // A page says both many times over; only news is a change to make and to tell.
        guard let known = workspace.tab(tab) else { return }
        if url == nil || known.url == url, title == nil || known.title == title { return }
        change { $0.record(tab, url: url, title: title) }
    }

    /// A tab closed: gone, or, when it is pinned, unloaded and back at its
    /// pinned page (Workspace.closeTab). Each window that showed it shows
    /// what its space has selected now.
    func closeTab(_ id: UUID) {
        let next = change { $0.closeTab(id) }
        for window in allWindows where window.tabID == id {
            // The next tab may be on screen in another window already: this one shows its space's start instead.
            let shown = next.flatMap { tab -> UUID? in
                let shower = self.window(showing: tab)
                return tab == id || shower == nil || shower === window ? tab : nil
            }
            // A pinned tab closed is the one selected still when it is the space's only tab: unloaded, not shown.
            window.show(tab: shown == id ? nil : shown, inSpace: window.spaceID)
        }
        pages.close(id)
    }

    /// Several tabs closed at once: the space's Clear, or Close Other Tabs.
    func closeTabs(_ ids: [UUID]) {
        for id in ids { closeTab(id) }
    }

    /// The windows on the space go to another first, so no page goes from under a window still showing it.
    func removeSpace(_ id: UUID) {
        guard workspace.spaces.count > 1, let space = workspace.space(id),
              let other = workspace.spaces.first(where: { $0.id != id }) else { return }
        for window in allWindows where window.spaceID == id {
            window.showSpace(other.id)
        }
        for tab in space.tabs { pages.close(tab.id) }
        change { _ = $0.removeSpace(id) }
        // Its extensions and their data first: WebKit won't remove a store
        // that an extension controller still holds.
        Extensions.shared.removeSpace(id)
        Stores.erase(id)
        HistoryRecorder.shared.removeSpace(id)
    }

    /// A tab into another space. A window that showed it shows what its own
    /// space has selected now, unless another window has that on screen.
    func moveTab(_ id: UUID, to space: UUID) {
        let from = workspace.spaceID(of: id)
        guard change({ $0.moveTab(id, to: space) }) else { return }
        for window in allWindows where window.tabID == id {
            let next = from.flatMap { workspace.space($0)?.selected }
            let shower = next.flatMap { self.window(showing: $0) }
            window.show(tab: shower == nil || shower === window ? next : nil, inSpace: window.spaceID)
        }
        // Signed in somewhere else now: the page loads again in that space's store.
        pages.moved(id)
    }

    // MARK: Windows

    func register(_ window: WindowModel) {
        windows.add(window)
        guard !waiting.isEmpty else { return }
        let urls = waiting
        waiting = []
        for url in urls { window.open(url, newTab: true) }
    }

    func unregister(_ window: WindowModel) {
        windows.remove(window)
    }

    var allWindows: [WindowModel] {
        windows.allObjects
    }

    /// The window with `tab` on screen, with the keys or beside them.
    func window(showing tab: UUID) -> WindowModel? {
        allWindows.first { $0.shows(tab) }
    }

    /// The tabs on screen: one per window, two where a split is.
    var shownTabs: Set<UUID> {
        Set(allWindows.flatMap { [$0.page == nil ? nil : $0.tabID, $0.partner?.tab].compactMap { $0 } })
    }

    /// The window in front, or the one used last.
    var frontWindow: WindowModel? {
        allWindows.first { $0.window?.isKeyWindow == true }
            ?? allWindows.first { $0.window?.isMainWindow == true }
            ?? allWindows.first
    }

    /// Links from other apps (`fromOtherApp`), each in a little window of
    /// its own, as Arc's Little Arc, unless Settings › General › Links says
    /// a tab (Preferences.linksFromApps). Files from Finder, the app's own
    /// links and links from other apps otherwise, each in a new tab of the
    /// window in front; a new window for them when there is none.
    func open(_ urls: [URL], fromOtherApp: Bool = false) {
        guard canUseWorkspace else { waiting += urls; return }
        let pages = urls.filter { ["http", "https", "file"].contains($0.scheme?.lowercased() ?? "") }
        guard !pages.isEmpty else { return }
        pages.filter(\.isFileURL).forEach { FileAccess.keep($0) }
        if fromOtherApp, preferences.linksFromApps == .littleWindow {
            for url in pages where !url.isFileURL { LittleWindow.open(url) }
            let files = pages.filter(\.isFileURL)
            guard !files.isEmpty else { return }
            return open(files)
        }
        if let window = frontWindow {
            for url in pages { window.open(url, newTab: true) }
            window.window?.makeKeyAndOrderFront(nil)
        } else {
            waiting += pages
            openWindow?(nil)
        }
    }
}

/// Web pages opened from Finder. The sandbox lets the app read such a file
/// only until it quits, and its tab keeps no more than the file's address:
/// each is kept as a security-scoped bookmark, so the tab still opens it
/// after a relaunch (Page.load).
@MainActor
enum FileAccess {
    private static let key = "fileBookmarks"
    /// The files read through their bookmarks since launch, which stay readable until the app quits.
    private static var opened: Set<URL> = []

    /// A bookmark to `url` while the app may read it, under `address`, the tab's.
    static func keep(_ url: URL, as address: URL? = nil) {
        guard url.isFileURL,
              let data = try? url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                              includingResourceValuesForKeys: nil, relativeTo: nil)
        else { return }
        var kept = UserDefaults.standard.dictionary(forKey: key) as? [String: Data] ?? [:]
        kept[(address ?? url).absoluteString] = data
        UserDefaults.standard.set(kept, forKey: key)
    }

    /// The file at `url` readable again through its bookmark, before a tab
    /// loads it; nothing for a file never opened from Finder, or a site.
    static func open(_ url: URL) {
        guard url.isFileURL, !opened.contains(url),
              let data = (UserDefaults.standard.dictionary(forKey: key) as? [String: Data])?[url.absoluteString]
        else { return }
        var stale = false
        guard let found = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil,
                                   bookmarkDataIsStale: &stale),
              found.startAccessingSecurityScopedResource()
        else { return }
        opened.insert(url)
        // A file moved or renamed since: its bookmark made again, for the next launch.
        if stale { keep(found, as: url) }
    }
}
