import Foundation

// History in the user's own iCloud, when Settings › iCloud › Sync history is on
// (Preferences.historySync): a zone of its own beside the spaces' (SyncZone),
// in the same CloudKit private database. What its records are called and
// hold lives here; the app sends and takes them (HistoryCloud.swift).
//
// Each device writes its own visits only, a record for each space and day,
// in pieces small enough for CloudKit (HistoryCloudRecord.day). Taking a
// record never removes anything: a device lets go of its own old days, and
// another device keeps the visits it took. Only a clearing (HistoryRemoval)
// removes visits elsewhere, and it is kept, so that a day record from a
// device that was offline can't bring cleared visits back.

public enum HistoryCloudZone {
    public static let name = "History"
}

/// A record of the History zone, by its name.
public enum HistoryCloudRecord: Equatable, Hashable, Sendable {
    /// A device's visits in one space (its iCloud id, Space.cloudID) on one
    /// day (HistoryCloudDay), the `chunk`th piece of them.
    case day(device: String, space: UUID, day: String, chunk: Int)
    /// A clearing, by its id.
    case removal(UUID)

    public static let dayType = "HistoryDay"
    public static let removalType = "HistoryRemoval"

    public var name: String {
        switch self {
        case let .day(device, space, day, chunk): return "\(Self.dayType).\(device).\(space.uuidString).\(day).\(chunk)"
        case .removal(let id): return "\(Self.removalType).\(id.uuidString)"
        }
    }

    public var type: String {
        switch self {
        case .day: return Self.dayType
        case .removal: return Self.removalType
        }
    }

    public init?(name: String) {
        let parts = name.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        switch parts.first {
        case Self.dayType:
            guard parts.count == 5, !parts[1].isEmpty, let space = UUID(uuidString: parts[2]), HistoryCloudDay.range(of: parts[3]) != nil,
                  let chunk = Int(parts[4]), chunk >= 0 else { return nil }
            self = .day(device: parts[1], space: space, day: parts[3], chunk: chunk)
        case Self.removalType:
            guard parts.count == 2, let id = UUID(uuidString: parts[1]) else { return nil }
            self = .removal(id)
        default:
            return nil
        }
    }
}

/// New account epochs write distinct day records, preserving older records
/// rather than replacing their contents with a newly eligible subset.
public enum HistoryUploadIdentity {
    public static func writer(device: String, epoch: UUID) -> String { "\(device)-\(epoch.uuidString)" }

    public static func orphanedRecords(_ mine: Set<String>, activeSpaces: Set<UUID>, currentWriter: String) -> Set<String> {
        Set(mine.filter { name in
            if case let .day(writer, space, _, _) = HistoryCloudRecord(name: name) {
                return writer == currentWriter && !activeSpaces.contains(space)
            }
            return false
        })
    }

    public static func recordsForRemovedSpace(_ mine: Set<String>, cloud: UUID, device: String) -> Set<String> {
        Set(mine.filter { name in
            if case let .day(writer, space, _, _) = HistoryCloudRecord(name: name) {
                return space == cloud && owns(writer: writer, device: device)
            }
            return false
        })
    }

    public static func owns(writer: String, device: String) -> Bool {
        if writer == device { return true }
        let prefix = device + "-"
        return writer.hasPrefix(prefix) && UUID(uuidString: String(writer.dropFirst(prefix.count))) != nil
    }
}

/// A space (this device's id for it) and a day (HistoryCloudDay): what a
/// device's History record is of.
public struct HistoryDayOfSpace: Hashable, Codable, Sendable {
    public var space: UUID
    public var day: String

    public init(space: UUID, day: String) {
        self.space = space
        self.day = day
    }
}

