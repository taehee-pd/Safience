import Foundation
import PadCore
import WebKit

/// Each space's history on this device, both apps': the store (HistoryStore,
/// in Application Support), what pages tell it, and what the command bar,
/// the History list and Settings ask of it. Writes go to the store one after
/// another, in the order they were made, so a page's name never arrives
/// before its visit.
@MainActor
final class HistoryRecorder: ObservableObject {
    static let shared = HistoryRecorder()

    /// Goes up as history changes, for what shows it to look again.
    @Published private(set) var revision = 0
    private let store: HistoryStore?
    /// The last write, which the next one waits for.
    private var chain: Task<Void, Never>?
    /// When history was last let go of past Settings' retention.
    private var pruned: Date?
    /// What the app is about to open, and how it was asked for (typed, a
    /// bookmark), by page and by search words: the visit that follows within
    /// a few seconds is that kind. Search engines rewrite their addresses as
    /// they load, so a search is known by its words.
    private var expected: [String: (kind: HistoryKind, at: Date)] = [:]
    /// How long, in seconds, an expectation holds for the visit that follows.
    private static let expectationWindow: TimeInterval = 15

    private init() {
        let folder = Session.folder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("history.sqlite")
        store = try? HistoryStore(url: file)
        #if os(iOS)
        // Readable once the device has been unlocked after starting, as the workspace is.
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                                               ofItemAtPath: file.path)
        #endif
        // The sync clock (sync.json) may have been written before the last
        // clearing or visit seen from a device ahead was: it starts after
        // them, before any visit is made.
        if let latest = store?.latestWhenOpened { Sync.shared.saw(latest) }
    }

    // MARK: Pages

    /// The app is about to open `url` as asked: typed in the command bar, or a bookmark.
    func expect(_ kind: HistoryKind, _ url: URL) {
        let now = Date()
        expected = expected.filter { now.timeIntervalSince($0.value.at) < Self.expectationWindow }
        expected[Self.expectation(for: url)] = (kind, now)
    }

    /// Whether the app has just been asked to open `url` (expect).
    func isExpected(_ url: URL) -> Bool {
        guard let asked = expected[Self.expectation(for: History.address(url))] else { return false }
        return Date().timeIntervalSince(asked.at) < Self.expectationWindow
    }

    /// How the app was just asked to open `url`, if it was: told once, as
    /// its navigation starts, so the kind holds through redirects to
    /// another address (apple.com to www.apple.com).
    func takeExpectation(_ url: URL) -> HistoryKind? {
        guard let asked = expected.removeValue(forKey: Self.expectation(for: History.address(url))),
              Date().timeIntervalSince(asked.at) < Self.expectationWindow else { return nil }
        return asked.kind
    }

    private static func expectation(for url: URL) -> String {
        Destination.searchWords(in: url, engine: Session.shared.preferences.engine).map { "search:" + $0 }
            ?? History.pageKey(History.address(url))
    }

    /// A page gone to: kept, unless it isn't to be (History.keeps). The
    /// visit's id, for the page to name it and take it back.
    func visit(space: UUID, url: URL, title: String?, kind: HistoryKind) -> UUID? {
        guard History.keeps(url) else { return nil }
        let address = History.address(url)
        var kind = kind
        let expectation = Self.expectation(for: address)
        if let asked = expected.removeValue(forKey: expectation), Date().timeIntervalSince(asked.at) < Self.expectationWindow {
            kind = asked.kind
        }
        let search = kind == .typed ? Destination.searchWords(in: address, engine: Session.shared.preferences.engine) : nil
        // Its time by this device's clock, as it is shown and kept; its
        // stamp by the sync clock, later than any clearing this device has taken.
        let visit = HistoryVisit(space: space, url: address, title: title ?? "", time: Date(), stamp: Sync.shared.stampNow(),
                                 device: Sync.shared.deviceID, kind: kind, search: search)
        then { try await $0.record(visit) }
        HistoryCloud.shared.recorded(visit.id)
        HistoryCloud.shared.visited(space: space, time: visit.time)
        prune()
        return visit.id
    }

    /// What a page is called, or says it is about, as that comes in.
    func page(space: UUID, url: URL, title: String?, summary: String?) {
        guard History.keeps(url) else { return }
        let address = History.address(url)
        let me = Sync.shared.deviceID
        then { store in
            // The day of this device's last visit to it, which may be
            // yesterday's (by iCloud's day) for a name that came after midnight:
            // its record goes again, with the name and description it has now.
            guard let time = try await store.update(space: space, url: address, title: title, summary: summary, device: me)
            else { return }
            await MainActor.run { HistoryCloud.shared.visited(space: space, time: time) }
        }
    }

    /// A visit taken back: the page asked for a password after all.
    func forget(_ visit: UUID) {
        then { store in
            guard let gone = try await store.forget(visit: visit) else { return }
            // Its day goes again without it, if it went at all.
            await MainActor.run { HistoryCloud.shared.visited(space: gone.space, time: gone.time) }
            // Old enough to have gone to iCloud already: the other devices
            // that took it let it go too, as they do what a clearing covers.
            guard await MainActor.run(body: { HistoryCloud.shared.mayHaveSent(visit) }) else { return }
            let made = await MainActor.run { Sync.shared.stampNow() }
            let removal = HistoryRemoval(space: gone.space, scope: .visit(visit), made: made, wall: Date())
            try await store.remove(removal)
            await MainActor.run { HistoryCloud.shared.withdrawn(removal) }
        }
    }

    // MARK: Clearing

    /// History cleared in a space, or every one: the store's, and the
    /// closed tabs' that Reopen Closed Tab would bring back.
    func clear(space: UUID?, scope: HistoryRemoval.Scope) {
        // By the sync clock: later than every visit this device has seen,
        // so it clears all it showed, whatever the other devices' clocks.
        let made = Sync.shared.stampNow()
        var scope = scope
        // A stretch up to now runs up to the clearing's own time: a visit
        // from a device whose clock is ahead is dated after now here, but
        // never after the clearing's stamp, once this device has seen it.
        if case let .range(from, to) = scope, to >= Date().addingTimeInterval(-1) {
            scope = .range(from: from, to: max(to, made))
        }
        let removal = HistoryRemoval(space: space, scope: scope, made: made, wall: Date())
        let me = Sync.shared.deviceID
        then { store in
            let days = try await store.remove(removal, daysOf: me)
            await MainActor.run { HistoryCloud.shared.cleared(removal, days: days) }
        }
        dropClosedTabs(space: space, scope: scope, madeAt: removal.wall ?? removal.made)
    }

    /// The closed tabs a clearing covers, here or on another device: Reopen Closed Tab brings none of them back.
    /// Only those last on screen before the clearing was made, as with the
    /// visits it covers (HistoryRemoval.covers): one that comes late, from a
    /// device that was offline or from a backfill, leaves what came after it.
    func dropClosedTabs(space: UUID?, scope: HistoryRemoval.Scope, madeAt made: Date) {
        Session.shared.change { workspace in
            workspace.closed.removeAll { closed in
                guard space == nil || closed.space == space, closed.tab.shown <= made else { return false }
                switch scope {
                case .all:
                    return true
                case .page(let digest):
                    return closed.tab.url.map { History.digest(ofKey: History.pageKey($0)) } == digest
                case .range(let from, let to):
                    return closed.tab.shown >= from && closed.tab.shown <= to
                case .visit:
                    return false
                }
            }
        }
    }

    /// History past Settings' retention let go, and the history of spaces
    /// gone (here or on another device); at most once a day unless asked.
    func prune(now: Date = Date(), always: Bool = false) {
        guard Session.shared.canUseWorkspace else { return }
        guard always || pruned.map({ now.timeIntervalSince($0) > 86_400 }) ?? true else { return }
        pruned = now
        let retention = Session.shared.preferences.historyRetention
        let spaces = Set(Session.shared.workspace.spaces.map(\.id))
        then { store in
            try await store.prune(keeping: retention, now: now)
            try await store.keepSpaces(spaces)
        }
        HistoryCloud.shared.pruned(before: retention.cutoff(now: now))
    }

    func removeSpace(_ space: UUID) {
        then { try await $0.removeSpace(space) }
        HistoryCloud.shared.spaceRemoved()
    }

    // MARK: Finding

    /// The space's pages for what is typed (HistoryQuery: words, and when),
    /// among the visits the filter lets in.
    func search(space: UUID, text: String, limit: Int = 30, filter: HistoryFilter = HistoryFilter()) async -> [HistoryPage] {
        await search(space: space, query: HistoryQuery.parse(text, now: Date()), limit: limit, filter: filter)
    }

    func search(space: UUID, query: HistoryQuery, limit: Int = 30, filter: HistoryFilter = HistoryFilter()) async -> [HistoryPage] {
        guard let store else { return [] }
        await chain?.value
        let scope = filter.scope(device: Sync.shared.deviceID, now: Date())
        return (try? await store.search(space: space, query: query, limit: limit, scope: scope)) ?? []
    }

    /// Words too common to look for a page by, when any one of the words will do.
    private static let common: Set<String> = ["the", "and", "that", "this", "with", "from", "about", "what", "when", "where",
                                              "which", "for", "was", "were", "have", "had", "page", "site", "one", "some"]

    /// The pages Apple Intelligence is shown for what is typed, to read
    /// for meaning (Autocomplete.intentQuestion's `history`): those any
    /// one of the words is in, then the space's most wanted, within the
    /// time the words name if they name one; `limit` at most. The letters
    /// alone find only pages with every word in them (search); "that
    /// article about glass" finds none.
    func recall(space: UUID, text: String, limit: Int = Autocomplete.historySlots) async -> [HistoryPage] {
        guard let store else { return [] }
        await chain?.value
        let query = HistoryQuery.parse(text, now: Date())
        let words = query.words.lowercased().split { !($0.isLetter || $0.isNumber) }.map(String.init)
            .filter { word in
                // Two letters are a word in Korean, Japanese and Chinese.
                let wide = word.unicodeScalars.contains { $0.value >= 0x1100 }
                return (word.count >= 3 || (wide && word.count >= 2)) && !Self.common.contains(word)
            }
        var pages: [HistoryPage] = []
        var seen: Set<String> = []
        func add(_ found: [HistoryPage]) {
            for page in found where pages.count < limit && seen.insert(page.key).inserted { pages.append(page) }
        }
        var unique: [String] = []
        for word in words where !unique.contains(word) { unique.append(word) }
        for word in unique.prefix(5) {
            add((try? await store.search(space: space, query: HistoryQuery(words: word, from: query.from, to: query.to), limit: 5)) ?? [])
        }
        add((try? await store.search(space: space, query: HistoryQuery(words: "", from: query.from, to: query.to), limit: limit)) ?? [])
        return pages
    }

    /// The space's visits the filter lets in, newest first, for the History list.
    func entries(space: UUID, before: Date? = nil, limit: Int = 200, filter: HistoryFilter = HistoryFilter()) async -> [HistoryEntry] {
        guard let store else { return [] }
        await chain?.value
        let scope = filter.scope(device: Sync.shared.deviceID, now: Date())
        return (try? await store.entries(space: space, before: before, limit: limit, scope: scope)) ?? []
    }

    // MARK: Writing in order

    /// A write, after those before it. `changes`: what shows history looks again after it.
    private func then(changes: Bool = true, _ work: @escaping @Sendable (HistoryStore) async throws -> Void) {
        guard Session.shared.canUseWorkspace, let store else { return }
        let previous = chain
        chain = Task { [weak self] in
            await previous?.value
            try? await work(store)
            if changes { self?.revision += 1 }
        }
    }

    // MARK: For iCloud (HistoryCloud)

    func read<T: Sendable>(_ work: @escaping @Sendable (HistoryStore) async throws -> T) async -> T? {
        guard let store else { return nil }
        await chain?.value
        return try? await work(store)
    }

    func write(changes: Bool = true, _ work: @escaping @Sendable (HistoryStore) async throws -> Void) {
        then(changes: changes, work)
    }
}

