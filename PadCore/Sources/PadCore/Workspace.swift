import Foundation

/// One tab as it is kept between launches: where it was and what it was
/// called. The page itself lives in the app (Pages.swift), live or frozen.
public struct TabRecord: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var url: URL?
    public var title: String
    /// When it was last on screen: the freezer keeps the most recent ones.
    public var shown: Date
    /// For a pinned tab, the address it was pinned with, which closing it
    /// takes it back to; nil for every other tab.
    public var pinned: URL?
    /// For a pinned tab that came from iCloud or joined one there, the id
    /// the other devices know it by; nil otherwise, when its own id is
    /// that id (SyncPlan).
    public var cloudID: UUID?

    public init(id: UUID = UUID(), url: URL?, title: String = "", shown: Date = .distantPast, pinned: URL? = nil) {
        self.id = id
        self.url = url
        self.title = title
        self.shown = shown
        self.pinned = pinned
    }

    public var isPinned: Bool {
        pinned != nil
    }

    /// The name a row shows: the page's title, else its address, else
    /// "New Tab" for a tab that has gone nowhere yet.
    public var label: String {
        let named = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !named.isEmpty { return named }
        return url.map(Address.pretty) ?? "New Tab"
    }
}

/// The colour a space wears: its button is filled with it, so a window
/// says which space it is in at a glance (Design.swift has the shades).
public enum SpaceColor: String, Codable, CaseIterable, Sendable {
    case blue, purple, pink, red, orange, yellow, green, teal, indigo, gray

    /// The colour a space gets when none was chosen: one for each of the
    /// symbols spaces are given in turn, so spaces made one after another
    /// differ in colour as they do in symbol.
    public static func standard(for symbol: String) -> SpaceColor {
        let index = Workspace.symbols.firstIndex(of: symbol) ?? 0
        return allCases[index % allCases.count]
    }
}

/// Two tabs side by side in one window, as in Dia: `left` on the left.
/// The space's selected tab is the pane with the keys; the other stays on
/// screen beside it. A split's tabs sit next to each other in the row, left
/// first, so the row shows them as one tab (Workspace keeps them so).
public struct Split: Codable, Equatable, Sendable {
    public var left: UUID
    public var right: UUID
    /// The left pane's share of the window's width.
    public var ratio: Double

    /// As far as the divider goes either way: each pane keeps a quarter.
    public static let ratios: ClosedRange<Double> = 0.25...0.75

    public init(left: UUID, right: UUID, ratio: Double = 0.5) {
        self.left = left
        self.right = right
        self.ratio = min(max(ratio, Split.ratios.lowerBound), Split.ratios.upperBound)
    }

    public func contains(_ tab: UUID) -> Bool {
        left == tab || right == tab
    }

    /// The other pane's tab, or nil for a tab not in this split.
    public func partner(of tab: UUID) -> UUID? {
        tab == left ? right : tab == right ? left : nil
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
    public var color: SpaceColor
    /// Pinned tabs first, then the others (Workspace keeps them so).
    public var tabs: [TabRecord]
    public var selected: UUID?
    /// This space's own bookmarks, for the grid a new tab shows.
    public var bookmarks: [Bookmark]
    /// Tabs shown two at a time; a tab is in one split at most, and never a
    /// pinned one.
    public var splits: [Split]
    /// The id iCloud knows this space by, the same on every device; nil for
    /// a space that has never been synced (CloudSync.swift). Not `id`: that
    /// one names this device's sign-ins for the space.
    public var cloudID: UUID?

    public init(id: UUID = UUID(), name: String, symbol: String, color: SpaceColor? = nil, tabs: [TabRecord] = [],
                selected: UUID? = nil, bookmarks: [Bookmark] = [], splits: [Split] = []) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.color = color ?? SpaceColor.standard(for: symbol)
        self.tabs = tabs
        self.selected = selected
        self.bookmarks = bookmarks
        self.splits = splits
    }

    enum CodingKeys: String, CodingKey {
        case id, name, symbol, color, tabs, selected, bookmarks, splits, cloudID
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        symbol = try c.decode(String.self, forKey: .symbol)
        tabs = try c.decode([TabRecord].self, forKey: .tabs)
        selected = try c.decodeIfPresent(UUID.self, forKey: .selected)
        // Spaces got colours and bookmarks later: a file from before has
        // neither, and must still read.
        color = (try? c.decodeIfPresent(SpaceColor.self, forKey: .color)) ?? SpaceColor.standard(for: symbol)
        bookmarks = (try? c.decodeIfPresent([Bookmark].self, forKey: .bookmarks)) ?? []
        splits = (try? c.decodeIfPresent([Split].self, forKey: .splits)) ?? []
        cloudID = try? c.decodeIfPresent(UUID.self, forKey: .cloudID)
    }

