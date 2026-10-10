import Combine
import PadCore
import UIKit
import WebKit

/// Ads and trackers, blocked by WebKit's own content blocker with EasyList
/// and EasyPrivacy (ContentBlocking.swift in PadCore). The lists ship with
/// the app and are downloaded again when they say they are stale, four days
/// at the soonest; the app turns them into WebKit's rules and WebKit compiles
/// them into rule lists, kept on disk until the lists change. Every page but
/// a hands-off one gets them (Page.applyBlocking), unless Settings or the
/// site's own switch says no. Nothing runs in the page and nothing is read
/// from it: WebKit decides each load itself.
@MainActor
final class ContentBlocker: ObservableObject {
    static let shared = ContentBlocker()

    /// The compiled lists, in the order a page gets them.
    private(set) var lists: [WKContentRuleList] = []
    /// What Settings and Diagnostics say about it.
    @Published private(set) var summary = "Getting the lists ready…"
    /// What Settings lists, row by row: each list and the day it was made, and
    /// the rules WebKit has. Nil until the lists are ready.
    @Published private(set) var shown: Shown?

    struct Shown: Equatable {
        struct List: Equatable, Identifiable {
            let name: String
            let made: Date?
            var id: String { name }
        }
        var lists: [List]
        var rules: Int
        var dropped: Int
    }

    private let store = WKContentRuleListStore.default()
    private var saved = Saved()
    private var building = false
    /// Newer lists arrived while a build ran: one more build when it ends.
    private var buildAgain = false
    private var checking = false
    private var started = false
    private var observer: AnyCancellable?

    private struct Saved: Codable {
        /// The compiled lists' identifiers, in order.
        var identifiers: [String] = []
        /// Each list's "! Version:", by its id, and the converter that made the rules.
        var versions: [String: String] = [:]
        var converter = 0
        var rules = 0
        /// Lists WebKit turned down, left out.
        var dropped = 0
        /// When the lists were last asked for, and what their server said they were.
        var checked: Date?
        var expires: TimeInterval?
        var etags: [String: String] = [:]
        var modified: [String: String] = [:]
    }

    private static var folder: URL {
        Session.folder.appendingPathComponent("Filters", isDirectory: true)
    }

    private static var savedFile: URL {
        folder.appendingPathComponent("lists.json")
    }

