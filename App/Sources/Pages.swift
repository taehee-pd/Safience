import PadCore
import UIKit
import WebKit

/// Every tab's page: live, or frozen to a picture.
///
/// A live page keeps its WebKit content process. A frozen one keeps a
/// picture of how it looked and what WebKit needs to load it back where it
/// was, and nothing else: opening it shows the picture while the page loads
/// again underneath. Which tabs stay live is the Freezer's choice
/// (Memory.swift in PadCore): the tabs on screen, one heavy tab, a couple of
/// light ones, and under memory pressure only the tabs on screen.
@MainActor
final class Pages {
    private(set) var live: [UUID: Page] = [:]
    private var pictures: [UUID: UIImage] = [:]
    private var states: [UUID: Any] = [:]
    /// Tabs being frozen right now, so they aren't frozen twice.
    private var freezing: Set<UUID> = []
    private var pressure: DispatchSourceMemoryPressure?

    /// The tab's page, made and loaded when it was frozen or never opened.
    /// `thawed` says it was, so the window can show the picture meanwhile.
    func page(for tab: TabRecord, in space: UUID) -> (page: Page, thawed: Bool) {
        if let page = live[tab.id] { return (page, false) }
        let page = Page(tab: tab.id, space: space)
        live[tab.id] = page
        if let state = states.removeValue(forKey: tab.id) ?? Snapshots.state(for: tab.id) {
            page.view.interactionState = state
        }
        // No state, or one WebKit couldn't use: the tab's address.
        if page.view.url == nil, let url = tab.url {
            page.load(url)
        }
        return (page, true)
    }

    /// A page WebKit made for a tab, opened by another page.
    func adopt(tab: UUID, space: UUID, configuration: WKWebViewConfiguration) -> Page {
        live[tab]?.tearDown()
        let page = Page(tab: tab, space: space, configuration: configuration)
        live[tab] = page
        return page
    }

    func picture(for tab: UUID) -> UIImage? {
        if let picture = pictures[tab] { return picture }
        let saved = Snapshots.picture(for: tab)
        pictures[tab] = saved
        return saved
    }

    func isLive(_ tab: UUID) -> Bool {
        live[tab] != nil
    }

    /// Tabs whose page is not live: frozen, or never opened this run.
    var frozenCount: Int {
        Session.shared.workspace.spaces.reduce(0) { $0 + $1.tabs.count } - live.count
    }

    /// A tab closed for good: its page, its picture, everything.
    func close(_ tab: UUID) {
        live.removeValue(forKey: tab)?.tearDown()
        pictures[tab] = nil
        states[tab] = nil
        Snapshots.remove(tab)
    }

    /// Freezes what the Freezer says should be frozen now.
    func enforce(pressure: Bool = false) {
        let session = Session.shared
        let shown = session.shownTabs
        var loads: [TabLoad] = []
        for space in session.workspace.spaces {
            for tab in space.tabs {
                let page = live[tab.id]
                loads.append(TabLoad(
                    id: tab.id,
                    heavy: page?.isHeavy ?? Adapters.adapter(for: tab.url).isHeavy(tab.url),
                    onScreen: shown.contains(tab.id),
                    live: page != nil,
                    lastShown: tab.shown,
                    mustStay: page?.mustStay ?? false
                ))
            }
        }
        for tab in Freezer.plan(loads, limits: session.preferences.limits, pressure: pressure) {
            freeze(tab, force: pressure)
        }
    }

    /// Asks the page whether it holds anything typed, pictures it, then
    /// lets it go, looking again before each step: each takes a moment, and
    /// the tab may have come back on screen meanwhile.
    func freeze(_ tab: UUID, force: Bool = false) {
        guard let page = live[tab], !freezing.contains(tab) else { return }
        freezing.insert(tab)
        page.holdsTyping { [weak self] typed in
            guard let self else { return }
            guard force || typed == false, !Session.shared.shownTabs.contains(tab), self.live[tab] === page else {
                self.freezing.remove(tab)
                return
            }
            page.picture { [weak self] picture in
                guard let self else { return }
                self.freezing.remove(tab)
                guard !Session.shared.shownTabs.contains(tab), self.live[tab] === page else { return }
                if let picture {
                    self.pictures[tab] = picture
                    // Never a picture of a sign-in page on disk: it can hold
                    // an email address or a half-typed password.
                    if !page.isSignIn { Snapshots.save(picture, for: tab) }
                }
                self.release(page)
            }
        }
    }

    /// A page off screen whose process ended: frozen as it stands, with the
    /// picture it had, if any.
    func processEnded(_ page: Page) {
        guard live[page.tab] === page else { return }
        self.release(page)
    }

    /// Takes a tab's page down when the tab moves to another space, whose
    /// store is not the one the page was signed in with.
    func moved(_ tab: UUID) {
        live.removeValue(forKey: tab)?.tearDown()
        states[tab] = nil
    }

    private func release(_ page: Page) {
        if let state = page.view.interactionState {
            states[page.tab] = state
            if !page.isSignIn { Snapshots.save(state: state, for: page.tab) }
        }
        live[page.tab] = nil
        page.tearDown()
    }

    /// Memory pressure, from the system: every tab that can freeze, does.
    func watchMemory() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.enforce(pressure: true) }
        }
        source.resume()
        pressure = source
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.enforce(pressure: true) }
        }
    }
}