/// What a page knows of its own history: how its next document is being
/// come to, and the visit the one on screen is. Each Page has one; it tells
/// HistoryRecorder of a visit once a document is committed (not as its
/// address changes on the way), never for a reload or a step back or
/// forward, and never for a pop-up, which is no tab of the workspace's.
@MainActor
struct PageHistory {
    /// What the main-frame navigation decided and not committed yet is:
    /// nothing yet, no visit (a reload, a step back), or a visit and how it
    /// was come to (HistoryRecorder.expect knows when it was typed or a bookmark).
    private enum Next: Equatable {
        case none
        case ignored
        case visit(HistoryKind)
    }

    private var next = Next.none
    /// The visit the document on screen is, and its page.
    private var visit: UUID?
    private var key: String?
    /// A sign-in page turned up in this document: nothing of it is kept.
    private var withheld = false
    /// The document shows a password field now, as the page last said
    /// (signInFound, signInGone): its pages are sign-in pages until it goes.
    private var password = false
    /// The name the visit was last given, and when the visit began: a page
    /// is named as it loads, and one that goes on renaming itself (unread
    /// counts, a player's time) isn't written down each time.
    private var named: String?
    private var began = Date.distantPast
    private static let naming: TimeInterval = 30
    /// The next document is the tab's own coming back (restoring): not a visit.
    private var restored = false
    /// The tab's back and forward entries visits were made at: a step back
    /// or forward to one, within a web app's own pages, is no new visit.
    private var entries: [WKBackForwardListItem] = []

