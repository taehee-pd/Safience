import Foundation

// What iCloud holds of the workspace, and how the two turn into each other.
//
// Records live in the user's private CloudKit database, in one zone
// (SyncZone.name): a record per space, per bookmark and folder, per pinned
// tab, and one per device and space for that device's open tabs. The app
// (Sync.swift, through CKSyncEngine) and the browser extension
// (Extension/model.js, through CloudKit Web Services) write the same record
// types and fields; a change to one is a change to both.
//
// Nothing here knows CloudKit: records are plain values (SyncRecord), so the
// rules can be tested, and the app and the extension can each turn them into
// what their side of CloudKit takes.

public enum SyncZone {
    public static let name = "Sync"
}

public enum SyncKind: String, CaseIterable, Codable, Sendable {
    case space = "Space"
    case bookmark = "BookmarkNode"
    case pinned = "PinnedTab"
    case deviceTabs = "DeviceTabs"

    /// Every field a record of this kind has. A save sets each, or clears
    /// it, so a field left out of the record (a folder's address) is none.
    public var fields: [String] {
        switch self {
        case .space: return ["name", "symbol", "color"]
        case .bookmark: return ["space", "parent", "position", "title", "url"]
        case .pinned: return ["space", "position", "title", "url"]
        case .deviceTabs: return ["device", "deviceName", "browser", "space", "updated", "tabs"]
        }
    }
}

/// A field's value as CloudKit keeps it: text, a number, or a time.
public enum SyncField: Equatable, Sendable {
    case string(String)
    case double(Double)
    case date(Date)

    public var string: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var double: Double? {
        if case .double(let value) = self { return value }
        return nil
    }

    public var date: Date? {
        if case .date(let value) = self { return value }
        return nil
    }
}

/// A record, CloudKit aside: its type, its name in the zone, its fields.
/// A field left out is one with no value.
public struct SyncRecord: Equatable, Sendable {
    public var kind: SyncKind
    public var name: String
    public var fields: [String: SyncField]

    public init(kind: SyncKind, name: String, fields: [String: SyncField]) {
        self.kind = kind
        self.name = name
        self.fields = fields
    }
}

// MARK: The records

/// A space's name, icon and colour. Its record name is the space's iCloud
/// id (Space.cloudID), the same on every device.
public struct SyncSpace: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var symbol: String
    public var color: String

    public init(id: String, name: String, symbol: String, color: String) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.color = color
    }

    public var record: SyncRecord {
        SyncRecord(kind: .space, name: id, fields: ["name": .string(name), "symbol": .string(symbol), "color": .string(color)])
    }

    public init?(_ record: SyncRecord) {
        guard record.kind == .space, let name = record.fields["name"]?.string else { return nil }
        self.init(id: record.name, name: name, symbol: record.fields["symbol"]?.string ?? "square.grid.2x2",
                  color: record.fields["color"]?.string ?? SpaceColor.blue.rawValue)
    }
}

/// A bookmark, or a folder of them: which space, which folder, where among
/// its neighbours. Its record name is the bookmark's id.
public struct SyncBookmark: Codable, Equatable, Sendable {
    public var id: String
    public var space: String
    /// The folder it is in; nil at the space's top level.
    public var parent: String?
    /// Neighbours are ordered by position, then by record name.
    public var position: Double
    public var title: String
    /// Nil for a folder.
    public var url: String?

    public init(id: String, space: String, parent: String?, position: Double, title: String, url: String?) {
        self.id = id
        self.space = space
        self.parent = parent
        self.position = position
        self.title = title
        self.url = url
    }

    public var record: SyncRecord {
        var fields: [String: SyncField] = ["space": .string(space), "position": .double(position), "title": .string(title)]
        if let parent { fields["parent"] = .string(parent) }
        if let url { fields["url"] = .string(url) }
        return SyncRecord(kind: .bookmark, name: id, fields: fields)
    }

