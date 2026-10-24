import Foundation
import Testing
@testable import PadCore

struct DownloadActivityStorageTests {
    private func folder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("download-storage-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
    private func record(_ name: String) -> DownloadRecord {
        DownloadRecord(name: name, source: URL(string: "https://example.com/file"), space: UUID())
    }
    @Test func confirmedMissingIndexCanBeCreated() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        var storage = DownloadActivityStorage(file: folder.appendingPathComponent("activity.json"))
        guard case .missing = storage.load() else { Issue.record("Expected confirmed absence"); return }
        let item = record("new")
        try storage.save([item])
        guard case .loaded(let loaded) = storage.load() else { Issue.record("Saved activity was not recovered"); return }
        #expect(loaded.map(\.id) == [item.id])
    }
    @Test func corruptActivityCannotBeReplacedByANewDownloadAndFilesRemainIntact() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let index = folder.appendingPathComponent("activity.json")
        let file = folder.appendingPathComponent("retained.zip")
        let original = Data("damaged activity bytes".utf8)
        try original.write(to: index)
        try Data("retained download".utf8).write(to: file)
        var storage = DownloadActivityStorage(file: index)
        guard case .unavailable(.decode) = storage.load() else { Issue.record("Expected a decode failure"); return }
        #expect(!storage.canWrite)
        #expect(throws: DownloadActivityStorage.Failure.unavailable) { try storage.save([record("new")]) }
        #expect(try Data(contentsOf: index) == original)
        #expect(try Data(contentsOf: file) == Data("retained download".utf8))
    }
    @Test func deniedReadKeepsSourceBytesAndRetryMergesRecoveredAndCurrentActivity() throws {
        let folder = try folder()
        let index = folder.appendingPathComponent("activity.json")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: index.path)
            try? FileManager.default.removeItem(at: folder)
        }
        let old = record("retained")
        let bytes = try JSONEncoder().encode([old])
        try bytes.write(to: index)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: index.path)
        var storage = DownloadActivityStorage(file: index)
        guard case .unavailable(.read) = storage.load() else { Issue.record("Denied access was treated as an empty list"); return }
        let current = record("current")
        #expect(throws: DownloadActivityStorage.Failure.unavailable) { try storage.save([current]) }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: index.path)
        #expect(try Data(contentsOf: index) == bytes)
        guard case .loaded(let recovered) = storage.load() else { Issue.record("Retry did not restore access"); return }
        let merged = DownloadActivityStorage.merge(recovered: recovered, current: [current])
        try storage.save(merged)
        guard case .loaded(let durable) = storage.load() else { Issue.record("Merged list was not saved"); return }
        #expect(Set(durable.map(\.id)) == [old.id, current.id])
    }
    @Test func recoveredInterruptedActivityCannotReplaceALiveDownloadWithTheSameID() {
        var current = record("current")
        current.fraction = 0.7
        var saved = current
        saved.name = "old"; saved.fraction = 0.1
        let recovered = saved.recovered { _ in false }
        let merged = DownloadActivityStorage.merge(recovered: [recovered], current: [current])
        #expect(merged.count == 1)
        #expect(merged.first?.phase == .downloading)
        #expect(merged.first?.fraction == 0.7)
        #expect(merged.first?.name == "current")
    }
    @Test func retryDoesNotResurrectActivityExplicitlyClearedWhileStorageWasUnavailable() {
        let cleared = record("cleared")
        let retained = record("retained")
        let current = record("current")
        let merged = DownloadActivityStorage.merge(recovered: [cleared, retained], current: [current], excluding: [cleared.id])
        #expect(Set(merged.map(\.id)) == [retained.id, current.id])
    }
    @Test func duplicateIDsAreUnavailableInsteadOfSilentlyDroppingOneSavedRecord() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let index = folder.appendingPathComponent("activity.json")
        let item = record("one")
        let bytes = try JSONEncoder().encode([item, item])
        try bytes.write(to: index)
        var storage = DownloadActivityStorage(file: index)
        guard case .unavailable(.decode) = storage.load() else { Issue.record("Duplicate IDs would lose activity during merge"); return }
        #expect(throws: DownloadActivityStorage.Failure.unavailable) { try storage.save([]) }
        #expect(try Data(contentsOf: index) == bytes)
    }
}