    private mutating func entered(_ entry: WKBackForwardListItem?) {
        guard let entry, !entries.contains(where: { $0 === entry }) else { return }
        entries.append(entry)
        if entries.count > 100 { entries.removeFirst(entries.count - 100) }
    }

    mutating func restoring() {
        next = .ignored
        restored = true
    }

    /// A main-frame navigation WebKit is about to make. A redirect, or a
    /// request sent again (with another user agent, or the screen's light
    /// or dark), comes back here as `.other`, and keeps what the first said.
    mutating func decided(_ type: WKNavigationType, url: URL?) {
        // Coming back, through any redirect, until its document is
        // committed; unless this is a page asked for meanwhile: a link, a
        // form, an address typed or a bookmark.
        if restored {
            let asked = type == .linkActivated || type == .formSubmitted || url.map(HistoryRecorder.shared.isExpected) == true
            guard asked else {
                next = .ignored
                return
            }
            restored = false
        }
        switch type {
        case .backForward, .reload, .formResubmitted:
            next = .ignored
        default:
            if let url, let asked = HistoryRecorder.shared.takeExpectation(url) {
                next = .visit(asked)
            } else if type == .other, next != .none {
                return
            } else {
                next = .visit(type == .linkActivated || type == .formSubmitted ? .link : .other)
            }
        }
    }

