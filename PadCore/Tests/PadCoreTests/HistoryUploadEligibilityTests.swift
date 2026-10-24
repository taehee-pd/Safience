#if canImport(SQLite3)
import Foundation
import SQLite3
import Testing
@testable import PadCore

@MainActor
struct HistoryUploadEligibilityTests {
    private func folder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("history-eligibility-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func sql(_ text: String, in db: OpaquePointer) throws {
        guard sqlite3_exec(db, text, nil, nil, nil) == SQLITE_OK else {
            throw HistoryStoreError.sqlite(String(cString: sqlite3_errmsg(db)))
        }
    }

    private func connection(_ file: URL) throws -> OpaquePointer {
        var db: OpaquePointer?
        guard sqlite3_open(file.path, &db) == SQLITE_OK, let db else { throw HistoryStoreError.sqlite("fixture open") }
        return db
    }

    private func visit(_ path: String, space: UUID, time: Double, title: String = "", summary: String = "", search: String? = nil) -> HistoryVisit {
        HistoryVisit(space: space, url: URL(string: "https://fixture.invalid/\(path)")!, title: title, summary: summary,
                     time: Date(timeIntervalSince1970: time), device: "fixture", kind: .typed, search: search)
    }

    private func validated(_ account: String, epoch: UUID) -> HistoryAccountSession {
        var session = HistoryAccountSession()
        _ = session.loaded(verified: account, stored: account, available: true, verifiedEpoch: epoch, storedEpoch: epoch)
        _ = session.confirm(verified: account, stored: account, persisted: true, verifiedEpoch: epoch, storedEpoch: epoch)
        return session
    }

    @Test func consentWriteDenialAndStaleARelaunchKeepUnknownAndBVisitsLocal() async throws {
        struct Metadata: Codable {
            let account: String
            let accountEpoch: UUID
            let uploadAfter: Date
        }
        let root = try folder()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
            try? FileManager.default.removeItem(at: root)
        }
        let database = root.appendingPathComponent("history.sqlite")
        let consentFile = root.appendingPathComponent("sync-account.json")
        let store = try HistoryStore(url: database)
        var consent = SyncAccountConsent()
        consent.observe("A")
        consent.savedNewIdentities()
        let approvedA = consent.choose(.sync, for: "A")
        #expect(approvedA)
        try consent.write(to: consentFile)
        let firstEpoch = try #require(consent.historyEpoch)
        let oldConsent = try Data(contentsOf: consentFile)
        let metadata = Metadata(account: "A", accountEpoch: firstEpoch, uploadAfter: Date(timeIntervalSince1970: 10))
        let oldMetadata = try JSONEncoder().encode(metadata)
        try await store.setSyncValue(oldMetadata, for: "cloud")
        let space = UUID()
        let oldA = visit("old-a", space: space, time: 100, title: "A")
        try await store.record(oldA, syncEpoch: firstEpoch)

        // Before the first account verification and during a definite sign-out,
        // capture no upload grant. These rows survive a later approved A.
        var admission = HistoryAccountSession()
        let unknownEpoch = admission.uploadEpoch(verified: nil, stored: "A", verifiedEpoch: nil, storedEpoch: firstEpoch)
        #expect(unknownEpoch == nil)
        let startup = visit("startup-unverified", space: space, time: 50_000, title: "Unknown account")
        try await store.record(startup, syncEpoch: unknownEpoch)
        admission = validated("A", epoch: firstEpoch)
        admission.revoke()
        let signedOutEpoch = admission.uploadEpoch(verified: nil, stored: "A", verifiedEpoch: nil, storedEpoch: firstEpoch)
        let signedOut = visit("signed-out", space: space, time: 50_001, title: "Signed out")
        try await store.record(signedOut, syncEpoch: signedOutEpoch)