    public init?(_ record: SyncRecord) {
        guard record.kind == .bookmark, let space = record.fields["space"]?.string else { return nil }
        let parent = record.fields["parent"]?.string
        self.init(id: record.name, space: space, parent: parent?.isEmpty == true ? nil : parent,
                  position: record.fields["position"]?.double ?? 0, title: record.fields["title"]?.string ?? "",
                  url: record.fields["url"]?.string.flatMap { $0.isEmpty ? nil : $0 })
    }
}

/// A pinned tab of a space: the address it was pinned with, and where it is
/// among the space's pinned tabs. Its record name is the tab's iCloud id
/// (TabRecord.cloudID, else its id).
public struct SyncPinned: Codable, Equatable, Sendable {
    public var id: String
    public var space: String
    public var position: Double
    public var title: String
    public var url: String

    public init(id: String, space: String, position: Double, title: String, url: String) {
        self.id = id
        self.space = space
        self.position = position
        self.title = title
        self.url = url
    }

    public var record: SyncRecord {
        SyncRecord(kind: .pinned, name: id, fields: [
            "space": .string(space), "position": .double(position), "title": .string(title), "url": .string(url),
        ])
    }

    public init?(_ record: SyncRecord) {
        guard record.kind == .pinned, let space = record.fields["space"]?.string,
              let url = record.fields["url"]?.string, !url.isEmpty
        else { return nil }
        self.init(id: record.name, space: space, position: record.fields["position"]?.double ?? 0,
                  title: record.fields["title"]?.string ?? "", url: url)
    }
}

/// One open tab of another device, as it shows in a list.
public struct SyncTab: Codable, Equatable, Sendable {
    public var url: String
    public var title: String
    public var pinned: Bool
    /// The tab group it is in, in a desktop browser.
    public var group: String?

    public init(url: String, title: String, pinned: Bool = false, group: String? = nil) {
        self.url = url
        self.title = title
        self.pinned = pinned
        self.group = group
    }

    enum CodingKeys: String, CodingKey {
        case url = "u", title = "t", pinned = "p", group = "g"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        url = try c.decode(String.self, forKey: .url)
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        pinned = (try? c.decodeIfPresent(Bool.self, forKey: .pinned)) ?? false
        group = try? c.decodeIfPresent(String.self, forKey: .group)
    }
}

/// A device's open tabs in one space: Safience on an iPhone, or a desktop
/// browser's profile through the extension. Only that device writes it.
public struct SyncDeviceTabs: Codable, Equatable, Sendable {
    public var id: String
    public var device: String
    /// "iPhone", "Mac", what the person called it.
    public var deviceName: String
    /// "Safience", "Chrome", "Edge"...
    public var browser: String
    public var space: String
    public var updated: Date
    public var tabs: [SyncTab]

    public init(device: String, deviceName: String, browser: String, space: String, updated: Date, tabs: [SyncTab]) {
        id = Self.recordName(device: device, space: space)
        self.device = device
        self.deviceName = deviceName
        self.browser = browser
        self.space = space
        self.updated = updated
        self.tabs = tabs
    }

    public static func recordName(device: String, space: String) -> String {
        "tabs.\(device).\(space)"
    }

    /// Unseen for this long, a device's tabs are out of date and don't show.
    public static let stale: TimeInterval = 14 * 24 * 60 * 60

    public var record: SyncRecord {
        let list = (try? JSONEncoder().encode(tabs)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        return SyncRecord(kind: .deviceTabs, name: id, fields: [
            "device": .string(device), "deviceName": .string(deviceName), "browser": .string(browser),
            "space": .string(space), "updated": .date(updated), "tabs": .string(list),
        ])
    }

    public init?(_ record: SyncRecord) {
        guard record.kind == .deviceTabs, let device = record.fields["device"]?.string,
              let space = record.fields["space"]?.string
        else { return nil }
        let list = record.fields["tabs"]?.string.flatMap { $0.data(using: .utf8) }
            .flatMap { try? JSONDecoder().decode([SyncTab].self, from: $0) } ?? []
        self.init(device: device, deviceName: record.fields["deviceName"]?.string ?? "",
                  browser: record.fields["browser"]?.string ?? "", space: space,
                  updated: record.fields["updated"]?.date ?? .distantPast, tabs: list)
        id = record.name
    }
}

// MARK: The mirror

/// Every synced record as this device knows it: what iCloud holds, plus
/// this device's changes on their way there. The workspace's synced spaces
/// are built from it, and it from them (SyncPlan).
public struct SyncMirror: Codable, Equatable, Sendable {
    public var spaces: [String: SyncSpace] = [:]
    public var bookmarks: [String: SyncBookmark] = [:]
    public var pinned: [String: SyncPinned] = [:]
    public var deviceTabs: [String: SyncDeviceTabs] = [:]

