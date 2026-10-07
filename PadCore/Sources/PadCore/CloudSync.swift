import Foundation

/// A space as iCloud keeps it: its name, colour, icon and bookmarks, under an
/// id of its own that every device shares. Its tabs and its sign-ins stay on
/// each device; a space removed on one device is kept as `deleted`, so the
/// others remove it too.
public struct CloudSpace: Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var symbol: String
    public var color: SpaceColor
    public var bookmarks: [Bookmark]
    public var deleted: Bool

    public init(id: UUID, name: String, symbol: String, color: SpaceColor, bookmarks: [Bookmark], deleted: Bool = false) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.color = color
        self.bookmarks = bookmarks
        self.deleted = deleted
    }

    public static func tombstone(_ id: UUID) -> CloudSpace {
        CloudSpace(id: id, name: "", symbol: "", color: .gray, bookmarks: [], deleted: true)
    }
}

extension Space {
    /// What iCloud keeps of this space; nil for a space that isn't synced.
    public var cloud: CloudSpace? {
        cloudID.map { CloudSpace(id: $0, name: name, symbol: symbol, color: color, bookmarks: bookmarks) }
    }
}

/// Spaces and their bookmarks between this device and iCloud.
///
/// iCloud keeps one value per space and settles two devices writing at once
/// by keeping the last; what it holds is what every device shows. A device
/// writes its change at once, and takes up whatever comes in.
public enum CloudSync {
    /// Turning sync on: each space joins the iCloud space it was synced with,
    /// or the one with its name, or comes in as new; their bookmarks are put
    /// together, so turning sync on loses none. iCloud spaces this device
    /// hasn't got come in too. Returns what to write back.
    @discardableResult
    public static func join(_ workspace: inout Workspace, remote: [CloudSpace], now: Date = Date()) -> [CloudSpace] {
        let live = remote.filter { !$0.deleted }
        let gone = Set(remote.filter(\.deleted).map(\.id))
        var taken = Set(workspace.spaces.compactMap(\.cloudID)).subtracting(gone)
        for s in workspace.spaces.indices {
            if let id = workspace.spaces[s].cloudID, gone.contains(id) { workspace.spaces[s].cloudID = nil }
            if workspace.spaces[s].cloudID == nil {
                let name = key(workspace.spaces[s].name)
                if let match = live.first(where: { key($0.name) == name && !taken.contains($0.id) }) {
                    workspace.spaces[s].cloudID = match.id
                } else {
                    workspace.spaces[s].cloudID = UUID()
                }
                if let id = workspace.spaces[s].cloudID { taken.insert(id) }
            }
            guard let id = workspace.spaces[s].cloudID, let there = live.first(where: { $0.id == id }) else { continue }
            // iCloud's name, colour and icon; both sets of bookmarks.
            var bookmarks = there.bookmarks
            _ = Bookmarks.merge(workspace.spaces[s].bookmarks, into: &bookmarks)
            workspace.spaces[s].name = there.name
            workspace.spaces[s].symbol = there.symbol
            workspace.spaces[s].color = there.color
            workspace.spaces[s].bookmarks = bookmarks
        }
        _ = apply(live.filter { !taken.contains($0.id) }, to: &workspace, now: now)
        return workspace.spaces.compactMap(\.cloud).filter { mine in !remote.contains(mine) }
    }

    /// What came in from iCloud: each space takes iCloud's name, colour,
    /// icon and bookmarks, and a space new to this device comes in with one
    /// empty tab. Returns the spaces removed on another device, for the app
    /// to remove with their sign-ins (Session.removeSpace).
    @discardableResult
    public static func apply(_ remote: [CloudSpace], to workspace: inout Workspace, now: Date = Date()) -> [UUID] {
        var removed: [UUID] = []
        for there in remote {
            if let s = workspace.spaces.firstIndex(where: { $0.cloudID == there.id }) {
                if there.deleted {
                    removed.append(workspace.spaces[s].id)
                    continue
                }
                workspace.spaces[s].name = there.name
                workspace.spaces[s].symbol = there.symbol
                workspace.spaces[s].color = there.color
                workspace.spaces[s].bookmarks = there.bookmarks
            } else if !there.deleted {
                let tab = TabRecord(url: nil, shown: now)
                var space = Space(name: there.name, symbol: there.symbol, color: there.color, tabs: [tab],
                                  selected: tab.id, bookmarks: there.bookmarks)
                space.cloudID = there.id
                workspace.spaces.append(space)
            }
        }
        return removed
    }

    /// A space made while sync is on gets its iCloud id.
    public static func assignIDs(_ workspace: inout Workspace) {
        for s in workspace.spaces.indices where workspace.spaces[s].cloudID == nil {
            workspace.spaces[s].cloudID = UUID()
        }
    }

    /// What to write after a change on this device: the synced spaces that
    /// changed or are new, and a tombstone for each that was removed.
    public static func changes(from old: Workspace, to new: Workspace) -> [CloudSpace] {
        let before = Dictionary(old.spaces.compactMap(\.cloud).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let after = new.spaces.compactMap(\.cloud)
        let ids = Set(after.map(\.id))
        return after.filter { before[$0.id] != $0 } + before.keys.filter { !ids.contains($0) }.sorted { $0.uuidString < $1.uuidString }.map(CloudSpace.tombstone)
    }

    private static func key(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
