import Foundation
import XCTest
@testable import PadCore

final class SyncAccountConsentTests: XCTestCase {
    private func folder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    func testFirstAccountRequiresAnExplicitChoiceAndCurrentIdentity() {
        var permission = SyncAccountConsent()
        permission.observe("Account A")
        XCTAssertFalse(permission.allows("Account A"))
        XCTAssertFalse(permission.allows(nil), "a disk value alone is not a verified current account")
        XCTAssertTrue(permission.choose(.sync, for: "Account A"))
        XCTAssertTrue(permission.allows("Account A"))
        XCTAssertFalse(permission.allows("Account B"))
        XCTAssertFalse(permission.allows(nil))
    }

    func testAccountSwitchRevokesPermissionAndRequiresNewCloudIdentities() throws {
        var permission = SyncAccountConsent()
        permission.observe("A")
        XCTAssertTrue(permission.choose(.sync, for: "A"))
        permission.observe("B")
        XCTAssertEqual(permission.choice, .needsChoice)
        XCTAssertTrue(permission.requiresNewIdentities)
        XCTAssertFalse(permission.allows("A"))
        XCTAssertFalse(permission.allows("B"))
        XCTAssertFalse(permission.choose(.sync, for: "A"), "a stale account-choice action is rejected")
        let relaunched = try JSONDecoder().decode(SyncAccountConsent.self, from: JSONEncoder().encode(permission))
        XCTAssertEqual(relaunched, permission)
        XCTAssertFalse(relaunched.allows("B"), "relaunch does not approve the new account")
    }

