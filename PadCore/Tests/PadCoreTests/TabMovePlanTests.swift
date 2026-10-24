import Foundation
import Testing
@testable import PadCore

struct TabMovePlanTests {
    private func fixture() -> (Workspace, UUID, UUID, UUID) {
        let tab = TabRecord(url: URL(string: "https://example.com/draft"), title: "Draft")
        let from = Space(name: "Work", symbol: "briefcase", tabs: [tab], selected: tab.id)
        let to = Space(name: "Personal", symbol: "person", tabs: [TabRecord(url: URL(string: "https://example.net"))])
        return (Workspace(spaces: [from, to]), tab.id, from.id, to.id)
    }

    @Test func cancellationCannotMoveOrReorderTheOriginal() throws {
        var (workspace, tab, _, destination) = fixture()
        let before = workspace
        let plan = try #require(TabMovePlan(workspace: workspace, tab: tab, destination: destination))
        #expect(plan.apply(.cancel, to: &workspace) == nil)
        #expect(workspace == before)
    }

    @Test func aCopyGetsANewIdentityAndLeavesTheOriginalRecordAndStoreOwnerIntact() throws {
        var (workspace, tab, source, destination) = fixture()
        let original = workspace.tab(tab)
        let plan = try #require(TabMovePlan(workspace: workspace, tab: tab, destination: destination))
        let copy = try #require(plan.apply(.copy, to: &workspace))
        #expect(copy != tab)
        #expect(workspace.tab(tab) == original)
        #expect(workspace.spaceID(of: tab) == source)
        #expect(workspace.spaceID(of: copy) == destination)
        #expect(workspace.tab(copy)?.url == original?.url)
        #expect(workspace.tab(copy)?.title == original?.title)
        #expect(workspace.tab(copy)?.cloudID == nil)
    }

    @Test func onlyExplicitMoveKeepsTheTabIdentityInTheDestination() throws {
        var (workspace, tab, source, destination) = fixture()
        let plan = try #require(TabMovePlan(workspace: workspace, tab: tab, destination: destination))
        #expect(plan.apply(.move, to: &workspace) == tab)
        #expect(workspace.spaceID(of: tab) == destination)
        #expect(workspace.space(source)?.tabs.isEmpty == true)
    }

    @Test func aNavigationAfterTheQuestionInvalidatesBothDestructiveAndCopyChoices() throws {
        var (workspace, tab, _, destination) = fixture()
        let plan = try #require(TabMovePlan(workspace: workspace, tab: tab, destination: destination))
        workspace.record(tab, url: URL(string: "https://example.com/another-document"), title: "Another")
        let changed = workspace
        #expect(plan.apply(.move, to: &workspace) == nil)
        #expect(plan.apply(.copy, to: &workspace) == nil)
        #expect(workspace == changed)
    }

    @Test func aRemovedDestinationOrMovedInsertionTargetInvalidatesTheRequest() throws {
        var (workspace, tab, source, destination) = fixture()
        let target = try #require(workspace.space(destination)?.tabs.first?.id)
        let plan = try #require(TabMovePlan(workspace: workspace, tab: tab, destination: destination, before: target))
        let targetMoved = workspace.moveTab(target, to: source)
        #expect(targetMoved)
        let changed = workspace
        #expect(plan.apply(.move, to: &workspace) == nil)
        #expect(workspace == changed)
        let withoutTarget = try #require(TabMovePlan(workspace: workspace, tab: tab, destination: destination))
        let removed = workspace.removeSpace(destination)
        #expect(removed)
        #expect(withoutTarget.apply(.copy, to: &workspace) == nil)
    }

    @Test func anotherMoveWhileTheDialogIsOpenCannotMoveTheTabTwice() throws {
        var (workspace, tab, _, destination) = fixture()
        let third = workspace.addSpace(named: "Third")
        let plan = try #require(TabMovePlan(workspace: workspace, tab: tab, destination: destination))
        let moved = workspace.moveTab(tab, to: third)
        #expect(moved)
        let changed = workspace
        #expect(plan.apply(.move, to: &workspace) == nil)
        #expect(workspace == changed)
    }
}
