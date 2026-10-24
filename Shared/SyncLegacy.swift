import Foundation
import PadCore

extension Sync {
    /// What the key-value store kept before sync moved to CloudKit: read
    /// once, when this device first joins, and never written again.
    static func legacySpaces() -> [CloudSpace] {
        let store = NSUbiquitousKeyValueStore.default
        store.synchronize()
        return store.dictionaryRepresentation.keys.filter { $0.hasPrefix("space.") }.sorted().compactMap { key in
            store.data(forKey: key).flatMap(Deflate.inflate).flatMap { try? JSONDecoder().decode(CloudSpace.self, from: $0) }
        }
    }
}

extension SyncMirror {
    /// The key-value store's spaces that CloudKit hasn't got yet.
    func adding(legacy spaces: [CloudSpace]) -> SyncMirror {
        let old = SyncPlan.mirror(fromLegacy: spaces)
        var out = self
        for (id, space) in old.spaces where out.spaces[id] == nil && !out.removedSpaces.contains(id) {
            out.spaces[id] = space
            for bookmark in old.bookmarks.values where bookmark.space == id { out.bookmarks[bookmark.id] = bookmark }
        }
        return out
    }
}