    public init() {}

    public var isEmpty: Bool {
        spaces.isEmpty && bookmarks.isEmpty && pinned.isEmpty && deviceTabs.isEmpty
    }

    /// A record from iCloud in place of what was here; false for one that
    /// can't be read, which is left out.
    @discardableResult
    public mutating func take(_ record: SyncRecord) -> Bool {
        switch record.kind {
        case .space:
            guard let space = SyncSpace(record) else { return false }
            spaces[record.name] = space
        case .bookmark:
            guard let bookmark = SyncBookmark(record) else { return false }
            bookmarks[record.name] = bookmark
        case .pinned:
            guard let pin = SyncPinned(record) else { return false }
            pinned[record.name] = pin
        case .deviceTabs:
            guard let tabs = SyncDeviceTabs(record) else { return false }
            deviceTabs[record.name] = tabs
        }
        return true
    }

    /// A record deleted in iCloud, whatever its kind.
    public mutating func remove(_ name: String) {
        spaces[name] = nil
        bookmarks[name] = nil
        pinned[name] = nil
        deviceTabs[name] = nil
    }

    public func record(named name: String) -> SyncRecord? {
        spaces[name]?.record ?? bookmarks[name]?.record ?? pinned[name]?.record ?? deviceTabs[name]?.record
    }

    /// Everything that belongs to a space: what goes with it when it is removed.
    public func names(in space: String) -> [String] {
        [space] + bookmarks.values.filter { $0.space == space }.map(\.id)
            + pinned.values.filter { $0.space == space }.map(\.id)
            + deviceTabs.values.filter { $0.space == space }.map(\.id)
    }
}

// MARK: The rules

public enum SyncPlan {
    /// Every space gets an iCloud id while sync is on.
    public static func assignIDs(_ workspace: inout Workspace) {
        for s in workspace.spaces.indices where workspace.spaces[s].cloudID == nil {
            workspace.spaces[s].cloudID = UUID()
        }
    }

    // MARK: Workspace to records

    /// What iCloud should hold of the workspace's synced spaces: their
    /// names, bookmarks and pinned tabs. Built on `mirror`, what it holds
    /// now: neighbours keep their positions wherever their order is
    /// unchanged, so moving one bookmark rewrites one record; a bookmark
    /// whose folder hasn't arrived yet stays in that folder. Device tabs
    /// are carried over as they are.
    public static func records(of workspace: Workspace, keeping mirror: SyncMirror) -> SyncMirror {
        var out = SyncMirror()
        out.deviceTabs = mirror.deviceTabs
        for space in workspace.spaces {
            guard let cloud = space.cloudID?.uuidString else { continue }
            out.spaces[cloud] = SyncSpace(id: cloud, name: space.name, symbol: space.symbol, color: space.color.rawValue)
            addBookmarks(space.bookmarks, parent: nil, space: cloud, previous: mirror, into: &out)
            let pins = space.tabs.filter(\.isPinned)
            let names = pins.map(pinName)
            let places = positions(names, previous: mirror.pinned.mapValues(\.position))
            for (index, tab) in pins.enumerated() {
                guard let url = tab.pinned else { continue }
                let name = names[index]
                // The title of the page it was pinned at; another page's
                // title, while it is elsewhere, would rewrite it on every load.
                let title = tab.url == tab.pinned ? tab.title : (mirror.pinned[name]?.title ?? tab.title)
                out.pinned[name] = SyncPinned(id: name, space: cloud, position: places[index], title: title, url: url.absoluteString)
            }
        }
        return out
    }

