#if canImport(SQLite3)
import Foundation
import SQLite3
import Testing
@testable import PadCore

@MainActor
struct HistoryFaultTests {
    private func fixture() throws -> (URL, HistoryStore, OpaquePointer) {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("history-fault-\(UUID().uuidString).sqlite")
        let store = try HistoryStore(url: file)
        var connection: OpaquePointer?
        guard sqlite3_open(file.path, &connection) == SQLITE_OK, let connection else { throw HistoryStoreError.sqlite("fixture open") }
        return (file, store, connection)
    }
    private func sql(_ text: String, in connection: OpaquePointer) throws {
        guard sqlite3_exec(connection, text, nil, nil, nil) == SQLITE_OK else {
            throw HistoryStoreError.sqlite(String(cString: sqlite3_errmsg(connection)))
        }
    }
    private func visit(space: UUID) -> HistoryVisit {
        HistoryVisit(space: space, url: URL(string: "https://example.com/retained")!, title: "Retained", time: Date(), device: "fixture", kind: .link)
    }

    @Test func failedOpenLeavesExistingBytesIntact() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("history-unavailable-\(UUID().uuidString).sqlite")
        let bytes = Data("synthetic damaged database".utf8)
        try bytes.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(throws: (any Error).self) { try HistoryStore(url: file) }
        #expect(try Data(contentsOf: file) == bytes)
    }

    @Test func aReadFailureThrowsInsteadOfReturningAnEmptyHistory() async throws {
        let (file, store, connection) = try fixture()
        defer { sqlite3_close(connection); try? FileManager.default.removeItem(at: file) }
        let space = UUID()
        try await store.record(visit(space: space))
        try sql("ALTER TABLE visits RENAME TO retained_visits", in: connection)
        do {
            _ = try await store.entries(space: space)
            Issue.record("A missing table was presented as a successful query")
        } catch {}
        try sql("ALTER TABLE retained_visits RENAME TO visits", in: connection)
        let kept = try await store.entries(space: space)
        #expect(kept.count == 1)
    }

    @Test func failedClearRollsBackVisitsTombstonesAndRevisionBeforeRetry() async throws {
        let (file, store, connection) = try fixture()
        defer { sqlite3_close(connection); try? FileManager.default.removeItem(at: file) }
        let space = UUID()
        try await store.record(visit(space: space))
        let before = await store.revision
        try sql("CREATE TRIGGER deny_delete BEFORE DELETE ON visits BEGIN SELECT RAISE(ABORT, 'synthetic write failure'); END", in: connection)
        let removal = HistoryRemoval(space: space, scope: .all, made: Date().addingTimeInterval(1))
        do {
            try await store.remove(removal, syncAccount: "account-A")
            Issue.record("A failed delete was acknowledged")
        } catch {}
        let kept = try await store.entries(space: space)
        #expect(kept.count == 1)
        #expect(await store.allRemovals().isEmpty)
        #expect(await store.revision == before)
        #expect(try await store.pendingClearings(for: "account-A").isEmpty)
        try sql("DROP TRIGGER deny_delete", in: connection)
        try await store.remove(removal, syncAccount: "account-A")
        #expect(try await store.entries(space: space).isEmpty)
        #expect(await store.allRemovals().map(\.id) == [removal.id])
        #expect(await store.revision == before + 1)
        #expect(try await store.pendingClearings(for: "account-A").map(\.id) == [removal.id])
        #expect(try await store.pendingClearings(for: "account-B").isEmpty)
        try await store.clearingSynced(removal.id)
        #expect(try await store.pendingClearings(for: "account-A").isEmpty)
    }

    @Test func droppedIntentsLeaveTheClearingButSendNothingForAnyAccount() async throws {
        let (file, store, connection) = try fixture()
        defer { sqlite3_close(connection); try? FileManager.default.removeItem(at: file) }
        let space = UUID()
        try await store.record(visit(space: space))
        let first = HistoryRemoval(space: space, scope: .all, made: Date().addingTimeInterval(1))
        try await store.remove(first, syncAccount: "account-A")
        let other = HistoryRemoval(space: UUID(), scope: .all, made: Date().addingTimeInterval(2))
        try await store.remove(other, syncAccount: "account-B")
        // A store that can't let them go keeps them, for the switch-off to ask again.
        try sql("CREATE TRIGGER deny_drop BEFORE DELETE ON sync_state BEGIN SELECT RAISE(ABORT, 'synthetic write failure'); END", in: connection)
        do {
            try await store.dropPendingClearings()
            Issue.record("A failed drop was acknowledged")
        } catch {}
        #expect(try await store.pendingClearings(for: "account-A").map(\.id) == [first.id])
        try sql("DROP TRIGGER deny_drop", in: connection)
        try await store.dropPendingClearings()
        #expect(try await store.pendingClearings(for: "account-A").isEmpty)
        #expect(try await store.pendingClearings(for: "account-B").isEmpty)
        // The clearings still hold on this device; only their trip to iCloud is let go.
        #expect(Set(await store.allRemovals().map(\.id)) == [first.id, other.id])
        #expect(try await store.entries(space: space).isEmpty)
    }

    @Test func aLaterLocalClearDoesNotLoseAnEarlierAccountBoundIntent() async throws {
        let (file, store, connection) = try fixture()
        defer { sqlite3_close(connection); try? FileManager.default.removeItem(at: file) }
        let space = UUID()
        try await store.record(visit(space: space))
        let first = HistoryRemoval(space: space, scope: .all, made: Date().addingTimeInterval(1))
        try await store.remove(first, syncAccount: "account-A")
        let local = HistoryRemoval(space: space, scope: .all, made: Date().addingTimeInterval(2))
        try await store.remove(local)
        #expect(try await store.pendingClearings(for: "account-A").map(\.id) == [first.id])
        #expect(try await store.pendingClearings(for: "account-B").isEmpty)
    }

    @Test func failedAccountNormalizationAndReturnToOldAccountCannotUploadInterveningVisits() async throws {
        struct Metadata: Codable {
            let account: String
            let epoch: UUID
            let uploadAfter: Date
        }
        let (file, store, connection) = try fixture()
        let consentFile = file.appendingPathExtension("consent")
        defer {
            sqlite3_close(connection)
            try? FileManager.default.removeItem(at: file)
            try? FileManager.default.removeItem(at: consentFile)
        }
        var consent = SyncAccountConsent()
        consent.observe("A")
        let firstEpoch = try #require(consent.historyEpoch)
        let original = Metadata(account: "A", epoch: firstEpoch, uploadAfter: Date(timeIntervalSince1970: 10))
        let oldBytes = try JSONEncoder().encode(original)
        try await store.setSyncValue(oldBytes, for: "cloud")

        // Account B is durably approved, but its normalized SQLite state cannot commit.
        consent.observe("B")
        consent.savedNewIdentities()
        let approvedB = consent.choose(.sync, for: "B")
        #expect(approvedB)
        try consent.write(to: consentFile)
        let bEpoch = try #require(consent.historyEpoch)
        var session = HistoryAccountSession()
        let bCutoff = Date(timeIntervalSince1970: 100)
        #expect(session.loaded(verified: "B", stored: original.account, available: true,
                               verifiedEpoch: bEpoch, storedEpoch: original.epoch, now: bCutoff) == .reset(uploadAfter: bCutoff))
        try sql("CREATE TRIGGER deny_cloud_update BEFORE UPDATE ON sync_state WHEN NEW.name = 'cloud' BEGIN SELECT RAISE(ABORT, 'synthetic metadata failure'); END", in: connection)
        do {
            try await store.setSyncValue(JSONEncoder().encode(Metadata(account: "B", epoch: bEpoch, uploadAfter: bCutoff)), for: "cloud")
            Issue.record("The normalized account metadata write should fail")
        } catch {}
        let failedB = session.confirm(verified: "B", stored: "B", persisted: false,
                                      verifiedEpoch: bEpoch, storedEpoch: bEpoch)
        #expect(!failedB)
        #expect(try await store.syncValue("cloud") == oldBytes)

        let space = UUID()
        let intervening = HistoryVisit(space: space, url: URL(string: "https://b.example/private")!, title: "B local visit",
                                       time: Date(timeIntervalSince1970: 150), device: "fixture", kind: .link)
        try await store.record(intervening)
        let localRemoval = HistoryRemoval(space: space, scope: .visit(UUID()), made: Date(timeIntervalSince1970: 200))
        try await store.remove(localRemoval, syncAccount: "A")

        // A relaunch reads the separately persisted B consent, then observes A.
        var relaunchedConsent = try SyncAccountConsent.read(from: consentFile)
        relaunchedConsent.observe("A")
        relaunchedConsent.savedNewIdentities()
        let approvedA = relaunchedConsent.choose(.sync, for: "A")
        #expect(approvedA)
        try relaunchedConsent.write(to: consentFile)
        let returnEpoch = try #require(relaunchedConsent.historyEpoch)
        let stale = try JSONDecoder().decode(Metadata.self, from: #require(try await store.syncValue("cloud")))
        var relaunched = HistoryAccountSession()
        let returnCutoff = Date(timeIntervalSince1970: 300)
        #expect(relaunched.loaded(verified: "A", stored: stale.account, available: true,
                                  verifiedEpoch: returnEpoch, storedEpoch: stale.epoch, now: returnCutoff) == .reset(uploadAfter: returnCutoff))
        #expect(!relaunched.allows(verified: "A", stored: stale.account, verifiedEpoch: returnEpoch, storedEpoch: stale.epoch))
        try sql("DROP TRIGGER deny_cloud_update", in: connection)
        try await store.setSyncValue(JSONEncoder().encode(Metadata(account: "A", epoch: returnEpoch, uploadAfter: returnCutoff)), for: "cloud")
        let confirmedA = relaunched.confirm(verified: "A", stored: "A", persisted: true,
                                            verifiedEpoch: returnEpoch, storedEpoch: returnEpoch)
        #expect(confirmedA)
        #expect(try await store.visits(device: "fixture", space: space, from: returnCutoff,
                                       to: Date(timeIntervalSince1970: 1_000)).isEmpty)
        #expect(try await store.entries(space: space).count == 1, "The B-era visit remains local")
        #expect(try await store.pendingClearings(for: "A").map(\.id) == [localRemoval.id])
        #expect(try await store.pendingClearings(for: "B").isEmpty)
    }

    @Test func lockedDatabaseDoesNotAcknowledgeClearAndCanRetryTheSameRequest() async throws {
        let (file, store, connection) = try fixture()
        defer { sqlite3_close(connection); try? FileManager.default.removeItem(at: file) }
        let space = UUID()
        try await store.record(visit(space: space))
        let before = await store.revision
        let removal = HistoryRemoval(space: space, scope: .all, made: Date().addingTimeInterval(1))
        try sql("BEGIN IMMEDIATE", in: connection)
        do {
            try await store.remove(removal)
            Issue.record("A locked database was acknowledged as cleared")
        } catch {}
        #expect(await store.revision == before)
        #expect(await store.allRemovals().isEmpty)
        try sql("ROLLBACK", in: connection)
        #expect(try await store.entries(space: space).count == 1)
        try await store.remove(removal)
        #expect(try await store.entries(space: space).isEmpty)
    }
}
#endif
