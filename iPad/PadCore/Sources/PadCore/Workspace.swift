import Foundation

/// One tab as it is kept between launches: where it was and what it was
/// called. The page itself lives in the app (Pages.swift), live or frozen.
public struct TabRecord: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var url: URL?
    public var title: String
    /// When it was last on screen: the freezer keeps the most recent ones.
    public var shown: Date

    public init(id: UUID = UUID(), url: URL?, title: String = "", shown: Date = .distantPast) {
        self.id = id
        self.url = url
        self.title = title
        self.shown = shown
    }

    /// The name a row shows: the page's title, else its address, else
    /// "New Tab" for a tab that has gone nowhere yet.
    public var label: String {
        let named = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !named.isEmpty { return named }
        return url.map(Address.pretty) ?? "New Tab"
    }
}

/// A set of tabs with sign-ins of its own: each space's pages use a WebKit
/// store made for it (WKWebsiteDataStore(forIdentifier:) with the space's
/// id), so a client's Figma and your own can both stay signed in.
public struct Space: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    /// An SF Symbol's name.
    public var symbol: String
    public var tabs: [TabRecord]
    public var selected: UUID?

    public init(id: UUID = UUID(), name: String, symbol: String, tabs: [TabRecord] = [], selected: UUID? = nil) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.tabs = tabs
        self.selected = selected
    }
}

/// A tab that was closed, kept so it can be reopened where it was.
public struct ClosedTab: Codable, Equatable, Sendable {
    public var tab: TabRecord
    public var space: UUID
    public var index: Int
}

/// Every space and its tabs: what the app saves and reads back at launch.
public struct Workspace: Codable, Equatable, Sendable {
    public var spaces: [Space]
    public var closed: [ClosedTab]

    /// Closed tabs remembered, newest last.
    public static let closedKept = 25

    /// The symbols a space can wear, from Apple's SF Symbols.
    public static let symbols = [
        "briefcase", "paintpalette", "building.2", "person.2", "sparkles", "lightbulb",
        "hammer", "book", "house", "heart", "leaf", "star",
    ]

    public init(spaces: [Space], closed: [ClosedTab] = []) {
        self.spaces = spaces
        self.closed = closed
    }

    /// The first launch: one space, on Figma.
    public static func starting(now: Date = Date()) -> Workspace {
        let tab = TabRecord(url: URL(string: "https://www.figma.com/files"), title: "Figma", shown: now)
        return Workspace(spaces: [Space(name: "Work", symbol: "briefcase", tabs: [tab], selected: tab.id)])
    }

    // MARK: Reading

    public func space(_ id: UUID) -> Space? {
        spaces.first { $0.id == id }
    }

    public func spaceID(of tab: UUID) -> UUID? {
        spaces.first { $0.tabs.contains { $0.id == tab } }?.id
    }

    public func tab(_ id: UUID) -> TabRecord? {
        for space in spaces {
            if let tab = space.tabs.first(where: { $0.id == id }) { return tab }
        }
        return nil
    }

    /// The tab `offset` places along from `tab` in its space, going round.
    public func neighbour(of tab: UUID, by offset: Int) -> UUID? {
        guard let space = spaces.first(where: { $0.tabs.contains { $0.id == tab } }),
              let index = space.tabs.firstIndex(where: { $0.id == tab })
        else { return nil }
        let count = space.tabs.count
        return space.tabs[((index + offset) % count + count) % count].id
    }

    /// The space `offset` places along from `space`, going round.
    public func spaceNeighbour(of space: UUID, by offset: Int) -> UUID? {
        guard let index = spaces.firstIndex(where: { $0.id == space }), !spaces.isEmpty else { return nil }
        let count = spaces.count
        return spaces[((index + offset) % count + count) % count].id
    }

    // MARK: Changing

    /// A new tab in `space`, right after `after` when that tab is in the same
    /// space, at the end otherwise; selected. Nil when there is no such space.
    @discardableResult
    public mutating func openTab(_ url: URL?, in space: UUID, after: UUID? = nil, now: Date = Date()) -> UUID? {
        guard let s = spaces.firstIndex(where: { $0.id == space }) else { return nil }
        let tab = TabRecord(url: url, shown: now)
        if let after, let index = spaces[s].tabs.firstIndex(where: { $0.id == after }) {
            spaces[s].tabs.insert(tab, at: index + 1)
        } else {
            spaces[s].tabs.append(tab)
        }
        spaces[s].selected = tab.id
        return tab.id
    }

    public mutating func select(_ tab: UUID, now: Date = Date()) {
        for s in spaces.indices {
            guard let t = spaces[s].tabs.firstIndex(where: { $0.id == tab }) else { continue }
            spaces[s].selected = tab
            spaces[s].tabs[t].shown = now
            return
        }
    }