    private static func addBookmarks(_ list: [Bookmark], parent: String?, space: String, previous: SyncMirror,
                                     into out: inout SyncMirror) {
        let names = list.map(\.id.uuidString)
        let places = positions(names, previous: previous.bookmarks.mapValues(\.position))
        for (index, item) in list.enumerated() {
            let name = names[index]
            var folder = parent
            var position = places[index]
            // At the top only because its folder hasn't arrived: still in it.
            if parent == nil, let known = previous.bookmarks[name], let waiting = known.parent,
               previous.bookmarks[waiting] == nil {
                folder = waiting
                position = known.position
            }
            out.bookmarks[name] = SyncBookmark(id: name, space: space, parent: folder, position: position,
                                               title: item.title, url: item.url?.absoluteString)
            if let children = item.children {
                addBookmarks(children, parent: name, space: space, previous: previous, into: &out)
            }
        }
    }

    static func pinName(_ tab: TabRecord) -> String {
        (tab.cloudID ?? tab.id).uuidString
    }

    /// Positions for `names` in this order: those already in increasing
    /// order (the longest such run) keep theirs, the rest go between their
    /// neighbours. When a gap has run out of room, all are numbered again.
    public static func positions(_ names: [String], previous: [String: Double]) -> [Double] {
        let known = names.map { previous[$0] }
        let keep = increasingRun(known)
        var out = [Double](repeating: 0, count: names.count)
        var index = 0
        while index < names.count {
            if keep.contains(index), let value = known[index] {
                out[index] = value
                index += 1
                continue
            }
            // A run of new places, between the kept ones around it.
            let start = index
            while index < names.count && !keep.contains(index) { index += 1 }
            let below = start > 0 ? out[start - 1] : nil
            let above = index < names.count ? known[index] : nil
            let count = index - start
            for k in 0..<count {
                switch (below, above) {
                case let (low?, high?): out[start + k] = low + (high - low) * Double(k + 1) / Double(count + 1)
                case let (low?, nil): out[start + k] = low + Double(k + 1)
                case let (nil, high?): out[start + k] = high - Double(count - k)
                case (nil, nil): out[start + k] = Double(k + 1)
                }
            }
        }
        // Halved too often to tell apart: start again from 1, 2, 3.
        for i in 1..<max(out.count, 1) where !(out[i] > out[i - 1]) || out[i] - out[i - 1] < 1e-9 {
            return names.indices.map { Double($0 + 1) }
        }
        return out
    }

    /// The indices of the longest run of known values that increases.
    private static func increasingRun(_ values: [Double?]) -> Set<Int> {
        var tails: [Int] = []
        var before = [Int](repeating: -1, count: values.count)
        for (index, value) in values.enumerated() {
            guard let value else { continue }
            var low = 0, high = tails.count
            while low < high {
                let mid = (low + high) / 2
                if let tail = values[tails[mid]], tail < value { low = mid + 1 } else { high = mid }
            }
            if low > 0 { before[index] = tails[low - 1] }
            if low == tails.count { tails.append(index) } else { tails[low] = index }
        }
        var run = Set<Int>()
        var at = tails.last ?? -1
        while at >= 0 {
            run.insert(at)
            at = before[at]
        }
        return run
    }

    /// The records to save and to delete for `old` to become `new`, device
    /// tabs aside: they are each device's own (deviceChanges).
    public static func changes(from old: SyncMirror, to new: SyncMirror) -> (save: [String], delete: [String]) {
        var save: [String] = []
        var delete: [String] = []
        for (name, value) in new.spaces where old.spaces[name] != value { save.append(name) }
        for (name, value) in new.bookmarks where old.bookmarks[name] != value { save.append(name) }
        for (name, value) in new.pinned where old.pinned[name] != value { save.append(name) }
        for name in old.spaces.keys where new.spaces[name] == nil { delete.append(name) }
        for name in old.bookmarks.keys where new.bookmarks[name] == nil { delete.append(name) }
        for name in old.pinned.keys where new.pinned[name] == nil { delete.append(name) }
        return (save.sorted(), delete.sorted())
    }