/// A day as the History zone counts them: in UTC, so every device and time
/// zone agrees which record a visit is in ("20261021").
public enum HistoryCloudDay {
    /// How long a day record is kept in iCloud, by any device, whoever wrote it.
    public static let kept: TimeInterval = 400 * 86_400

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    public static func key(for date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d%02d%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Existing own records expire by retention, independent of when a new
    /// account upload epoch began. A new boundary must not erase older days.
    public static func expiredRecords(_ mine: Set<String>, retentionCutoff: Date?, now: Date = Date()) -> Set<String> {
        let last = key(for: max(retentionCutoff ?? .distantPast, now.addingTimeInterval(-kept)))
        return Set(mine.filter { name in
            if case .day(_, _, let day, _) = HistoryCloudRecord(name: name) { return day < last }
            return false
        })
    }

    /// The day's first moment and its last.
    public static func range(of key: String) -> (from: Date, to: Date)? {
        guard key.count == 8, key.allSatisfy(\.isNumber), let number = Int(key) else { return nil }
        let parts = DateComponents(year: number / 10_000, month: number / 100 % 100, day: number % 100)
        guard parts.isValidDate(in: calendar), let start = calendar.date(from: parts),
              let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
        return (start, end.addingTimeInterval(-0.001))
    }

    /// Whether the day is older than any record of it is kept.
    public static func isExpired(_ key: String, now: Date) -> Bool {
        guard let range = range(of: key) else { return true }
        return range.to < now.addingTimeInterval(-kept)
    }
}

/// What a History record holds, as JSON (the app compresses it and keeps it
/// in the record's encrypted values): visits, or a clearing, with the space
/// as iCloud knows it (Space.cloudID), not as this device does.
public enum HistoryCloudPayload {
    /// The most a record's visits come to before compression: CloudKit takes
    /// a record of a megabyte at most, and the plan keeps each under half.
    public static let chunkLimit = 400_000

    public static func encode(_ visits: [HistoryVisit]) -> Data {
        (try? JSONEncoder().encode(visits)) ?? Data()
    }

    public static func visits(from data: Data) -> [HistoryVisit]? {
        try? JSONDecoder().decode([HistoryVisit].self, from: data)
    }

    public static func encode(_ removal: HistoryRemoval) -> Data {
        (try? JSONEncoder().encode(removal)) ?? Data()
    }

    public static func removal(from data: Data) -> HistoryRemoval? {
        try? JSONDecoder().decode(HistoryRemoval.self, from: data)
    }

    /// A day's visits in the pieces its records hold, oldest first: each
    /// piece `limit` bytes of JSON at most, but for a single visit that is
    /// more by itself. Adding visits later in the day changes only the last
    /// piece, which is the one sent again.
    public static func chunks(_ visits: [HistoryVisit], limit: Int = chunkLimit) -> [[HistoryVisit]] {
        var chunks: [[HistoryVisit]] = []
        var current: [HistoryVisit] = []
        var size = 2
        for visit in visits.sorted(by: { ($0.time, $0.id.uuidString) < ($1.time, $1.id.uuidString) }) {
            let length = ((try? JSONEncoder().encode(visit))?.count ?? 0) + 1
            if !current.isEmpty, size + length > limit {
                chunks.append(current)
                current = []
                size = 2
            }
            current.append(visit)
            size += length
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }
}


/// History metadata is usable only after it has been read and normalized for
/// the currently approved account. A later storage retry must repeat this step.
public struct HistoryAccountSession: Equatable, Sendable {
    public enum LoadDecision: Equatable, Sendable {
        case unavailable
        case retain
        case reset(uploadAfter: Date)
    }

    private var validatedAccount: String?
    private var validatedEpoch: UUID?

    public init() {}

    public mutating func loaded(verified: String?, stored: String?, available: Bool,
                                verifiedEpoch: UUID? = nil, storedEpoch: UUID? = nil,
                                now: Date = Date()) -> LoadDecision {
        revoke()
        guard let verified, available else { return .unavailable }
        if (stored != nil && stored != verified) || verifiedEpoch != storedEpoch {
            return .reset(uploadAfter: now)
        }
        return .retain
    }

    /// Normalized account, epoch and cutoff must be acknowledged on disk first.
    @discardableResult
    public mutating func confirm(verified: String?, stored: String?, persisted: Bool,
                                 verifiedEpoch: UUID? = nil, storedEpoch: UUID? = nil) -> Bool {
        guard persisted, let verified, verified == stored, verifiedEpoch == storedEpoch else { revoke(); return false }
        validatedAccount = verified
        validatedEpoch = verifiedEpoch
        return true
    }

    public func allows(verified: String?, stored: String?, verifiedEpoch: UUID? = nil, storedEpoch: UUID? = nil) -> Bool {
        guard let verified else { return false }
        return validatedAccount == verified && stored == verified
            && validatedEpoch == verifiedEpoch && storedEpoch == verifiedEpoch
    }

    /// Captured when a local visit is created, never inferred when a queued
    /// write is retried or a later account starts backfilling local history.
    public func uploadEpoch(verified: String?, stored: String?, verifiedEpoch: UUID?, storedEpoch: UUID?) -> UUID? {
        allows(verified: verified, stored: stored, verifiedEpoch: verifiedEpoch, storedEpoch: storedEpoch) ? verifiedEpoch : nil
    }

    public mutating func revoke() { validatedAccount = nil; validatedEpoch = nil }
}
