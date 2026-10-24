import Foundation
import Testing
@testable import PadCore

struct WorkspacePersistenceTests {
    @Test func failedWriteRetainsTheLastFileAndDirtyRevisionUntilRetry() async throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("workspace.json")
        let original = Workspace.starting()
        try WorkspaceFile.write(original, to: file)
        let fault = WriteFault(code: NSFileWriteOutOfSpaceError)
        let writer = WorkspaceWriter(file: file) { try fault.write($0, $1) }
        var edited = original
        edited.renameSpace(edited.firstSpace.id, to: "Changed")
        var state = WorkspaceSaveState()
        let revision = state.changed()

        state.acknowledge(await save(writer, edited, revision: revision))
        #expect(state.isDirty)
        #expect(state.failure == .outOfSpace)
        #expect(WorkspaceFile.load(file) == .loaded(original))

        state.acknowledge(await save(writer, edited, revision: revision))
        #expect(!state.isDirty)
        #expect(state.failure == nil)
        #expect(WorkspaceFile.load(file) == .loaded(edited))
        #expect(WorkspaceFile.load(WorkspaceFile.backup(for: file)) == .loaded(original))
    }

    @Test func terminationFlushFollowsQueuedWritesAndStaleSnapshotsCannotReplaceIt() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("workspace.json")
        let writer = WorkspaceWriter(file: file)
        var older = Workspace.starting()
        older.renameSpace(older.firstSpace.id, to: "Older")
        var latest = older
        latest.renameSpace(latest.firstSpace.id, to: "Latest")

        writer.save(older, revision: 1) { _ in }
        let receipt = writer.saveNow(latest, revision: 2)
        #expect(receipt.failure == nil)
        #expect(receipt.revision == 2)
        #expect(WorkspaceFile.load(file) == .loaded(latest))

        let stale = writer.saveNow(older, revision: 1)
        #expect(stale.failure == nil)
        #expect(stale.revision == 2)
        #expect(WorkspaceFile.load(file) == .loaded(latest))
    }

    @Test func acknowledgementsNeverClearNewerEditsOrResurrectOlderErrors() {
        var state = WorkspaceSaveState()
        state.changed()
        state.changed()
        state.acknowledge(.init(revision: 1, failure: .permissionDenied))
        state.acknowledge(.init(revision: 1, failure: nil))
        #expect(state.savedRevision == 1)
        #expect(state.isDirty)
        #expect(state.failure == .permissionDenied)

        state.acknowledge(.init(revision: 2, failure: nil))
        state.acknowledge(.init(revision: 1, failure: .outOfSpace))
        #expect(state.savedRevision == 2)
        #expect(!state.isDirty)
        #expect(state.failure == nil)

        state.changed()
        state.acknowledge(.init(revision: 2, failure: nil))
        #expect(state.isDirty)
        #expect(state.savedRevision == 2)
    }

    @Test func invalidSourceIsPreservedAndReportedAsUnavailable() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("workspace.json")
        let corrupt = Data("broken saved workspace".utf8)
        try corrupt.write(to: file)
        let writer = WorkspaceWriter(file: file)
        let receipt = writer.saveNow(.starting(), revision: 1)
        #expect(receipt.failure == .sourceUnavailable)
        #expect(try Data(contentsOf: file) == corrupt)
    }

    @Test(arguments: [NSFileWriteNoPermissionError, NSFileReadNoPermissionError])
    func permissionErrorsHaveAnActionableOutcome(code: Int) async {
        let fault = WriteFault(code: code)
        let writer = WorkspaceWriter(file: temporaryFolder().appendingPathComponent("workspace.json")) { try fault.write($0, $1) }
        let receipt = await save(writer, .starting(), revision: 1)
        #expect(receipt.failure == .permissionDenied)
    }

    @Test func exportedBackupCanBeLoadedWithoutTouchingTheSavedFile() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let original = Workspace.starting()
        let saved = folder.appendingPathComponent("workspace.json")
        try WorkspaceFile.write(original, to: saved)
        let before = try Data(contentsOf: saved)
        var edited = original
        edited.renameSpace(edited.firstSpace.id, to: "Unsaved Changes")
        let backup = folder.appendingPathComponent("export.json")
        try WorkspaceFile.exportData(edited).write(to: backup)
        #expect(WorkspaceFile.load(backup) == .loaded(edited))
        #expect(try Data(contentsOf: saved) == before)
    }

    private func temporaryFolder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Safience-Persistence-\(UUID().uuidString)", isDirectory: true)
    }

    private func save(_ writer: WorkspaceWriter, _ workspace: Workspace, revision: UInt64) async -> WorkspaceSaveReceipt {
        await withCheckedContinuation { continuation in
            writer.save(workspace, revision: revision) { continuation.resume(returning: $0) }
        }
    }
}

private final class WriteFault: @unchecked Sendable {
    private let lock = NSLock()
    private var fails = true
    private let code: Int

    init(code: Int) { self.code = code }

    func write(_ workspace: Workspace, _ file: URL) throws {
        let fail = lock.withLock {
            let value = fails
            fails = false
            return value
        }
        if fail { throw NSError(domain: NSCocoaErrorDomain, code: code) }
        try WorkspaceFile.write(workspace, to: file)
    }
}