    // MARK: Records to workspace

    /// The space's bookmarks as the mirror has them: each folder's children
    /// in order. A bookmark whose folder hasn't arrived shows at the top
    /// until it does; two folders each in the other (two devices moving
    /// them at once) are broken at the top too.
    public static func tree(of space: String, in mirror: SyncMirror) -> [Bookmark] {
        let nodes = mirror.bookmarks.values.filter { $0.space == space }
        let names = Set(nodes.map(\.id))
        var children: [String?: [SyncBookmark]] = [:]
        for node in nodes {
            let parent = node.parent.flatMap { names.contains($0) && $0 != node.id ? $0 : nil }
            children[parent, default: []].append(node)
        }
        var placed = Set<String>()
        func build(_ parent: String?) -> [Bookmark] {
            let list = (children[parent] ?? []).sorted { ($0.position, $0.id) < ($1.position, $1.id) }
            return list.compactMap { node in
                guard placed.insert(node.id).inserted, let id = UUID(uuidString: node.id) else { return nil }
                if let address = node.url {
                    guard let url = URL(string: address) else { return nil }
                    return Bookmark(id: id, title: node.title, url: url)
                }
                return Bookmark(id: id, folder: node.title, children: build(node.id))
            }
        }
        var top = build(nil)
        // What a loop of folders kept from the top.
        for node in nodes where !placed.contains(node.id) {
            guard let id = UUID(uuidString: node.id) else { continue }
            placed.insert(node.id)
            if let address = node.url, let url = URL(string: address) {
                top.append(Bookmark(id: id, title: node.title, url: url))
            } else if node.url == nil {
                top.append(Bookmark(id: id, folder: node.title, children: build(node.id)))
            }
        }
        return top
    }

    /// What changing the workspace to match the mirror took away: spaces
    /// removed elsewhere, and pinned tabs, which the app closes (they are
    /// unpinned here, so closing removes them).
    public struct Applied: Equatable, Sendable {
        public var removedSpaces: [UUID] = []
        public var removedTabs: [UUID] = []
    }

    /// The workspace's synced spaces as the mirror has them: names, icons,
    /// colours, bookmarks and pinned tabs. Spaces new to this device come in
    /// with one empty tab; `deleted` are spaces removed elsewhere, for the
    /// app to remove with their sign-ins.
    @discardableResult
    public static func apply(_ mirror: SyncMirror, to workspace: inout Workspace, deleted: Set<String> = [],
                             now: Date = Date()) -> Applied {
        var applied = Applied()
        for s in workspace.spaces.indices {
            guard let cloud = workspace.spaces[s].cloudID?.uuidString else { continue }
            if deleted.contains(cloud) {
                applied.removedSpaces.append(workspace.spaces[s].id)
                continue
            }
            guard let record = mirror.spaces[cloud] else { continue }
            workspace.spaces[s].name = record.name
            workspace.spaces[s].symbol = record.symbol
            workspace.spaces[s].color = SpaceColor(rawValue: record.color) ?? workspace.spaces[s].color
            workspace.spaces[s].bookmarks = tree(of: cloud, in: mirror)
            applied.removedTabs += applyPinned(mirror, to: &workspace.spaces[s], cloud: cloud, now: now)
        }
        let known = Set(workspace.spaces.compactMap { $0.cloudID?.uuidString })
        for record in mirror.spaces.values.sorted(by: { $0.name < $1.name }) where !known.contains(record.id) && !deleted.contains(record.id) {
            guard let cloud = UUID(uuidString: record.id) else { continue }
            let tab = TabRecord(url: nil, shown: now)
            var space = Space(name: record.name, symbol: record.symbol, color: SpaceColor(rawValue: record.color),
                              tabs: [tab], selected: tab.id, bookmarks: tree(of: record.id, in: mirror))
            space.cloudID = cloud
            _ = applyPinned(mirror, to: &space, cloud: record.id, now: now)
            workspace.spaces.append(space)
        }
        return applied
    }

