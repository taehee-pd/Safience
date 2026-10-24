import Foundation
import PadCore
import os

extension Sync {
    /// The mirror, each record's CloudKit version, the engine's own state,
    /// and this device's id, in Application Support.
    struct Stored: Codable {
        var mirror = SyncMirror()
        var systemFields: [String: Data] = [:]
        var state: Data?
        var device = UUID().uuidString
        /// The account whose mirror, pending records and engine state are stored here.
        var account: String?
        /// This device's spaces have joined iCloud's.
        var joined = false
        /// The Mac's extensions as it last sent them (SyncPlan.publish);
        /// nil before the first time.
        var extensions: [SyncPlan.LocalExtension]?
        /// Spaces removed, whose extensions' uses go when they come.
        var removedSpaces: [String]?
        /// The record types it was fetched with (Sync.schema); nil before 2.
        var schema: Int?
        /// The clock this device stamps its edits with (SyncClock); kept
        /// across an account change, so it never goes back.
        var clock: SyncClock?
        /// Tombstones whose deletion from iCloud is on its way (collectTombstones).
        var collecting: Set<String>?
        /// The latest time iCloud has given its records: tombstones expire by it.
        var serverTime: Date?
        /// iCloud's time when it last saved a record of this device's, and
        /// this device's then (serverNow).
        var lastSave: Date?
        var lastSaveNoted: Date?
        /// A server-confirmed fetch completed with no pending writes for this account.
        var lastSuccessfulSync: Date?
        /// Spaces deleted from iCloud for good: what they held goes after
        /// them (SyncPlan.expired).
        var goneSpaces: Set<String>?
        /// This device's edits proper not in iCloud yet, by the stamp each
        /// set the deleted register with (commit): what an outright deletion
        /// mustn't take (SyncPlan.survivors, unknownItem).
        var editsUnsent: [String: SyncStamp]?
        /// Extension switches waiting for their space (waitingSwitches).
        var waitingOn: [SyncPlan.ExtensionInSpace]?
        var waitingOff: [SyncPlan.ExtensionInSpace]?
        /// Records to save and to delete, stamped while there was no engine
        /// to take them (queue): handed to it when there is (begin).
        var waitingSaves: Set<String>?
        var waitingDeletes: Set<String>?
        /// When iCloud saved each tombstone it holds (noteSaved).
        var tombstonesSaved: [String: Date]?

        init(device: String = UUID().uuidString, clock: SyncClock? = nil, account: String? = nil) {
            self.device = device
            self.clock = clock
            self.account = account
        }

        @MainActor static var file: URL {
            Session.folder.appendingPathComponent("sync.json")
        }

        /// Nothing when sync.json is missing or unreadable: this device then
        /// joins again and fetches everything from iCloud, which is slower but
        /// loses nothing iCloud has.
        @MainActor static func read() -> Stored? {
            let data: Data
            do {
                data = try Data(contentsOf: file)
            } catch CocoaError.fileReadNoSuchFile {
                return nil
            } catch {
                Sync.log.error("sync.json not read: \(error.localizedDescription, privacy: .public)")
                return nil
            }
            do {
                return try JSONDecoder().decode(Stored.self, from: data)
            } catch {
                Sync.log.error("sync.json not decoded: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
    }
}
