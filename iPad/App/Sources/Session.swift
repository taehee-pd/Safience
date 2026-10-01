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
    }

    // MARK: The workspace

    /// Every change to the workspace goes through here: saved a moment
    /// later, and every window hears of it.
    @discardableResult
    func change<T>(_ edit: (inout Workspace) -> T) -> T {
        var copy = workspace
        let result = edit(&copy)
        if copy != workspace {
            workspace = copy
            save()
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

    func closeTab(_ id: UUID) {
        let next = change { $0.closeTab(id) }
        pages.close(id)
        for window in allBrowsers where window.model.tabID == id {
            window.show(tab: next.flatMap { browser(showing: $0) == nil ? $0 : nil }, inSpace: window.model.spaceID)
        }
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

    func browser(showing tab: UUID) -> Browser? {
        allBrowsers.first { $0.model.tabID == tab && $0.isConnected }
    }

    /// The tabs on screen, one per window.
    var shownTabs: Set<UUID> {
        Set(allBrowsers.filter(\.isConnected).compactMap(\.model.tabID))
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