    /// Takes a tab away and remembers it for `reopen()`. When it was its
    /// space's selected tab, the one to its right is selected instead, or the
    /// one to its left when it was last, as browsers do. Returns the space's
    /// selection afterwards.
    @discardableResult
    public mutating func closeTab(_ id: UUID) -> UUID? {
        for s in spaces.indices {
            guard let index = spaces[s].tabs.firstIndex(where: { $0.id == id }) else { continue }
            let tab = spaces[s].tabs.remove(at: index)
            closed.append(ClosedTab(tab: tab, space: spaces[s].id, index: index))
            if closed.count > Workspace.closedKept { closed.removeFirst(closed.count - Workspace.closedKept) }
            if spaces[s].selected == id {
                let tabs = spaces[s].tabs
                spaces[s].selected = tabs.isEmpty ? nil : tabs[min(index, tabs.count - 1)].id
            }
            return spaces[s].selected
        }
        return nil
    }

    /// The last closed tab back where it was, selected; into the first space
    /// when its own is gone. Returns its id.
    public mutating func reopen(now: Date = Date()) -> UUID? {
        guard var last = closed.popLast() else { return nil }
        let s = spaces.firstIndex(where: { $0.id == last.space }) ?? 0
        guard spaces.indices.contains(s) else { return nil }
        last.tab.shown = now
        spaces[s].tabs.insert(last.tab, at: min(last.index, spaces[s].tabs.count))
        spaces[s].selected = last.tab.id
        return last.tab.id
    }

    /// What a page said about itself: its address and title.
    public mutating func record(_ tab: UUID, url: URL?, title: String?) {
        for s in spaces.indices {
            guard let t = spaces[s].tabs.firstIndex(where: { $0.id == tab }) else { continue }
            if let url { spaces[s].tabs[t].url = url }
            if let title { spaces[s].tabs[t].title = title }
            return
        }
    }

    /// A new space at the end, with one empty tab. Returns its id.
    @discardableResult
    public mutating func addSpace(named name: String, symbol: String? = nil, now: Date = Date()) -> UUID {
        let tab = TabRecord(url: nil, shown: now)
        let used = Set(spaces.map(\.symbol))
        let symbol = symbol ?? Workspace.symbols.first { !used.contains($0) } ?? "square.grid.2x2"
        let space = Space(name: name, symbol: symbol, tabs: [tab], selected: tab.id)
        spaces.append(space)
        return space.id
    }

    /// Takes a space and its tabs away, never the last one. Its closed tabs
    /// are forgotten too: their sign-ins go with the space's store.
    public mutating func removeSpace(_ id: UUID) -> Bool {
        guard spaces.count > 1, let index = spaces.firstIndex(where: { $0.id == id }) else { return false }
        spaces.remove(at: index)
        closed.removeAll { $0.space == id }
        return true
    }

    public mutating func renameSpace(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = spaces.firstIndex(where: { $0.id == id }) else { return }
        spaces[index].name = trimmed
    }

    public mutating func setSymbol(_ id: UUID, to symbol: String) {
        guard let index = spaces.firstIndex(where: { $0.id == id }) else { return }
        spaces[index].symbol = symbol
    }

    /// A tab into another space, at its end and selected there. The page
    /// has to load again in that space's store; the app does that.
    @discardableResult
    public mutating func moveTab(_ id: UUID, to space: UUID) -> Bool {
        guard let from = spaces.firstIndex(where: { $0.tabs.contains { $0.id == id } }),
              let to = spaces.firstIndex(where: { $0.id == space }), from != to,
              let index = spaces[from].tabs.firstIndex(where: { $0.id == id })
        else { return false }
        let tab = spaces[from].tabs.remove(at: index)
        if spaces[from].selected == id {
            let tabs = spaces[from].tabs
            spaces[from].selected = tabs.isEmpty ? nil : tabs[min(index, tabs.count - 1)].id
        }
        spaces[to].tabs.append(tab)
        spaces[to].selected = tab.id
        return true
    }

    /// A tab to another place in its own space's row.
    public mutating func moveTab(_ id: UUID, toIndex target: Int) {
        for s in spaces.indices {
            guard let index = spaces[s].tabs.firstIndex(where: { $0.id == id }) else { continue }
            let tab = spaces[s].tabs.remove(at: index)
            spaces[s].tabs.insert(tab, at: max(0, min(target, spaces[s].tabs.count)))
            return
        }
    }

    /// Puts right what a damaged or hand-edited file got wrong: no spaces, a
    /// selection that isn't one of the space's tabs.
    public mutating func repair(now: Date = Date()) {
        if spaces.isEmpty { self = Workspace.starting(now: now) }
        for s in spaces.indices {
            let ids = Set(spaces[s].tabs.map(\.id))
            if let selected = spaces[s].selected, !ids.contains(selected) { spaces[s].selected = nil }
            if spaces[s].selected == nil { spaces[s].selected = spaces[s].tabs.first?.id }
        }
    }
}

/// The workspace on disk, as JSON.
public enum WorkspaceFile {
    public static func read(_ file: URL) -> Workspace? {
        guard let data = try? Data(contentsOf: file),
              var workspace = try? JSONDecoder().decode(Workspace.self, from: data)
        else { return nil }
        workspace.repair()
        return workspace
    }

    public static func write(_ workspace: Workspace, to file: URL) throws {
        let data = try JSONEncoder().encode(workspace)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file, options: .atomic)
    }
}