    func testKeepingDataLocalSurvivesRelaunchAndSyncToggleReplay() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("sync-account.json")
        var permission = SyncAccountConsent()
        permission.observe("A")
        XCTAssertTrue(permission.choose(.keepLocal, for: "A"))
        try permission.write(to: file)
        var relaunched = try SyncAccountConsent.read(from: file)
        for _ in 0..<3 { relaunched.observe("A") }
        XCTAssertEqual(relaunched.choice, .keepLocal)
        XCTAssertFalse(relaunched.allows("A"))
        XCTAssertTrue(relaunched.choose(.sync, for: "A"))
        try relaunched.write(to: file)
        XCTAssertTrue(try SyncAccountConsent.read(from: file).allows("A"))
    }

    func testSignOutRevokesConsentEvenWhenTheSameAccountReturns() {
        var permission = SyncAccountConsent()
        permission.observe("A")
        XCTAssertTrue(permission.choose(.sync, for: "A"))
        permission.observe(nil)
        permission.observe("A")
        XCTAssertFalse(permission.allows("A"))
        XCTAssertEqual(permission.choice, .needsChoice)
        XCTAssertFalse(permission.requiresNewIdentities, "the same account can retain stable cloud identity")
    }

    func testLegacyUnknownAccountNeverReusesOldIdentitiesAutomatically() {
        var permission = SyncAccountConsent()
        permission.observe("A", legacyIdentityUnknown: true)
        XCTAssertTrue(permission.requiresNewIdentities)
        XCTAssertFalse(permission.allows("A"))
        XCTAssertFalse(permission.choose(.sync, for: "A"), "approval cannot bypass the durable identity-detachment step")
        permission.savedNewIdentities()
        XCTAssertTrue(permission.choose(.sync, for: "A"))
        XCTAssertFalse(permission.requiresNewIdentities)
        XCTAssertTrue(permission.allows("A"))
    }

    func testAccountChangeWhileSyncWasOffStillRequiresAChoice() {
        var permission = SyncAccountConsent()
        permission.observe("A")
        XCTAssertTrue(permission.choose(.sync, for: "A"))
        permission.observe("B")
        XCTAssertFalse(permission.allows("B"))
        permission.observe("B")
        XCTAssertFalse(permission.allows("B"), "repeated identity checks do not provide consent")
    }

    func testHistoryAccountBoundaryRotatesDurablyWhenReturningToAPreviousAccount() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("sync-account.json")
        var permission = SyncAccountConsent()
        permission.observe("A")
        let firstA = try XCTUnwrap(permission.historyEpoch)
        permission.observe("B")
        try permission.write(to: file)
        var relaunched = try SyncAccountConsent.read(from: file)
        XCTAssertNotEqual(relaunched.historyEpoch, firstA)
        relaunched.observe("A")
        XCTAssertNotEqual(relaunched.historyEpoch, firstA)
        XCTAssertFalse(relaunched.allows("A"))
        try relaunched.write(to: file)
        XCTAssertEqual(try SyncAccountConsent.read(from: file).historyEpoch, relaunched.historyEpoch)
    }

    func testExistingConsentAddsADurableHistoryBoundaryWithoutInventingNewApproval() throws {
        let data = Data(#"{"account":"A","choice":"sync","requiresNewIdentities":false}"#.utf8)
        var permission = try JSONDecoder().decode(SyncAccountConsent.self, from: data)
        XCTAssertNil(permission.historyEpoch)
        permission.observe("A")
        XCTAssertNotNil(permission.historyEpoch)
        XCTAssertTrue(permission.allows("A"))
        let saved = try JSONDecoder().decode(SyncAccountConsent.self, from: JSONEncoder().encode(permission))
        XCTAssertEqual(saved.historyEpoch, permission.historyEpoch)
    }

    func testDamagedConsentDoesNotProduceAnApproval() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("sync-account.json")
        try Data("damaged".utf8).write(to: file)
        XCTAssertThrowsError(try SyncAccountConsent.read(from: file))
        XCTAssertFalse(SyncAccountConsent().allows("A"), "the caller's fallback remains paused")
    }

    func testAConsentWriteFailureIsReportedInsteadOfAcknowledged() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let blockedParent = folder.appendingPathComponent("not-a-directory")
        let sentinel = Data("keep this file".utf8)
        try sentinel.write(to: blockedParent)
        var permission = SyncAccountConsent()
        permission.observe("A")
        XCTAssertTrue(permission.choose(.sync, for: "A"))
        XCTAssertThrowsError(try permission.write(to: blockedParent.appendingPathComponent("sync-account.json")))
        XCTAssertEqual(try Data(contentsOf: blockedParent), sentinel)
    }

    func testReturningToAPreviousAccountDoesNotMoveItsExistingBookmarksOrPins() throws {
        var workspace = Workspace.starting()
        workspace.spaces[0].cloudID = UUID()
        workspace.spaces[0].bookmarks = [Bookmark(folder: "Client", children: [Bookmark(title: "Docs", url: URL(string: "https://client.example")!)])]
        workspace.spaces[0].tabs[0].pinned = URL(string: "https://client.example")
        let previous = SyncPlan.records(of: workspace, keeping: SyncMirror())
        let oldSpace = try XCTUnwrap(workspace.spaces[0].cloudID?.uuidString)
        let localID = workspace.spaces[0].id
        SyncPlan.detachAccountIdentities(&workspace)
        let rejoined = SyncPlan.join(&workspace, remote: previous)
        XCTAssertEqual(workspace.spaces.count, 2)
        XCTAssertNotEqual(workspace.space(localID)?.cloudID?.uuidString, oldSpace)
        for (id, bookmark) in previous.bookmarks { XCTAssertEqual(rejoined.bookmarks[id], bookmark) }
        for (id, pin) in previous.pinned { XCTAssertEqual(rejoined.pinned[id], pin) }
        XCTAssertEqual(rejoined.bookmarks.count, previous.bookmarks.count * 2)
        XCTAssertEqual(rejoined.pinned.count, previous.pinned.count * 2)
    }

    func testNewAccountDetachmentPreservesLocalWorkButRemovesAllCloudLinks() {
        var workspace = Workspace.starting()
        workspace.spaces[0].cloudID = UUID()
        workspace.spaces[0].tabs[0].url = URL(string: "https://client.example/draft")
        workspace.spaces[0].tabs[0].cloudID = UUID()
        workspace.spaces[0].tabs[0].pinned = URL(string: "https://client.example")
        workspace.spaces[0].bookmarks = [Bookmark(title: "Client", url: URL(string: "https://client.example")!)]
        let original = workspace
        SyncPlan.detachAccountIdentities(&workspace)
        XCTAssertEqual(workspace.spaces[0].id, original.spaces[0].id)
        XCTAssertEqual(workspace.spaces[0].tabs[0].id, original.spaces[0].tabs[0].id)
        XCTAssertEqual(workspace.spaces[0].tabs[0].url, original.spaces[0].tabs[0].url)
        XCTAssertEqual(workspace.spaces[0].tabs[0].pinned, original.spaces[0].tabs[0].pinned)
        XCTAssertEqual(workspace.spaces[0].bookmarks.map(\.title), original.spaces[0].bookmarks.map(\.title))
        XCTAssertEqual(workspace.spaces[0].bookmarks.map(\.url), original.spaces[0].bookmarks.map(\.url))
        XCTAssertNotEqual(workspace.spaces[0].bookmarks[0].id, original.spaces[0].bookmarks[0].id)
        XCTAssertNil(workspace.spaces[0].cloudID)
        XCTAssertNotEqual(workspace.spaces[0].tabs[0].cloudID, original.spaces[0].tabs[0].cloudID)
    }
}