    /// The space's pinned tabs in the mirror's order: kept, added, or
    /// unpinned to be closed. A live tab keeps its page; only the address it
    /// goes back to changes.
    private static func applyPinned(_ mirror: SyncMirror, to space: inout Space, cloud: String, now: Date) -> [UUID] {
        let wanted = mirror.pinned.values.filter { $0.space == cloud }.sorted { ($0.position, $0.id) < ($1.position, $1.id) }
        var pins: [String: TabRecord] = [:]
        for tab in space.tabs where tab.isPinned { pins[pinName(tab)] = tab }
        var pinnedTabs: [TabRecord] = []
        for record in wanted {
            guard let url = URL(string: record.url) else { continue }
            if var tab = pins.removeValue(forKey: record.id) {
                tab.pinned = url
                pinnedTabs.append(tab)
            } else {
                var tab = TabRecord(url: url, title: record.title, shown: .distantPast, pinned: url)
                tab.cloudID = UUID(uuidString: record.id)
                pinnedTabs.append(tab)
            }
        }
        // Pinned elsewhere no longer: unpinned here, for the app to close.
        var gone: [TabRecord] = []
        for var tab in pins.values {
            tab.pinned = nil
            tab.cloudID = nil
            gone.append(tab)
        }
        let others = space.tabs.filter { !$0.isPinned }
        space.tabs = pinnedTabs + gone + others
        if space.selected == nil || !space.tabs.contains(where: { $0.id == space.selected }) {
            space.selected = space.tabs.first?.id
        }
        return gone.map(\.id)
    }

    // MARK: Turning sync on

    /// Joins this device's spaces to what iCloud holds: a space joins the
    /// one with its iCloud id, or else the one with its name, or comes in as
    /// new; both sets of bookmarks are kept, and pinned tabs at the same
    /// address are one. iCloud's spaces this device hasn't got come in too.
    /// Returns what iCloud should then hold; nothing of iCloud's is deleted.
    public static func join(_ workspace: inout Workspace, remote: SyncMirror, now: Date = Date()) -> SyncMirror {
        var taken = Set<String>()
        for s in workspace.spaces.indices {
            var cloud = workspace.spaces[s].cloudID?.uuidString
            if let id = cloud, remote.spaces[id] == nil || taken.contains(id) { cloud = nil }
            if cloud == nil {
                let name = key(workspace.spaces[s].name)
                cloud = remote.spaces.values.sorted { $0.id < $1.id }
                    .first { key($0.name) == name && !taken.contains($0.id) }?.id
            }
            guard let match = cloud, let there = remote.spaces[match], let id = UUID(uuidString: match) else {
                // New to iCloud: its own id, unless it has none or another space took it.
                if workspace.spaces[s].cloudID.map({ taken.contains($0.uuidString) }) ?? true {
                    workspace.spaces[s].cloudID = UUID()
                }
                if let id = workspace.spaces[s].cloudID?.uuidString { taken.insert(id) }
                continue
            }
            taken.insert(match)
            workspace.spaces[s].cloudID = id
            workspace.spaces[s].name = there.name
            workspace.spaces[s].symbol = there.symbol
            workspace.spaces[s].color = SpaceColor(rawValue: there.color) ?? workspace.spaces[s].color
            var bookmarks = tree(of: match, in: remote)
            _ = Bookmarks.merge(workspace.spaces[s].bookmarks, into: &bookmarks)
            workspace.spaces[s].bookmarks = bookmarks
            // A pinned tab here at an address pinned there is that one.
            let theirs = remote.pinned.values.filter { $0.space == match }
            for t in workspace.spaces[s].tabs.indices where workspace.spaces[s].tabs[t].isPinned {
                let address = workspace.spaces[s].tabs[t].pinned.map(Bookmarks.key)
                if let same = theirs.first(where: { URL(string: $0.url).map(Bookmarks.key) == address }) {
                    workspace.spaces[s].tabs[t].cloudID = UUID(uuidString: same.id)
                }
            }
            // Theirs come in as pinned tabs; ours that they haven't got stay.
            _ = applyPinnedKeepingOurs(remote, to: &workspace.spaces[s], cloud: match, now: now)
        }
        // iCloud's spaces this device hasn't got.
        var incoming = remote
        incoming.spaces = remote.spaces.filter { !taken.contains($0.key) }
        apply(incoming, to: &workspace, now: now)
        return records(of: workspace, keeping: remote)
    }

