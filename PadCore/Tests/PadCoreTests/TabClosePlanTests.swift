import Foundation
import XCTest
@testable import PadCore

final class TabClosePlanTests: XCTestCase {
    private let url = URL(string: "https://client.example")!

    func testBulkConfirmationCountsOnlyExistingUniqueOrdinaryTabs() throws {
        var workspace = Workspace.starting()
        let first = workspace.spaces[0].tabs[0].id
        workspace.record(first, url: url, title: "Pinned")
        workspace.pin(first)
        let a = try XCTUnwrap(workspace.openTab(url, in: workspace.spaces[0].id))
        let b = try XCTUnwrap(workspace.openTab(url, in: workspace.spaces[0].id))
        let plan = TabClosePlan(workspace: workspace, requested: [first, a, a, b, UUID()])
        XCTAssertEqual(Set(plan.ids), [first, a, b])
        XCTAssertEqual(Set(plan.ordinary), [a, b])
        XCTAssertEqual(plan.pinned, [first])
        XCTAssertTrue(plan.needsConfirmation)
        XCTAssertEqual(plan.title, "Close 2 tabs?")
    }

    func testOneOrdinaryTabAndPinnedPagesDoNotBecomeMultipleDestructiveClosures() throws {
        var workspace = Workspace.starting()
        let pinned = workspace.spaces[0].tabs[0].id
        workspace.record(pinned, url: url, title: "Pinned")
        workspace.pin(pinned)
        let ordinary = try XCTUnwrap(workspace.openTab(url, in: workspace.spaces[0].id))
        XCTAssertFalse(TabClosePlan(workspace: workspace, requested: [ordinary, pinned]).needsConfirmation)
        XCTAssertFalse(TabClosePlan(workspace: workspace, requested: [UUID()]).needsConfirmation)
    }

    func testClosingPinnedPagesPreservesRecordAndExplicitResetChangesOnlyThePinnedPage() throws {
        var workspace = Workspace.starting()
        let pinned = workspace.spaces[0].tabs[0].id
        workspace.record(pinned, url: url, title: "Original")
        workspace.pin(pinned)
        let ordinary = try XCTUnwrap(workspace.openTab(url, in: workspace.spaces[0].id))
        workspace.record(pinned, url: URL(string: "https://client.example/draft")!, title: "Draft")
        let before = try XCTUnwrap(workspace.tab(pinned))
        workspace.closeTab(pinned)
        XCTAssertEqual(workspace.tab(pinned), before, "ordinary close must not reset a draft's current address or title")
        XCTAssertTrue(workspace.resetPinnedTab(pinned))
        XCTAssertEqual(workspace.tab(pinned)?.url, url)
        XCTAssertEqual(workspace.tab(pinned)?.pinned, before.pinned)
        XCTAssertEqual(workspace.tab(pinned)?.id, before.id)
        XCTAssertFalse(workspace.resetPinnedTab(ordinary))
        XCTAssertNotNil(workspace.tab(ordinary))
        XCTAssertTrue(workspace.closed.isEmpty)
    }

    func testSpaceRemovalCopyDisclosesCurrentEffectiveScopeAndMacExtensionData() {
        let local = SpaceRemovalCopy.message(tabs: 1, device: "iPad", scope: .deviceOnly, extensionData: false)
        XCTAssertTrue(local.contains("1 tab"))
        XCTAssertFalse(local.contains("1 tabs"))
        XCTAssertFalse(local.contains("devices syncing"))
        let paused = SpaceRemovalCopy.message(tabs: 2, device: "Mac", scope: .iCloudUnchanged, extensionData: true)
        XCTAssertTrue(paused.contains("iCloud copies are unchanged"))
        XCTAssertTrue(paused.contains("extension data"))
        let synced = SpaceRemovalCopy.message(tabs: 2, device: "Mac", scope: .currentAccount, extensionData: true)
        XCTAssertTrue(synced.contains("devices syncing with this Apple Account"))
        for item in ["bookmarks", "pinned tabs", "history", "sign-ins", "cookies", "site data"] { XCTAssertTrue(synced.contains(item)) }
    }
}