        // Deny atomic replacement in the directory while an already open WAL
        // database remains writable. A's consent and cloud metadata stay on disk.
        consent.observe("B")
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: root.path)
        do {
            try consent.write(to: consentFile)
            Issue.record("The synthetic directory must deny the consent write")
        } catch {}
        #expect(try Data(contentsOf: consentFile) == oldConsent)
        let bEpoch = admission.uploadEpoch(verified: nil, stored: "A", verifiedEpoch: nil, storedEpoch: firstEpoch)
        #expect(bEpoch == nil)
        let b = visit("b-private?query=b-only", space: space, time: 50_002, title: "B private", search: "B-only search")
        try await store.record(b, syncEpoch: bEpoch)
        #expect(try await store.syncValue("cloud") == oldMetadata)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)

        // Relaunch under A really does read the old matching epoch and cutoff.
        let reopened = try HistoryStore(url: database)
        var relaunchedConsent = try SyncAccountConsent.read(from: consentFile)
        relaunchedConsent.observe("A")
        let stale = try JSONDecoder().decode(Metadata.self, from: #require(try await reopened.syncValue("cloud")))
        var relaunched = HistoryAccountSession()
        #expect(relaunched.loaded(verified: "A", stored: stale.account, available: true,
                                  verifiedEpoch: relaunchedConsent.historyEpoch, storedEpoch: stale.accountEpoch) == .retain)
        let confirmedA = relaunched.confirm(verified: "A", stored: stale.account, persisted: true,
                                   verifiedEpoch: relaunchedConsent.historyEpoch, storedEpoch: stale.accountEpoch)
        #expect(confirmedA)
        let currentEpoch = try #require(relaunched.uploadEpoch(verified: "A", stored: stale.account,
            verifiedEpoch: relaunchedConsent.historyEpoch, storedEpoch: stale.accountEpoch))
        let newA = visit("new-a", space: space, time: 50_003, title: "New A")
        try await reopened.record(newA, syncEpoch: currentEpoch)
        let uploads = try await reopened.visitsForSync(device: "fixture", space: space, from: stale.uploadAfter,
                                                       to: Date(timeIntervalSince1970: 100_000), epoch: currentEpoch)
        #expect(Set(uploads.map(\.id)) == [oldA.id, newA.id])
        #expect(try await reopened.entries(space: space).count == 5, "Unknown and B-era history remains visible locally")
        let days = try await reopened.daysForSync(device: "fixture", since: stale.uploadAfter, epoch: currentEpoch)
        #expect(days.count == 1)
    }

    @Test func failedVisitWriteRetriedAfterAccountApprovalKeepsItsCapturedLocalOnlyTag() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("history.sqlite")
        let store = try HistoryStore(url: file)
        let db = try connection(file)
        defer { sqlite3_close(db) }
        let space = UUID(), epoch = UUID()
        let capturedEpoch: UUID? = nil
        let pending = visit("queued-before-verification", space: space, time: 50_000)
        try sql("CREATE TRIGGER deny_visit BEFORE INSERT ON visits BEGIN SELECT RAISE(ABORT, 'synthetic visit write denial'); END", in: db)
        do {
            try await store.record(pending, syncEpoch: capturedEpoch)
            Issue.record("The queued visit write must fail")
        } catch {}
        #expect(try await store.entries(space: space).isEmpty)
        try sql("DROP TRIGGER deny_visit", in: db)
        let approved = validated("A", epoch: epoch)
        #expect(approved.uploadEpoch(verified: "A", stored: "A", verifiedEpoch: epoch, storedEpoch: epoch) == epoch)
        // Retry receives the original captured value, not the new approval.
        try await store.record(pending, syncEpoch: capturedEpoch)
        #expect(try await store.entries(space: space).map(\.id) == [pending.id])
        #expect(try await store.visitsForSync(device: "fixture", space: space, from: .distantPast, to: .distantFuture, epoch: epoch).isEmpty)
    }

    @Test func accountEpochsAndUnknownRowsCannotBorrowAnotherAccountsPageMetadata() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try HistoryStore(url: root.appendingPathComponent("history.sqlite"))
        let space = UUID(), aEpoch = UUID(), bEpoch = UUID()
        let a = visit("shared-page", space: space, time: 100)
        try await store.record(a, syncEpoch: aEpoch)
        let bLocal = visit("shared-page", space: space, time: 200, title: "B-only title", summary: "B-only summary")
        try await store.record(bLocal)
        _ = try await store.update(space: space, url: bLocal.url, title: "B later title", summary: "B later summary", device: "fixture")
        let emptySnapshot = try await store.visitsForSync(device: "fixture", space: space, from: .distantPast, to: .distantFuture, epoch: aEpoch)
        #expect(emptySnapshot.count == 1 && emptySnapshot[0].title.isEmpty && emptySnapshot[0].summary.isEmpty,
                "An empty approved snapshot must not fall back to shared local page metadata")
        let b = visit("shared-page", space: space, time: 50_000, title: "Approved B", summary: "Approved B summary", search: "B-only search")
        try await store.record(b, syncEpoch: bEpoch)
        _ = try await store.update(space: space, url: a.url, title: "A update", summary: "A summary", device: "fixture", syncEpoch: aEpoch, visit: a.id)
        // A queued B metadata update can be replayed after A starts again.
        _ = try await store.update(space: space, url: b.url, title: "Queued B update", summary: "Queued B summary", device: "fixture", syncEpoch: bEpoch, visit: b.id)
        _ = try await store.update(space: space, url: bLocal.url, title: "Delayed B description relabeled under A", summary: "B private text", device: "fixture", syncEpoch: aEpoch, visit: bLocal.id)
        let aOnly = try await store.visitsForSync(device: "fixture", space: space, from: .distantPast, to: .distantFuture, epoch: aEpoch)
        #expect(aOnly.map(\.id) == [a.id] && aOnly[0].title == "A update" && aOnly[0].summary == "A summary")
        #expect(aOnly[0].search == nil)
        let bOnly = try await store.visitsForSync(device: "fixture", space: space, from: .distantPast, to: .distantFuture, epoch: bEpoch)
        #expect(bOnly.map(\.id) == [b.id] && bOnly[0].title == "Queued B update" && bOnly[0].search == "B-only search")
        #expect(try await store.entries(space: space).count == 3)
    }

    @Test func duplicateAndRemoteMergesNeverPromoteLocalOnlyRowsOrReplaceUploadSnapshots() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try HistoryStore(url: root.appendingPathComponent("history.sqlite"))
        let space = UUID(), epoch = UUID()
        var local = visit("local-only", space: space, time: 100, title: "Local")
        try await store.record(local)
        local.title = "Duplicate must not promote"
        try await store.record(local, syncEpoch: epoch)
        var incoming = visit("remote", space: space, time: 200, title: "Remote")
        incoming.device = "fixture"
        try await store.merge([incoming])
        let approved = visit("approved", space: space, time: 300, title: "Approved snapshot")
        try await store.record(approved, syncEpoch: epoch)
        var duplicate = approved
        duplicate.title = "Remote replacement"
        duplicate.summary = "Remote summary"
        try await store.merge([duplicate])
        let uploads = try await store.visitsForSync(device: "fixture", space: space, from: .distantPast, to: .distantFuture, epoch: epoch)
        #expect(uploads.map(\.id) == [approved.id] && uploads[0].title == "Approved snapshot" && uploads[0].summary.isEmpty)
        #expect(try await store.entries(space: space).count == 3)
    }

    @Test func legacyDatabaseMigrationPreservesLocalVisitsWithoutInventingUploadEligibility() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("history.sqlite")
        let db = try connection(file)
        defer { sqlite3_close(db) }
        let space = UUID(), epoch = UUID()
        let legacy = visit("legacy", space: space, time: 100, title: "Retained legacy visit")
        try sql("""
            CREATE TABLE visits (id TEXT PRIMARY KEY, space TEXT NOT NULL, page TEXT NOT NULL, url TEXT NOT NULL, time REAL NOT NULL,
                device TEXT NOT NULL, kind TEXT NOT NULL, search TEXT, stamp REAL);
            CREATE TABLE removals (id TEXT PRIMARY KEY, space TEXT, scope TEXT NOT NULL, made REAL NOT NULL, wall REAL);
            CREATE TABLE pages (space TEXT NOT NULL, page TEXT NOT NULL, url TEXT NOT NULL, title TEXT NOT NULL DEFAULT '',
                summary TEXT NOT NULL DEFAULT '', last REAL NOT NULL, count INTEGER NOT NULL, frecency REAL NOT NULL,
                search TEXT, embedding BLOB, embedding_model TEXT, UNIQUE(space, page));
            INSERT INTO visits(id,space,page,url,time,device,kind) VALUES ('\(legacy.id.uuidString)','\(space.uuidString)','\(History.pageKey(legacy.url))','\(legacy.url.absoluteString)',100,'fixture','link');
            INSERT INTO pages(space,page,url,title,last,count,frecency) VALUES ('\(space.uuidString)','\(History.pageKey(legacy.url))','\(legacy.url.absoluteString)','Retained legacy visit',100,1,0);
            PRAGMA user_version = 3;
            """, in: db)
        let store = try HistoryStore(url: file)
        let reopened = try HistoryStore(url: file)
        #expect(try await reopened.entries(space: space).map(\.id) == [legacy.id])
        #expect(try await reopened.visitsForSync(device: "fixture", space: space, from: .distantPast, to: .distantFuture, epoch: epoch).isEmpty)
        #expect(try await reopened.daysForSync(device: "fixture", since: .distantPast, epoch: epoch).isEmpty)
        _ = store
    }

    @Test func ordinaryOrphanCleanupKeepsOldWritersButExplicitSpaceDeletionIncludesAllOwnedWriters() {
        let device = "fixture", target = UUID(), other = UUID()
        let oldWriter = HistoryUploadIdentity.writer(device: device, epoch: UUID())
        let currentWriter = HistoryUploadIdentity.writer(device: device, epoch: UUID())
        let record: (String, UUID) -> String = { writer, space in
            HistoryCloudRecord.day(device: writer, space: space, day: "20261023", chunk: 0).name
        }
        let legacy = record(device, target), old = record(oldWriter, target), current = record(currentWriter, target)
        let unrelated = record(oldWriter, other), foreign = record("another-device", target)
        let mine: Set<String> = [legacy, old, current, unrelated, foreign]
        #expect(HistoryUploadIdentity.orphanedRecords(mine, activeSpaces: [], currentWriter: currentWriter) == [current])
        #expect(HistoryUploadIdentity.recordsForRemovedSpace(mine, cloud: target, device: device) == [legacy, old, current])
    }

    @Test func sameAccountEpochRotationDoesNotExpireRetainedOldWriterDays() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let oldWriter = HistoryUploadIdentity.writer(device: "fixture", epoch: UUID())
        let newWriter = HistoryUploadIdentity.writer(device: "fixture", epoch: UUID())
        let space = UUID()
        let retained = HistoryCloudRecord.day(device: oldWriter, space: space,
            day: HistoryCloudDay.key(for: now.addingTimeInterval(-2 * 86_400)), chunk: 0).name
        let expired = HistoryCloudRecord.day(device: oldWriter, space: space,
            day: HistoryCloudDay.key(for: now.addingTimeInterval(-401 * 86_400)), chunk: 0).name
        let current = HistoryCloudRecord.day(device: newWriter, space: space, day: HistoryCloudDay.key(for: now), chunk: 0).name
        let clearing = HistoryCloudRecord.removal(UUID()).name
        let deletion = HistoryCloudDay.expiredRecords([retained, expired, current, clearing],
            retentionCutoff: now.addingTimeInterval(-30 * 86_400), now: now)
        #expect(deletion == [expired], "A new epoch's upload cutoff must not delete retained old-writer records")
    }

    @Test func writerNamespacesPreserveLegacyAndOtherEpochDayRecords() {
        let a = UUID(), b = UUID(), space = UUID()
        let first = HistoryUploadIdentity.writer(device: "fixture", epoch: a)
        let second = HistoryUploadIdentity.writer(device: "fixture", epoch: b)
        let oldName = HistoryCloudRecord.day(device: "fixture", space: space, day: "20261023", chunk: 0).name
        let aName = HistoryCloudRecord.day(device: first, space: space, day: "20261023", chunk: 0).name
        let bName = HistoryCloudRecord.day(device: second, space: space, day: "20261023", chunk: 0).name
        #expect(Set([oldName, aName, bName]).count == 3)
        #expect(HistoryCloudRecord(name: aName) == .day(device: first, space: space, day: "20261023", chunk: 0))
        #expect(HistoryUploadIdentity.owns(writer: "fixture", device: "fixture"))
        #expect(HistoryUploadIdentity.owns(writer: first, device: "fixture"))
        #expect(HistoryUploadIdentity.owns(writer: second, device: "fixture"))
        #expect(!HistoryUploadIdentity.owns(writer: first, device: "other"))
        #expect(!HistoryUploadIdentity.owns(writer: "fixture-untrusted-suffix", device: "fixture"))
    }
}
#endif