    /// Pinned tabs on joining: iCloud's, then this device's own that iCloud hasn't got.
    private static func applyPinnedKeepingOurs(_ mirror: SyncMirror, to space: inout Space, cloud: String, now: Date) -> [UUID] {
        let ours = space.tabs.filter { $0.isPinned && mirror.pinned[pinName($0)] == nil }
        var merged = mirror
        let last = mirror.pinned.values.filter { $0.space == cloud }.map(\.position).max() ?? 0
        for (index, tab) in ours.enumerated() {
            guard let url = tab.pinned else { continue }
            merged.pinned[pinName(tab)] = SyncPinned(id: pinName(tab), space: cloud, position: last + Double(index + 1),
                                                     title: tab.title, url: url.absoluteString)
        }
        return applyPinned(merged, to: &space, cloud: cloud, now: now)
    }

    private static func key(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    // MARK: This device's open tabs

    /// What other devices may show of this one's open tabs, one record per
    /// synced space: web addresses only, never a sign-in page or an address
    /// that carries a credential.
    public static func deviceTabs(of workspace: Workspace, device: String, deviceName: String, now: Date) -> [SyncDeviceTabs] {
        workspace.spaces.compactMap { space in
            guard let cloud = space.cloudID?.uuidString else { return nil }
            let tabs = space.tabs.compactMap { tab -> SyncTab? in
                guard let url = tab.url, isShareable(url) else { return nil }
                return SyncTab(url: url.absoluteString, title: tab.title, pinned: tab.isPinned)
            }
            return SyncDeviceTabs(device: device, deviceName: deviceName, browser: "Safience", space: cloud,
                                  updated: now, tabs: tabs)
        }
    }

    /// Query names that make an address a credential: whoever opens it is
    /// signed in, or finishes someone's sign-in.
    static let secretNames: Set<String> = [
        "code", "token", "access_token", "id_token", "refresh_token", "session", "sessionid", "sid",
        "sig", "signature", "auth", "authuser_token", "password", "otp", "key", "api_key", "apikey",
    ]

    /// A web address that is fine for another device to see.
    public static func isShareable(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), url.user == nil,
              url.password == nil, !SignIn.isSignInPage(url)
        else { return false }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let fragment = URLComponents(string: "x:?" + (url.fragment ?? ""))?.queryItems ?? []
        return !(items + fragment).contains { secretNames.contains($0.name.lowercased()) }
    }

    // MARK: From the key-value store, once

    /// The spaces the key-value store kept before sync moved to CloudKit,
    /// as records: on the first sync after the update, they join like any
    /// other device's.
    public static func mirror(fromLegacy spaces: [CloudSpace]) -> SyncMirror {
        var mirror = SyncMirror()
        for space in spaces where !space.deleted {
            let cloud = space.id.uuidString
            mirror.spaces[cloud] = SyncSpace(id: cloud, name: space.name, symbol: space.symbol, color: space.color.rawValue)
            var workspace = Workspace(spaces: [Space(name: space.name, symbol: space.symbol, bookmarks: space.bookmarks)])
            workspace.spaces[0].cloudID = space.id
            mirror.bookmarks.merge(records(of: workspace, keeping: SyncMirror()).bookmarks) { _, new in new }
        }
        return mirror
    }
}
