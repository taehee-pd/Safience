import Foundation

/// An unreadable activity index must never be replaced by an empty or partial list.
public struct DownloadActivityStorage: Sendable {
    public enum Failure: Error, Equatable, Sendable { case read, decode, unavailable }
    public enum Load: Sendable { case missing, loaded([DownloadRecord]), unavailable(Failure) }
    private let file: URL
    public private(set) var canWrite = false
    public init(file: URL) { self.file = file }

    public mutating func load() -> Load {
        canWrite = false
        let data: Data
        do { data = try Data(contentsOf: file) }
        catch {
            let error = error as NSError
            if error.domain == NSCocoaErrorDomain,
               error.code == NSFileNoSuchFileError || error.code == NSFileReadNoSuchFileError {
                canWrite = true
                return .missing
            }
            return .unavailable(.read)
        }
        do {
            let records = try JSONDecoder().decode([DownloadRecord].self, from: data)
            guard Set(records.map(\.id)).count == records.count else { return .unavailable(.decode) }
            canWrite = true
            return .loaded(records)
        } catch { return .unavailable(.decode) }
    }

    public func save(_ records: [DownloadRecord]) throws {
        guard canWrite else { throw Failure.unavailable }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(records).write(to: file, options: .atomic)
    }

    /// Current activity wins by ID: a recovered interrupted record cannot replace a running download.
    public static func merge(recovered: [DownloadRecord], current: [DownloadRecord], excluding removed: Set<UUID> = []) -> [DownloadRecord] {
        var records: [UUID: DownloadRecord] = [:]
        for item in recovered where !removed.contains(item.id) { records[item.id] = item }
        for item in current where !removed.contains(item.id) { records[item.id] = item }
        return records.values.sorted { $0.created == $1.created ? $0.id.uuidString < $1.id.uuidString : $0.created > $1.created }
    }
}
