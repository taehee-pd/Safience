import Combine
import PadCore
import UIKit

/// What every window shares: the spaces and their tabs, the settings, the
/// pages, and the windows themselves.
///
/// Windows (one per scene, Stage Manager's or Split View's) each show one
/// tab. A tab is on screen in one window at a time; choosing a tab that
/// another window shows brings that window forward instead.
@MainActor
final class Session: ObservableObject {
    static let shared = Session()

    @Published private(set) var workspace: Workspace
    @Published var preferences: Preferences {
        didSet {
            guard preferences != oldValue else { return }
            if let data = try? JSONEncoder().encode(preferences) {
                UserDefaults.standard.set(data, forKey: Session.preferencesKey)
            }
            for page in pages.live.values { page.settingsChanged() }
            if preferences.limits != oldValue.limits { pages.enforce() }
            if preferences.blocksContent != oldValue.blocksContent { ContentBlocker.shared.preferencesChanged() }
            if preferences.iCloudSync != oldValue.iCloudSync {
                if preferences.iCloudSync { Sync.shared.start(join: true) } else { Sync.shared.stop() }
            }
        }
    }

    let pages = Pages()
    private let browsers = NSHashTable<Browser>.weakObjects()
    private var saving: DispatchWorkItem?

    private static let preferencesKey = "preferences"

