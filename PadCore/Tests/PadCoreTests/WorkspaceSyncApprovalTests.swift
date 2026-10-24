import Foundation
import XCTest
@testable import PadCore

final class WorkspaceSyncApprovalTests: XCTestCase {
    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("workspace-account-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func approvedA() -> SyncAccountConsent {
        var consent = SyncAccountConsent()
        consent.observe("A")
        _ = consent.choose(.sync, for: "A")
        return consent
    }

    func testDeniedAccountStateWritesCannotAuthorizeSavedBEditsOnRelaunchWithA() throws {
        let root = try fixture()
        let state = root.appendingPathComponent("state")
        try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: state.path)
            try? FileManager.default.removeItem(at: root)
        }
        let consentFile = state.appendingPathComponent("sync-account.json")
        let syncFile = state.appendingPathComponent("sync.json")
        let workspaceFile = root.appendingPathComponent("workspace.json")
        let permission = approvedA()
        try permission.write(to: consentFile)
        let originalSync = Data(#"{"account":"A"}"#.utf8)
        try originalSync.write(to: syncFile)
        var workspace = Workspace.starting()
        workspace.spaces[0].cloudID = UUID()
        try WorkspaceFile.write(workspace, to: workspaceFile)
        var changedAccount = permission
        changedAccount.observe("B")
        let fence = UUID()
        workspace.syncApprovalRequired = fence
        workspace.spaces[0].name = "Private B edits"
        workspace.spaces[0].bookmarks = [Bookmark(title: "B only", url: URL(string: "https://b.example/private")!)]
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: state.path)
        XCTAssertThrowsError(try changedAccount.write(to: consentFile))
        XCTAssertThrowsError(try Data(#"{"account":"B"}"#.utf8).write(to: syncFile, options: .atomic))
        try WorkspaceFile.write(workspace, to: workspaceFile)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: state.path)
        var oldConsent = try SyncAccountConsent.read(from: consentFile)
        oldConsent.observe("A")
        XCTAssertTrue(oldConsent.allows("A"), "reproduces the old separate-file approval")
        let relaunched = try XCTUnwrap(WorkspaceFile.read(workspaceFile))
        XCTAssertEqual(try Data(contentsOf: syncFile), originalSync)
        XCTAssertEqual(relaunched.syncApprovalRequired, fence)
        XCTAssertEqual(relaunched.spaces[0].name, "Private B edits")
        XCTAssertEqual(relaunched.spaces[0].bookmarks[0].title, "B only")
        XCTAssertFalse(oldConsent.allows("A", workspace: relaunched))
    }

    func testFailedFenceClearLeavesDurableApprovalGateAndDetachedLocalContents() throws {
        let root = try fixture()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
            try? FileManager.default.removeItem(at: root)
        }
        let file = root.appendingPathComponent("workspace.json")
        let fence = UUID()
        var workspace = Workspace.starting()
        workspace.syncApprovalRequired = fence
        workspace.spaces[0].cloudID = UUID()
        workspace.spaces[0].bookmarks = [Bookmark(title: "Retained", url: URL(string: "https://retained.example")!)]
        let localSpace = workspace.spaces[0].id
        SyncPlan.detachAccountIdentities(&workspace)
        try WorkspaceFile.write(workspace, to: file)
        var candidate = workspace
        XCTAssertTrue(candidate.clearSyncApproval(ifMatching: fence))
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: root.path)
        XCTAssertThrowsError(try WorkspaceFile.write(candidate, to: file))
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        let relaunched = try XCTUnwrap(WorkspaceFile.read(file))
        XCTAssertEqual(relaunched.syncApprovalRequired, fence)
        XCTAssertNil(relaunched.spaces[0].cloudID)
        XCTAssertEqual(relaunched.spaces[0].id, localSpace)
        XCTAssertEqual(relaunched.spaces[0].bookmarks[0].title, "Retained")
        XCTAssertFalse(approvedA().allows("A", workspace: relaunched))
    }

    func testStaleApprovalCannotClearANewerBoundary() {
        var workspace = Workspace.starting()
        let stale = UUID()
        let current = UUID()
        workspace.syncApprovalRequired = current
        XCTAssertFalse(workspace.clearSyncApproval(ifMatching: stale))
        XCTAssertEqual(workspace.syncApprovalRequired, current)
        XCTAssertTrue(workspace.clearSyncApproval(ifMatching: current))
        XCTAssertTrue(approvedA().allows("A", workspace: workspace))
    }

    func testExistingWorkspaceWithoutFenceStillDecodes() throws {
        let workspace = Workspace.starting()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(workspace)) as? [String: Any])
        object.removeValue(forKey: "syncApprovalRequired")
        let legacy = try JSONDecoder().decode(Workspace.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(legacy.syncApprovalRequired)
        XCTAssertTrue(approvedA().allows("A", workspace: legacy))
    }

    func testOrdinaryTabNavigationIsNotASyncableEditButBookmarksAndPinnedTitlesAre() {
        var workspace = Workspace.starting()
        workspace.spaces[0].cloudID = UUID()
        var ordinary = workspace
        ordinary.spaces[0].tabs[0].url = URL(string: "https://example.com/ordinary")
        ordinary.spaces[0].tabs[0].title = "Ordinary navigation"
        XCTAssertFalse(SyncPlan.hasSyncableChanges(from: workspace, to: ordinary))
        var bookmarked = ordinary
        bookmarked.spaces[0].bookmarks = [Bookmark(title: "Private", url: URL(string: "https://example.com/private")!)]
        XCTAssertTrue(SyncPlan.hasSyncableChanges(from: ordinary, to: bookmarked))
        var pinned = ordinary
        pinned.spaces[0].tabs[0].pinned = pinned.spaces[0].tabs[0].url
        var renamed = pinned
        renamed.spaces[0].tabs[0].title = "Different account title"
        XCTAssertTrue(SyncPlan.hasSyncableChanges(from: pinned, to: renamed))
    }

    func testExtensionOwnershipComparisonIgnoresNamesAndOrderButIncludesLocalSpaceAndAccess() {
        let first = SyncPlan.LocalExtension(storeID: "one", title: "__MSG_name__", siteAccess: "onClick", spaces: ["local-no-cloud-id"])
        let second = SyncPlan.LocalExtension(storeID: "two", title: "Second", siteAccess: "allSites", spaces: [])
        var localized = first
        localized.title = "Localized Name"
        XCTAssertFalse(SyncPlan.hasExtensionConfigurationChanges(from: [first, second], to: [second, localized]))
        var toggled = localized
        toggled.spaces = []
        XCTAssertTrue(SyncPlan.hasExtensionConfigurationChanges(from: [first], to: [toggled]))
        var access = localized
        access.siteAccess = "allSites"
        XCTAssertTrue(SyncPlan.hasExtensionConfigurationChanges(from: [first], to: [access]))
        XCTAssertTrue(SyncPlan.hasExtensionConfigurationChanges(from: [first], to: []))
        XCTAssertTrue(SyncPlan.hasExtensionConfigurationChanges(from: [], to: [first]))
    }

}