    private static func downloaded(_ list: FilterList) -> URL {
        folder.appendingPathComponent("\(list.id).txt")
    }

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 30
        // Who is asking, as list maintainers ask apps to say.
        configuration.httpAdditionalHeaders = ["User-Agent": "Safience/1.0 (filter list update; +https://github.com/taehee-pd/Safience)"]
        return URLSession(configuration: configuration)
    }()

    // MARK: Starting

    /// At launch, and when Settings turns blocking on: the lists compiled
    /// last time if WebKit still has them, made again otherwise; then a look
    /// for newer ones if they are due.
    func start() {
        guard Session.shared.preferences.blocksContent, !started else { return }
        started = true
        if let data = try? Data(contentsOf: Self.savedFile), let read = try? JSONDecoder().decode(Saved.self, from: data) {
            saved = read
        }
        observer = NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.checkIfDue() } }
        Task {
            // Compiled lists are kept only while they are what the lists on
            // disk and this converter would make: a download that came in
            // as the app quit, or a new converter, makes them again.
            if saved.converter == ContentBlocking.converterVersion, saved.versions == Self.versionsOnDisk(),
               await lookUpSaved() {
                announce()
            } else {
                await build()
            }
            checkIfDue()
        }
    }

    /// The lists' texts: downloaded, or as they shipped.
    private static func texts() -> [String] {
        ContentBlocking.lists.map { list in
            (try? String(contentsOf: downloaded(list), encoding: .utf8)) ?? ContentBlocking.bundled(list) ?? ""
        }
    }

    /// Each list's "! Version:" as the text on disk has it, read from its header alone.
    private static func versionsOnDisk() -> [String: String] {
        var out: [String: String] = [:]
        for (list, text) in zip(ContentBlocking.lists, texts()) {
            out[list.id] = FilterConverter.convert(String(text.prefix(1_000))).version ?? ""
        }
        return out
    }

    private func lookUpSaved() async -> Bool {
        guard let store, !saved.identifiers.isEmpty else { return false }
        var found: [WKContentRuleList] = []
        for id in saved.identifiers {
            guard let list = await withCheckedContinuation({ (done: CheckedContinuation<WKContentRuleList?, Never>) in
                store.lookUpContentRuleList(forIdentifier: id) { list, _ in done.resume(returning: list) }
            }) else { return false }
            found.append(list)
        }
        lists = found
        return true
    }

    // MARK: Making the rule lists

    /// The lists' texts (downloaded, or as they shipped) turned into rules
    /// away from the main thread, then compiled by WebKit one list at a
    /// time. A list WebKit turns down is left out; the others still block.
    private func build() async {
        guard let store else { return }
        guard !building else {
            buildAgain = true
            return
        }
        building = true
        defer {
            building = false
            if buildAgain {
                buildAgain = false
                Task { await build() }
            }
        }
        summary = "Getting the lists ready…"
        shown = nil
        let texts = Self.texts()
        let (plan, converted) = await Task.detached(priority: .utility) {
            let converted = texts.map(FilterConverter.convert)
            return (ContentBlocking.plan(converted), converted)
        }.value
        var compiled: [WKContentRuleList] = []
        var rules = 0
        var dropped = 0
        for planned in plan {
            let list = await withCheckedContinuation { (done: CheckedContinuation<WKContentRuleList?, Never>) in
                store.compileContentRuleList(forIdentifier: planned.id, encodedContentRuleList: planned.json) { list, _ in
                    done.resume(returning: list)
                }
            }
            if let list {
                compiled.append(list)
                rules += planned.rules
            } else {
                dropped += 1
            }
        }
        lists = compiled
        saved.identifiers = compiled.compactMap(\.identifier)
        saved.rules = rules
        saved.dropped = dropped
        saved.versions = Dictionary(uniqueKeysWithValues: zip(ContentBlocking.lists.map(\.id), converted.map { $0.version ?? "" }))
        saved.expires = converted.compactMap(\.expires).min()
        saved.converter = ContentBlocking.converterVersion
        save()
        removeOld(keeping: Set(saved.identifiers))
        announce()
    }

    /// Lists compiled from older versions, gone from the disk.
    private func removeOld(keeping: Set<String>) {
        guard let store else { return }
        store.getAvailableContentRuleListIdentifiers { identifiers in
            for id in identifiers ?? [] where id.hasPrefix("blocking.") && !keeping.contains(id) {
                store.removeContentRuleList(forIdentifier: id) { _ in }
            }
        }
    }

    /// Every page takes the new lists for its next load; Settings and
    /// Diagnostics say what there is.
    private func announce() {
        summary = Self.describe(saved)
        shown = Self.shown(saved)
        for page in Session.shared.pages.live.values { page.blockingChanged() }
    }

    private static func describe(_ saved: Saved) -> String {
        let count = saved.rules.formatted(.number)
        let dates = ContentBlocking.lists.compactMap { list -> String? in
            guard let version = saved.versions[list.id], let date = date(ofVersion: version) else { return nil }
            return "\(list.name) of \(date.formatted(date: .abbreviated, time: .omitted))"
        }
        var text = "\(count) rules" + (dates.isEmpty ? "" : ", from " + dates.joined(separator: " and "))
        if saved.dropped > 0 { text += "; \(saved.dropped) of the lists couldn't be used" }
        return text
    }

    private static func shown(_ saved: Saved) -> Shown {
        Shown(lists: ContentBlocking.lists.map { list in
                  .init(name: list.name, made: saved.versions[list.id].flatMap(date(ofVersion:)))
              },
              rules: saved.rules, dropped: saved.dropped)
    }

    /// "202610080509": the list's version is when it was made, in UTC.
    private static func date(ofVersion version: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMddHHmm"
        return formatter.date(from: version)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(saved) else { return }
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        try? data.write(to: Self.savedFile, options: .atomic)
    }

    // MARK: Newer lists

    /// Asks for newer lists when the ones there have expired: as often as
    /// they say, never sooner than four days. A list comes only if it
    /// changed (If-None-Match, If-Modified-Since), and only a real one is
    /// kept: what doesn't read as that list leaves the old one in place.
    func checkIfDue() {
        guard started, Session.shared.preferences.blocksContent, !checking else { return }
        let wait = max(saved.expires ?? 0, ContentBlocking.shortestRefresh)
        if let checked = saved.checked, Date().timeIntervalSince(checked) < wait { return }
        checking = true
        Task {
            defer { checking = false }
            var changed = false
            var answered = false
            for list in ContentBlocking.lists {
                var request = URLRequest(url: list.url)
                if let etag = saved.etags[list.id] { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
                if let modified = saved.modified[list.id] { request.setValue(modified, forHTTPHeaderField: "If-Modified-Since") }
                guard let (data, response) = try? await session.data(for: request),
                      let http = response as? HTTPURLResponse else { continue }
                answered = true
                guard http.statusCode == 200, let text = String(data: data, encoding: .utf8),
                      Self.isList(text, named: list.name) else { continue }
                try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
                guard (try? text.write(to: Self.downloaded(list), atomically: true, encoding: .utf8)) != nil else { continue }
                saved.etags[list.id] = http.value(forHTTPHeaderField: "ETag")
                saved.modified[list.id] = http.value(forHTTPHeaderField: "Last-Modified")
                changed = true
            }
            // Offline: asked again next time the app comes up, not in four days.
            guard answered else { return }
            saved.checked = Date()
            save()
            if changed { await build() }
        }
    }

    /// A filter list, not an error page or half a download: the header
    /// Adblock Plus lists start with, its own title, and thousands of filters.
    private static func isList(_ text: String, named name: String) -> Bool {
        text.hasPrefix("[Adblock Plus") && text.prefix(2_000).contains("! Title: \(name)")
            && text.utf8.count > 100_000
    }

    // MARK: Settings

    /// Settings turned blocking on or off.
    func preferencesChanged() {
        if Session.shared.preferences.blocksContent {
            start()
            summary = lists.isEmpty ? "Getting the lists ready…" : Self.describe(saved)
            shown = lists.isEmpty ? nil : Self.shown(saved)
        } else {
            summary = "Off"
        }
    }

    /// For Diagnostics.
    var status: String {
        guard Session.shared.preferences.blocksContent else { return "off in Settings" }
        if building { return "compiling the lists" }
        return "\(lists.count) lists, \(Self.describe(saved))"
    }
}