    static var folder: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return support.appendingPathComponent("Safience", isDirectory: true)
    }

    static var workspaceFile: URL {
        folder.appendingPathComponent("workspace.json")
    }

    private init() {
        workspace = WorkspaceFile.read(Session.workspaceFile) ?? .starting()
        preferences = UserDefaults.standard.data(forKey: Session.preferencesKey)
            .flatMap { try? JSONDecoder().decode(Preferences.self, from: $0) } ?? Preferences()
    }

    /// Once, at launch, before the first window.
    func start() {
        Stores.sweep()
        Snapshots.prune(keeping: Set(workspace.spaces.flatMap { $0.tabs.map(\.id) }))
        pages.watchMemory()
        ContentBlocker.shared.start()
        if preferences.iCloudSync { Sync.shared.start(join: false) }
    }

    // MARK: The workspace

    /// Every change to the workspace goes through here: saved a moment
    /// later, and every window hears of it.
    @discardableResult
    func change<T>(_ edit: (inout Workspace) -> T) -> T {
        var copy = workspace
        let result = edit(&copy)
        if Sync.shared.assigns { SyncPlan.assignIDs(&copy) }
        if copy != workspace {
            let old = workspace
            workspace = copy
            save()
            Sync.shared.changed(from: old, to: copy)
        }
        return result
    }

    private func save() {
        saving?.cancel()
        let snapshot = workspace
        let work = DispatchWorkItem {
            try? WorkspaceFile.write(snapshot, to: Session.workspaceFile)
        }
        saving = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    /// What a page says about itself, its address and title, saved with
    /// everything else half a second after the last change.
    func record(_ tab: UUID, url: URL?, title: String?) {
        change { $0.record(tab, url: url, title: title) }
    }

    /// A tab closed: gone, or, when it is pinned, unloaded and back at its
    /// pinned page (Workspace.closeTab), when it may be the one to show.
    func closeTab(_ id: UUID) {
        let next = change { $0.closeTab(id) }
        // A pane beside a tab on screen goes before its page does.
        for window in allBrowsers where window.partner?.tab == id { window.syncSplit() }
        for window in allBrowsers where window.model.tabID == id {
            // The tab beside it in a split is this window's already: it stays.
            let shown = next.flatMap { tab -> UUID? in
                let shower = browser(showing: tab)
                return tab == id || shower == nil || shower === window ? tab : nil
            }
            window.show(tab: shown, inSpace: window.model.spaceID)
        }
        // Its page goes once no window has it up.
        pages.close(id)
    }

    /// Several tabs closed: the ones no window shows first, so no window
    /// goes to a tab about to go, then the ones on screen.
    func closeTabs(_ ids: [UUID]) {
        let shown = Set(allBrowsers.compactMap(\.model.tabID))
        for id in ids.filter({ !shown.contains($0) }) + ids.filter({ shown.contains($0) }) {
            closeTab(id)
        }
    }

    /// A bookmarks file into a space: an HTML export (Chrome's, Safari's,
    /// Firefox's) or the ZIP of Safari's Export Browsing Data with one in it.
    /// Returns what to tell the person who chose it.
    func importBookmarks(from file: URL, into space: UUID) -> (title: String, message: String) {
        guard let data = try? Data(contentsOf: file) else {
            return ("Couldn’t Read the File", "Choose the file again, or save a copy to On My \(Device.name) first.")
        }
        var html = data
        if ZipFile.isArchive(data) {
            guard let inside = ZipFile.file(in: data, matching: { $0.lowercased().hasSuffix("bookmarks.html") }) else {
                return ("No Bookmarks in This Archive",
                        "In Settings › Apps › Safari › Export, choose Bookmarks, then import the ZIP it saves to Downloads.")
            }
            html = inside
        }
        let read = BookmarkFile.parse(html)
        guard read.count > 0 else {
            return ("No Bookmarks Found", "Export them from Chrome (Bookmark Manager › Export Bookmarks) or Safari, then choose that file.")
        }
        let added = change { $0.importBookmarks(read.items, into: space) }
        SiteIcons.shared.adopt(read.icons)
        let name = workspace.space(space)?.name ?? "this space"
        guard added > 0 else { return ("Already There", "Every bookmark in the file is in \(name) already.") }
        return ("Bookmarks Imported", "\(added) of \(read.count) bookmarks added to \(name). They show on every new tab in it.")
    }

    func removeSpace(_ id: UUID) {
        guard workspace.spaces.count > 1, let space = workspace.space(id) else { return }
        for tab in space.tabs { pages.close(tab.id) }
        change { _ = $0.removeSpace(id) }
        Stores.erase(id)
        for window in allBrowsers where window.model.spaceID == id {
            window.showSpace(workspace.spaces[0].id)
        }
    }

    func moveTab(_ id: UUID, to space: UUID) {
        guard change({ $0.moveTab(id, to: space) }) else { return }
        // Signed in somewhere else now: the page loads again in that space's store.
        pages.moved(id)
        for window in allBrowsers where window.model.tabID == id {
            window.show(tab: id, inSpace: space)
        }
    }

    // MARK: Windows

    func register(_ browser: Browser) {
        browsers.add(browser)
    }

    func unregister(_ browser: Browser) {
        browsers.remove(browser)
    }

    var allBrowsers: [Browser] {
        browsers.allObjects
    }

    /// The window with `tab` on screen, alone or as one of a split's panes.
    func browser(showing tab: UUID) -> Browser? {
        allBrowsers.first { $0.shows(tab) && $0.isConnected }
    }

    /// The tabs on screen: one per window, two in a split.
    var shownTabs: Set<UUID> {
        Set(allBrowsers.filter(\.isConnected).flatMap(\.shownTabs))
    }

    /// A new window, through the system, showing `space` and `tab`.
    func openWindow(space: UUID?, tab: UUID?) {
        var request = UISceneSessionActivationRequest(role: .windowApplication)
        request.userActivity = WindowState(space: space, tab: tab).activity
        UIApplication.shared.activateSceneSession(for: request) { error in
            NSLog("Safience: no new window: \(error.localizedDescription)")
        }
    }

    func bringForward(_ browser: Browser) {
        guard let session = browser.view.window?.windowScene?.session else { return }
        let request = UISceneSessionActivationRequest(session: session)
        UIApplication.shared.activateSceneSession(for: request) { _ in }
    }
}

/// Which space and tab a window shows, kept by the system with the window
/// so each comes back as it was.
struct WindowState {
    var space: UUID?
    var tab: UUID?

    static var activityType: String {
        (Bundle.main.bundleIdentifier ?? "Safience") + ".window"
    }

    init(space: UUID?, tab: UUID?) {
        self.space = space
        self.tab = tab
    }

    init(activity: NSUserActivity?) {
        let info = activity?.activityType == WindowState.activityType ? activity?.userInfo : nil
        space = (info?["space"] as? String).flatMap(UUID.init(uuidString:))
        tab = (info?["tab"] as? String).flatMap(UUID.init(uuidString:))
    }

    var activity: NSUserActivity {
        let activity = NSUserActivity(activityType: WindowState.activityType)
        var info: [String: String] = [:]
        if let space { info["space"] = space.uuidString }
        if let tab { info["tab"] = tab.uuidString }
        activity.addUserInfoEntries(from: info)
        return activity
    }
}
