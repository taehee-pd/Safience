import Foundation

/// A space as iCloud's key-value store kept it, before sync moved to
/// CloudKit (SyncModel.swift): its name, colour, icon and bookmarks, under
/// an id of its own that every device shares; a removed one kept as
/// `deleted`. Read once, on the first sync after the update
/// (SyncPlan.mirror(fromLegacy:)), and never written again.
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
}