    /// The split `tab` is in, if any.
    public func split(containing tab: UUID) -> Split? {
        splits.first { $0.contains(tab) }
    }

    /// How many tabs at the front of the row are pinned.
    public var pinnedCount: Int {
        tabs.prefix { $0.isPinned }.count
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

    /// The symbols a space can wear, from Apple's SF Symbols. New ones go at
    /// the end: a space's standard colour follows its symbol's place here.
    public static let symbols = [
        "briefcase", "paintpalette", "building.2", "person.2", "sparkles", "lightbulb",
        "hammer", "book", "house", "heart", "leaf", "star",
        "folder", "doc.text", "pencil.and.ruler", "paintbrush", "camera", "film",
        "music.note", "gamecontroller", "cart", "creditcard", "chart.bar", "globe",
        "airplane", "graduationcap", "flame", "bolt", "cloud", "moon",
        "sun.max", "flag", "tag", "bell", "gift", "cup.and.saucer",
        "laptopcomputer", "wrench.and.screwdriver", "cube", "puzzlepiece", "mountain.2", "pawprint",
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

    /// The split `tab` is in, in whichever space.
    public func split(containing tab: UUID) -> Split? {
        for space in spaces {
            if let split = space.split(containing: tab) { return split }
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
            // Opened from a pinned tab: first of the others, never among the pinned.
            spaces[s].tabs.insert(tab, at: max(index + 1, spaces[s].pinnedCount))
        } else {
            spaces[s].tabs.append(tab)
        }
        spaces[s].selected = tab.id
        tidySplits(s)
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
    ///
    /// A pinned tab stays: it goes back to the address it was pinned with,
    /// and only its page goes, which the app unloads, as Dia and Arc do.
    @discardableResult
    public mutating func closeTab(_ id: UUID) -> UUID? {
        for s in spaces.indices {
            guard let index = spaces[s].tabs.firstIndex(where: { $0.id == id }) else { continue }
            // Its split ends; the pane beside it is the one left on screen.
            let partner = spaces[s].split(containing: id)?.partner(of: id)
            spaces[s].splits.removeAll { $0.contains(id) }
            if let pinned = spaces[s].tabs[index].pinned {
                spaces[s].tabs[index].url = pinned
                spaces[s].tabs[index].title = ""
                let tabs = spaces[s].tabs
                if spaces[s].selected == id, tabs.count > 1 {
                    spaces[s].selected = tabs[index + 1 < tabs.count ? index + 1 : index - 1].id
                }
                return spaces[s].selected
            }
            let tab = spaces[s].tabs.remove(at: index)
            closed.append(ClosedTab(tab: tab, space: spaces[s].id, index: index))
            if closed.count > Workspace.closedKept { closed.removeFirst(closed.count - Workspace.closedKept) }
            if spaces[s].selected == id {
                let tabs = spaces[s].tabs
                spaces[s].selected = partner ?? (tabs.isEmpty ? nil : tabs[min(index, tabs.count - 1)].id)
            }
            return spaces[s].selected
        }
        return nil
    }

    /// How a space's tabs can be put in order, as Safari's Arrange Tabs By.
    public enum Arrangement: Sendable {
        case title
        case website
    }

    /// The space's tabs in order of their names or their sites. The pinned
    /// ones stay first as they were, and a split's two tabs stay together,
    /// in order of the left one. Tabs that tie keep their order.
    public mutating func arrangeTabs(in space: UUID, by arrangement: Arrangement) {
        guard let s = spaces.firstIndex(where: { $0.id == space }) else { return }
        let pinned = spaces[s].tabs.filter(\.isPinned)
        let ordinary = spaces[s].tabs.filter { !$0.isPinned }
        var units: [[TabRecord]] = []
        var index = 0
        while index < ordinary.count {
            let tab = ordinary[index]
            if index + 1 < ordinary.count,
               spaces[s].splits.contains(where: { $0.left == tab.id && $0.right == ordinary[index + 1].id }) {
                units.append([tab, ordinary[index + 1]])
                index += 2
            } else {
                units.append([tab])
                index += 1
            }
        }
        func key(_ tab: TabRecord) -> String {
            switch arrangement {
            case .title:
                return tab.label
            case .website:
                let host = tab.url?.host()?.lowercased() ?? ""
                let site = Destination.registrable(host.hasPrefix("www.") ? String(host.dropFirst(4)) : host)
                // A tab gone nowhere yet goes last.
                return site.isEmpty ? "\u{10FFFF}" : site + " " + tab.label
            }
        }
        let sorted = units.enumerated().sorted { a, b in
            switch key(a.element[0]).localizedStandardCompare(key(b.element[0])) {
            case .orderedAscending: return true
            case .orderedDescending: return false
            case .orderedSame: return a.offset < b.offset
            }
        }
        spaces[s].tabs = pinned + sorted.flatMap(\.element)
    }

    /// The last closed tab back where it was, selected; into the first space
    /// when its own is gone. Returns its id.
    public mutating func reopen(now: Date = Date()) -> UUID? {
        guard var last = closed.popLast() else { return nil }
        let s = spaces.firstIndex(where: { $0.id == last.space }) ?? 0
        guard spaces.indices.contains(s) else { return nil }
        last.tab.shown = now
        last.tab.pinned = nil
        let place = max(min(last.index, spaces[s].tabs.count), spaces[s].pinnedCount)
        spaces[s].tabs.insert(last.tab, at: place)
        spaces[s].selected = last.tab.id
        tidySplits(s)
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
        let colors = Set(spaces.map(\.color))
        let color = SpaceColor.allCases.first { !colors.contains($0) } ?? SpaceColor.standard(for: symbol)
        let space = Space(name: name, symbol: symbol, color: color, tabs: [tab], selected: tab.id)
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

    public mutating func setColor(_ id: UUID, to color: SpaceColor) {
        guard let index = spaces.firstIndex(where: { $0.id == id }) else { return }
        spaces[index].color = color
    }

    /// Spaces to another place in the order they are listed and stepped
    /// through, as a list's drag gives it: the spaces at `offsets` go before
    /// the one at `destination`, as they were before the move.
    public mutating func moveSpaces(from offsets: IndexSet, to destination: Int) {
        let moving = offsets.filter(spaces.indices.contains).map { spaces[$0] }
        guard !moving.isEmpty else { return }
        let before = offsets.filter { $0 < destination }.count
        var rest = spaces.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        rest.insert(contentsOf: moving, at: max(0, min(destination - before, rest.count)))
        spaces = rest
    }

    /// A tab into another space, at its end and selected there. The page
    /// has to load again in that space's store; the app does that.
    @discardableResult
    public mutating func moveTab(_ id: UUID, to space: UUID) -> Bool {
        guard let from = spaces.firstIndex(where: { $0.tabs.contains { $0.id == id } }),
              let to = spaces.firstIndex(where: { $0.id == space }), from != to,
              let index = spaces[from].tabs.firstIndex(where: { $0.id == id })
        else { return false }
        spaces[from].splits.removeAll { $0.contains(id) }
        let tab = spaces[from].tabs.remove(at: index)
        if spaces[from].selected == id {
            let tabs = spaces[from].tabs
            spaces[from].selected = tabs.isEmpty ? nil : tabs[min(index, tabs.count - 1)].id
        }
        // A pinned tab stays pinned in its new space.
        if tab.isPinned {
            spaces[to].tabs.insert(tab, at: spaces[to].pinnedCount)
        } else {
            spaces[to].tabs.append(tab)
        }
        spaces[to].selected = tab.id
        return true
    }

    /// A tab to another place in its own space's row: among the pinned tabs
    /// when it is one, among the others when not. A split's two tabs go
    /// together.
    public mutating func moveTab(_ id: UUID, toIndex target: Int) {
        for s in spaces.indices {
            guard spaces[s].tabs.contains(where: { $0.id == id }) else { continue }
            let moving = spaces[s].split(containing: id).map { [$0.left, $0.right] } ?? [id]
            let tabs = moving.compactMap { m in spaces[s].tabs.first { $0.id == m } }
            spaces[s].tabs.removeAll { moving.contains($0.id) }
            let isPinned = tabs.first?.isPinned == true
            let pinned = spaces[s].pinnedCount
            let lowest = isPinned ? 0 : pinned
            let highest = isPinned ? pinned : spaces[s].tabs.count
            spaces[s].tabs.insert(contentsOf: tabs, at: max(lowest, min(target, highest)))
            tidySplits(s)
            return
        }
    }

    // MARK: Pinned tabs

    /// Pins a tab at the address it is on: it goes to the end of the pinned
    /// tabs at the front of its row, and from now on closing it takes it
    /// back there instead of away. A tab that has been nowhere yet has no
    /// address to pin.
    @discardableResult
    public mutating func pin(_ id: UUID) -> Bool {
        for s in spaces.indices {
            guard let index = spaces[s].tabs.firstIndex(where: { $0.id == id }) else { continue }
            guard !spaces[s].tabs[index].isPinned, let url = spaces[s].tabs[index].url else { return false }
            spaces[s].splits.removeAll { $0.contains(id) }
            var tab = spaces[s].tabs.remove(at: index)
            tab.pinned = url
            spaces[s].tabs.insert(tab, at: spaces[s].pinnedCount)
            return true
        }
        return false
    }

    /// A pinned tab back to being an ordinary one, first after the pinned.
    @discardableResult
    public mutating func unpin(_ id: UUID) -> Bool {
        for s in spaces.indices {
            guard let index = spaces[s].tabs.firstIndex(where: { $0.id == id }) else { continue }
            guard spaces[s].tabs[index].isPinned else { return false }
            var tab = spaces[s].tabs.remove(at: index)
            tab.pinned = nil
            spaces[s].tabs.insert(tab, at: spaces[s].pinnedCount)
            return true
        }
        return false
    }

    /// A pinned tab's page at the address it was pinned with; returns it.
    public mutating func backToPinned(_ id: UUID) -> URL? {
        for s in spaces.indices {
            guard let index = spaces[s].tabs.firstIndex(where: { $0.id == id }) else { continue }
            guard let pinned = spaces[s].tabs[index].pinned else { return nil }
            spaces[s].tabs[index].url = pinned
            return pinned
        }
        return nil
    }

    // MARK: Splits

    /// Shows `other` beside `tab`, on its right, as one tab of the row: the
    /// two must be ordinary tabs of one space. A split either was in ends.
    @discardableResult
    public mutating func split(_ tab: UUID, with other: UUID) -> Bool {
        guard tab != other, let s = spaces.firstIndex(where: { $0.tabs.contains { $0.id == tab } }),
              let left = spaces[s].tabs.first(where: { $0.id == tab }), !left.isPinned,
              let right = spaces[s].tabs.first(where: { $0.id == other }), !right.isPinned
        else { return false }
        spaces[s].splits.removeAll { $0.contains(tab) || $0.contains(other) }
        spaces[s].splits.append(Split(left: tab, right: other))
        tidySplits(s)
        return true
    }

    /// A new tab beside `tab`, on its right, selected so it is the one typed
    /// into. Returns its id; nil for a pinned tab or none.
    @discardableResult
    public mutating func splitWithNewTab(_ tab: UUID, url: URL? = nil, now: Date = Date()) -> UUID? {
        guard let space = spaceID(of: tab), self.tab(tab)?.isPinned == false,
              let new = openTab(url, in: space, after: tab, now: now), split(tab, with: new)
        else { return nil }
        select(new, now: now)
        return new
    }

    /// The split `tab` is in ends; both tabs stay where they are.
    public mutating func separate(_ tab: UUID) {
        for s in spaces.indices { spaces[s].splits.removeAll { $0.contains(tab) } }
    }

    /// The two panes change sides.
    public mutating func swapSides(_ tab: UUID) {
        for s in spaces.indices {
            guard let i = spaces[s].splits.firstIndex(where: { $0.contains(tab) }) else { continue }
            let split = spaces[s].splits[i]
            spaces[s].splits[i] = Split(left: split.right, right: split.left, ratio: 1 - split.ratio)
            tidySplits(s)
            return
        }
    }

    /// Where the divider of `tab`'s split is: the left pane's share.
    public mutating func setSplitRatio(_ tab: UUID, to ratio: Double) {
        for s in spaces.indices {
            guard let i = spaces[s].splits.firstIndex(where: { $0.contains(tab) }) else { continue }
            let split = spaces[s].splits[i]
            spaces[s].splits[i] = Split(left: split.left, right: split.right, ratio: ratio)
            return
        }
    }

    /// Keeps a space's splits as they must be: two ordinary tabs of its own
    /// each, no tab in two, and each split's tabs side by side in the row,
    /// left first, so the row shows them as one.
    mutating func tidySplits(_ s: Int) {
        let ordinary = Set(spaces[s].tabs.filter { !$0.isPinned }.map(\.id))
        var seen: Set<UUID> = []
        spaces[s].splits = spaces[s].splits.filter { split in
            guard split.left != split.right, ordinary.contains(split.left), ordinary.contains(split.right),
                  !seen.contains(split.left), !seen.contains(split.right)
            else { return false }
            seen.formUnion([split.left, split.right])
            return true
        }
        for split in spaces[s].splits {
            guard let r = spaces[s].tabs.firstIndex(where: { $0.id == split.right }) else { continue }
            let right = spaces[s].tabs.remove(at: r)
            let l = spaces[s].tabs.firstIndex { $0.id == split.left }
            spaces[s].tabs.insert(right, at: l.map { $0 + 1 } ?? r)
        }
    }

    // MARK: Bookmarks, each space its own

    /// This space's bookmark for `url`, at any depth.
    public func bookmark(for url: URL, in space: UUID) -> Bookmark? {
        self.space(space).flatMap { Bookmarks.find(url, in: $0.bookmarks) }
    }

    /// A bookmark at the end of the space's top level, unless the space has
    /// one for the address already. Returns the bookmark's id.
    @discardableResult
    public mutating func addBookmark(_ url: URL, title: String, in space: UUID) -> UUID? {
        guard let s = spaces.firstIndex(where: { $0.id == space }) else { return nil }
        if let known = Bookmarks.find(url, in: spaces[s].bookmarks) { return known.id }
        let bookmark = Bookmark(title: title, url: url)
        spaces[s].bookmarks.append(bookmark)
        return bookmark.id
    }

    public mutating func removeBookmark(_ id: UUID, in space: UUID) {
        guard let s = spaces.firstIndex(where: { $0.id == space }) else { return }
        Bookmarks.remove(id, from: &spaces[s].bookmarks)
    }

    /// A new folder at the end of `parent` (nil: the top level), named as
    /// given, or "New Folder". Returns its id; nil when the space or the
    /// parent is not there.
    @discardableResult
    public mutating func addFolder(named name: String, in parent: UUID?, of space: UUID) -> UUID? {
        guard let s = spaces.firstIndex(where: { $0.id == space }) else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let folder = Bookmark(folder: trimmed.isEmpty ? "New Folder" : trimmed, children: [])
        return Bookmarks.insert(folder, into: parent, of: &spaces[s].bookmarks) ? folder.id : nil
    }

    /// A bookmark's or a folder's name; an empty name leaves it as it was.
    public mutating func renameBookmark(_ id: UUID, to name: String, in space: UUID) {
        guard let s = spaces.firstIndex(where: { $0.id == space }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Bookmarks.update(id, in: &spaces[s].bookmarks) { $0.title = trimmed }
    }

    /// Moves a bookmark or a folder to the end of `folder` (nil: the top
    /// level). A folder never goes into itself or into one of its own.
    public mutating func moveBookmark(_ id: UUID, into folder: UUID?, in space: UUID) {
        guard let s = spaces.firstIndex(where: { $0.id == space }),
              let item = Bookmarks.find(id, in: spaces[s].bookmarks) else { return }
        if let folder {
            guard folder != id, Bookmarks.find(folder, in: item.children ?? []) == nil,
                  Bookmarks.find(folder, in: spaces[s].bookmarks)?.isFolder == true else { return }
        }
        var items = spaces[s].bookmarks
        Bookmarks.remove(id, from: &items)
        guard Bookmarks.insert(item, into: folder, of: &items) else { return }
        spaces[s].bookmarks = items
    }

    /// An import's bookmarks into the space, merged with what it has.
    /// Returns how many links it added.
    @discardableResult
    public mutating func importBookmarks(_ items: [Bookmark], into space: UUID) -> Int {
        guard let s = spaces.firstIndex(where: { $0.id == space }) else { return 0 }
        return Bookmarks.merge(items, into: &spaces[s].bookmarks)
    }

    /// Puts right what a damaged or hand-edited file got wrong: no spaces, a
    /// selection that isn't one of the space's tabs.
    public mutating func repair(now: Date = Date()) {
        if spaces.isEmpty { self = Workspace.starting(now: now) }
        for s in spaces.indices {
            // Pinned tabs at the front, the others after, each in its order.
            spaces[s].tabs = spaces[s].tabs.filter(\.isPinned) + spaces[s].tabs.filter { !$0.isPinned }
            let ids = Set(spaces[s].tabs.map(\.id))
            if let selected = spaces[s].selected, !ids.contains(selected) { spaces[s].selected = nil }
            if spaces[s].selected == nil { spaces[s].selected = spaces[s].tabs.first?.id }
            tidySplits(s)
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
