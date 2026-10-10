import XCTest
@testable import PadCore

final class WorkspaceTests: XCTestCase {
    let figma = URL(string: "https://www.figma.com/files")
    let slack = URL(string: "https://app.slack.com/client")
    let notion = URL(string: "https://www.notion.so/")

    func testStartsWithOneSpaceOnANewTab() {
        let w = Workspace.starting()
        XCTAssertEqual(w.spaces.count, 1)
        XCTAssertEqual(w.spaces[0].tabs.count, 1)
        XCTAssertNil(w.spaces[0].tabs.first?.url, "the start page, not a site's sign-in page")
        XCTAssertEqual(w.spaces[0].selected, w.spaces[0].tabs.first?.id)
    }

    func testOpenPutsTheTabAfterTheOneItCameFromAndSelectsIt() throws {
        var w = Workspace.onFigma()
        let space = w.spaces[0].id
        let first = try XCTUnwrap(w.spaces[0].selected)
        let second = try XCTUnwrap(w.openTab(slack, in: space))
        let between = try XCTUnwrap(w.openTab(notion, in: space, after: first))
        XCTAssertEqual(w.spaces[0].tabs.map(\.id), [first, between, second])
        XCTAssertEqual(w.spaces[0].selected, between)
        XCTAssertNil(w.openTab(slack, in: UUID()))
    }

    func testClosingSelectsTheRightNeighbourThenTheLeft() throws {
        var w = Workspace.onFigma()
        let space = w.spaces[0].id
        let a = try XCTUnwrap(w.spaces[0].selected)
        let b = try XCTUnwrap(w.openTab(slack, in: space))
        let c = try XCTUnwrap(w.openTab(notion, in: space))
        w.select(b)
        XCTAssertEqual(w.closeTab(b), c)
        XCTAssertEqual(w.closeTab(c), a)
        XCTAssertNil(w.closeTab(a))
        XCTAssertTrue(w.spaces[0].tabs.isEmpty)
        XCTAssertNil(w.spaces[0].selected)
    }

    func testReopenPutsTheTabBackWhereItWas() throws {
        var w = Workspace.onFigma()
        let space = w.spaces[0].id
        let a = try XCTUnwrap(w.spaces[0].selected)
        let b = try XCTUnwrap(w.openTab(slack, in: space))
        let c = try XCTUnwrap(w.openTab(notion, in: space))
        w.closeTab(b)
        XCTAssertEqual(w.reopen(), b)
        XCTAssertEqual(w.spaces[0].tabs.map(\.id), [a, b, c])
        XCTAssertEqual(w.spaces[0].selected, b)
        XCTAssertNil(w.reopen())
    }

    func testClosedTabsAreKeptUpToALimit() {
        var w = Workspace.onFigma()
        let space = w.spaces[0].id
        for _ in 0..<40 {
            if let id = w.openTab(slack, in: space) { w.closeTab(id) }
        }
        XCTAssertEqual(w.closed.count, Workspace.closedKept)
    }

    func testNeighboursGoRound() throws {
        var w = Workspace.onFigma()
        let space = w.spaces[0].id
        let a = try XCTUnwrap(w.spaces[0].selected)
        let b = try XCTUnwrap(w.openTab(slack, in: space))
        XCTAssertEqual(w.neighbour(of: a, by: 1), b)
        XCTAssertEqual(w.neighbour(of: b, by: 1), a)
        XCTAssertEqual(w.neighbour(of: a, by: -1), b)
        let other = w.addSpace(named: "Client")
        XCTAssertEqual(w.spaceNeighbour(of: space, by: 1), other)
        XCTAssertEqual(w.spaceNeighbour(of: space, by: -1), other)
        XCTAssertEqual(w.spaceNeighbour(of: other, by: 1), space)
    }

    func testSpacesComeWithAnEmptyTabAndTheLastOneStays() {
        var w = Workspace.onFigma()
        let first = w.spaces[0].id
        let client = w.addSpace(named: "Client")
        XCTAssertEqual(w.space(client)?.tabs.count, 1)
        XCTAssertNil(w.space(client)?.tabs.first?.url)
        XCTAssertNotEqual(w.space(client)?.symbol, w.space(first)?.symbol)
        XCTAssertTrue(w.removeSpace(client))
        XCTAssertFalse(w.removeSpace(first))
        XCTAssertEqual(w.spaces.count, 1)
    }

    func testRemovingASpaceForgetsItsClosedTabs() throws {
        var w = Workspace.onFigma()
        let client = w.addSpace(named: "Client")
        let tab = try XCTUnwrap(w.openTab(slack, in: client))
        w.closeTab(tab)
        XCTAssertEqual(w.closed.count, 1)
        XCTAssertTrue(w.removeSpace(client))
        XCTAssertTrue(w.closed.isEmpty)
    }

    func testMovingATabToAnotherSpace() throws {
        var w = Workspace.onFigma()
        let first = w.spaces[0].id
        let tab = try XCTUnwrap(w.spaces[0].selected)
        let client = w.addSpace(named: "Client")
        XCTAssertTrue(w.moveTab(tab, to: client))
        XCTAssertEqual(w.spaceID(of: tab), client)
        XCTAssertNil(w.space(first)?.selected)
        XCTAssertEqual(w.space(client)?.selected, tab)
        XCTAssertFalse(w.moveTab(tab, to: client))
    }

    func testRecordAndRename() throws {
        var w = Workspace.onFigma()
        let tab = try XCTUnwrap(w.spaces[0].selected)
        w.record(tab, url: slack, title: "Slack")
        XCTAssertEqual(w.tab(tab)?.url, slack)
        XCTAssertEqual(w.tab(tab)?.label, "Slack")
        w.record(tab, url: nil, title: "")
        XCTAssertEqual(w.tab(tab)?.label, "app.slack.com/client")
        w.renameSpace(w.spaces[0].id, to: "  Studio ")
        XCTAssertEqual(w.spaces[0].name, "Studio")
        w.renameSpace(w.spaces[0].id, to: "   ")
        XCTAssertEqual(w.spaces[0].name, "Studio")
        XCTAssertEqual(TabRecord(url: nil).label, "New Tab")
    }

    func testRepairFixesSelectionsAndEmptiness() {
        var broken = Workspace(spaces: [Space(name: "A", symbol: "star", tabs: [TabRecord(url: figma)], selected: UUID())])
        broken.repair()
        XCTAssertEqual(broken.spaces[0].selected, broken.spaces[0].tabs[0].id)
        var empty = Workspace(spaces: [])
        empty.repair()
        XCTAssertEqual(empty.spaces.count, 1)
    }

    func testFileRoundTrip() throws {
        var w = Workspace.onFigma()
        let client = w.addSpace(named: "Client")
        w.openTab(slack, in: client)
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("workspace.json")
        try WorkspaceFile.write(w, to: file)
        XCTAssertEqual(WorkspaceFile.read(file), w)
        try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
        XCTAssertNil(WorkspaceFile.read(file))
    }
}