    /// A load that failed: what it was decided as is not carried to the next.
    mutating func failed() {
        next = .none
    }

    /// A document committed: a visit, if it was decided as one.
    mutating func committed(url: URL?, title: String?, entry: WKBackForwardListItem?, space: UUID, tab: UUID) {
        entered(entry)
        withheld = false
        password = false
        restored = false
        visit = nil
        let decided = next
        next = .none
        key = url.map(History.pageKey)
        guard case .visit(let kind) = decided, let url, Session.shared.workspace.tab(tab) != nil else { return }
        visit = HistoryRecorder.shared.visit(space: space, url: url, title: title, kind: kind)
        named = title
        began = Date()
    }

    /// The page became a tab's as it is, with no load (a Mac's Peek or little
    /// window opened in a tab): the document on screen, kept nowhere while
    /// the page was no tab's, is a visit now, unless it is a sign-in's.
    mutating func adopted(url: URL?, title: String?, entry: WKBackForwardListItem?, space: UUID, tab: UUID) {
        guard visit == nil, !withheld, !password, let url, Session.shared.workspace.tab(tab) != nil else { return }
        entered(entry)
        key = History.pageKey(url)
        visit = HistoryRecorder.shared.visit(space: space, url: url, title: title, kind: .link)
        named = title
        began = Date()
    }

    /// The page's address or name changed: its name for the visit; or, with
    /// no load under way, a page that moved to another of its own pages
    /// without loading (a web app), a visit of its own.
    mutating func changed(url: URL?, title: String?, entry: WKBackForwardListItem?, loading: Bool, space: UUID, tab: UUID) {
        guard let url else { return }
        let now = History.pageKey(url)
        if now == key {
            // A new name, while the page is still coming in or had none yet.
            if !withheld, visit != nil, let title, !title.isEmpty, title != named,
               named?.isEmpty ?? true || Date().timeIntervalSince(began) < Self.naming {
                named = title
                HistoryRecorder.shared.page(space: space, url: url, title: title, summary: nil)
            }
            return
        }
        guard !loading, Session.shared.workspace.tab(tab) != nil else { return }
        key = now
        // A step back or forward within the web app's own pages: WebKit
        // decided it so, with no document to commit; or it is to a page of
        // this tab's it was on already. No new visit.
        let stepped = next == .ignored
        if stepped { next = .none }
        if stepped || entries.contains(where: { $0 === entry }) { return }
        entered(entry)
        // Still showing a password field (/account/step1 to /step2): a
        // sign-in page too, though the field didn't come or go to say so.
        if password {
            visit = nil
            withheld = true
            return
        }
        // Another of the web app's own pages (/watch?v=2 after ?v=1): the
        // sign-in it may have left behind is not this one.
        withheld = false
        visit = HistoryRecorder.shared.visit(space: space, url: url, title: title, kind: .link)
        named = title
        began = Date()
    }

    /// What the page says it is about (its meta description).
    func described(_ text: String?, url: URL?, space: UUID) {
        guard !withheld, visit != nil, let url, let text, !text.isEmpty, History.pageKey(url) == key else { return }
        HistoryRecorder.shared.page(space: space, url: url, title: nil, summary: text)
    }

    /// The page asks for a password: its visit taken back, and nothing more of it kept.
    mutating func signInFound() {
        if let visit { HistoryRecorder.shared.forget(visit) }
        visit = nil
        withheld = true
        password = true
    }

    /// The password field is gone. The page on screen stays out of history,
    /// even if the field went as the address changed (a sign-in that moves
    /// on to the app's own page): which of the two came first can't be told
    /// here, so the next page the app moves to is the first one kept.
    mutating func signInGone() {
        password = false
    }
}
