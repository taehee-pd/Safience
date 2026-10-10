import XCTest
@testable import PadCore

final class PinnedTabTests: XCTestCase {
    let figma = URL(string: "https://www.figma.com/files")
    let slack = URL(string: "https://app.slack.com/client")
    let notion = URL(string: "https://www.notion.so/")
    let elsewhere = URL(string: "https://www.figma.com/design/AbC/Product")

    func testPinningMovesTheTabToTheFrontAndKeepsItsAddress() throws {
        var w = Workspace.onFigma()
        let space = w.spaces[0].id
        let a = try XCTUnwrap(w.spaces[0].selected)
        let b = try XCTUnwrap(w.openTab(slack, in: space))
        let c = try XCTUnwrap(w.openTab(notion, in: space))
        XCTAssertTrue(w.pin(c))
        XCTAssertEqual(w.spaces[0].tabs.map(\.id), [c, a, b])
        XCTAssertEqual(w.tab(c)?.pinned, notion)
        XCTAssertTrue(w.pin(b))
        XCTAssertEqual(w.spaces[0].tabs.map(\.id), [c, b, a])
        XCTAssertEqual(w.spaces[0].pinnedCount, 2)
        XCTAssertFalse(w.pin(b), "already pinned")
    }

    func testATabThatWentNowhereHasNothingToPin() throws {
        var w = Workspace.onFigma()
        let empty = try XCTUnwrap(w.openTab(nil, in: w.spaces[0].id))
        XCTAssertFalse(w.pin(empty))
        XCTAssertNil(w.tab(empty)?.pinned)
    }

    func testClosingAPinnedTabTakesItBackInsteadOfAway() throws {
        var w = Workspace.onFigma()
        let space = w.spaces[0].id
        let a = try XCTUnwrap(w.spaces[0].selected)
        let b = try XCTUnwrap(w.openTab(slack, in: space))
        XCTAssertTrue(w.pin(a))
        w.record(a, url: elsewhere, title: "Product")
        w.select(a)
        XCTAssertEqual(w.closeTab(a), b, "the neighbour is selected, as for any tab closed")
        XCTAssertEqual(w.spaces[0].tabs.map(\.id), [a, b], "but the pinned tab stays")
        XCTAssertEqual(w.tab(a)?.url, figma)
        XCTAssertEqual(w.tab(a)?.title, "")
        XCTAssertTrue(w.closed.isEmpty, "nothing to reopen: it never went")
    }

    func testThePinnedTabAloneStaysSelected() throws {
        var w = Workspace.onFigma()
        let a = try XCTUnwrap(w.spaces[0].selected)
        w.pin(a)
        XCTAssertEqual(w.closeTab(a), a)
        XCTAssertEqual(w.spaces[0].tabs.count, 1)
    }

    func testNewTabsNeverLandAmongThePinned() throws {
        var w = Workspace.onFigma()
        let space = w.spaces[0].id
        let a = try XCTUnwrap(w.spaces[0].selected)
        let b = try XCTUnwrap(w.openTab(slack, in: space))
        w.pin(a)
        w.pin(b)
        let c = try XCTUnwrap(w.openTab(notion, in: space, after: a))
        XCTAssertEqual(w.spaces[0].tabs.map(\.id), [a, b, c])
    }

    func testUnpinningPutsItFirstAfterThePinned() throws {
        var w = Workspace.onFigma()
        let space = w.spaces[0].id
        let a = try XCTUnwrap(w.spaces[0].selected)
        let b = try XCTUnwrap(w.openTab(slack, in: space))
        let c = try XCTUnwrap(w.openTab(notion, in: space))
        w.pin(a)
        w.pin(b)
        XCTAssertTrue(w.unpin(a))
        XCTAssertEqual(w.spaces[0].tabs.map(\.id), [b, a, c])
        XCTAssertNil(w.tab(a)?.pinned)
        XCTAssertFalse(w.unpin(c))
    }

    func testBackToThePinnedAddress() throws {
        var w = Workspace.onFigma()
        let a = try XCTUnwrap(w.spaces[0].selected)
        w.pin(a)
        w.record(a, url: elsewhere, title: nil)
        XCTAssertEqual(w.backToPinned(a), figma)
        XCTAssertEqual(w.tab(a)?.url, figma)
    }

    func testMovingKeepsPinnedAndOtherTabsApart() throws {
        var w = Workspace.onFigma()
        let space = w.spaces[0].id
        let a = try XCTUnwrap(w.spaces[0].selected)
        let b = try XCTUnwrap(w.openTab(slack, in: space))
        let c = try XCTUnwrap(w.openTab(notion, in: space))
        w.pin(a)
        w.moveTab(a, toIndex: 2)
        XCTAssertEqual(w.spaces[0].tabs.map(\.id), [a, b, c])
        w.moveTab(c, toIndex: 0)
        XCTAssertEqual(w.spaces[0].tabs.map(\.id), [a, c, b])
    }

    func testRepairPutsPinnedTabsFirst() {
        let loose = TabRecord(url: slack)
        let pinned = TabRecord(url: figma, pinned: figma)
        var w = Workspace(spaces: [Space(name: "Work", symbol: "briefcase", tabs: [loose, pinned])])
        w.repair()
        XCTAssertEqual(w.spaces[0].tabs.map(\.id), [pinned.id, loose.id])
    }

    func testAPinnedTabStaysPinnedInAnotherSpace() throws {
        var w = Workspace.onFigma()
        let home = w.spaces[0].id
        let a = try XCTUnwrap(w.spaces[0].selected)
        w.pin(a)
        let other = w.addSpace(named: "Client")
        XCTAssertTrue(w.moveTab(a, to: other))
        XCTAssertEqual(w.space(other)?.tabs.first?.id, a)
        XCTAssertEqual(w.tab(a)?.pinned, figma)
        XCTAssertTrue(w.space(home)?.tabs.isEmpty ?? false)
    }

    func testAReopenedTabIsNeverAmongThePinned() throws {
        var w = Workspace.onFigma()
        let space = w.spaces[0].id
        let a = try XCTUnwrap(w.spaces[0].selected)
        let b = try XCTUnwrap(w.openTab(slack, in: space))
        w.closeTab(a)
        w.pin(b)
        XCTAssertEqual(w.reopen(), a)
        XCTAssertEqual(w.spaces[0].tabs.map(\.id), [b, a])
    }
}

final class SpaceTests: XCTestCase {
    func testNewSpacesGetAColourNoOtherHas() {
        var w = Workspace.onFigma()
        for number in 1...5 { w.addSpace(named: "Space \(number)") }
        let colours = w.spaces.map(\.color)
        XCTAssertEqual(Set(colours).count, colours.count)
        w.setColor(w.spaces[1].id, to: .orange)
        XCTAssertEqual(w.spaces[1].color, .orange)
    }

    func testSpacesReorderAsAListDragsThem() {
        var w = Workspace.onFigma()
        let a = w.spaces[0].id
        let b = w.addSpace(named: "B")
        let c = w.addSpace(named: "C")
        w.moveSpaces(from: IndexSet(integer: 2), to: 0)
        XCTAssertEqual(w.spaces.map(\.id), [c, a, b])
        w.moveSpaces(from: IndexSet(integer: 0), to: 3)
        XCTAssertEqual(w.spaces.map(\.id), [a, b, c])
        w.moveSpaces(from: IndexSet([0, 1]), to: 3)
        XCTAssertEqual(w.spaces.map(\.id), [c, a, b])
        w.moveSpaces(from: IndexSet(integer: 9), to: 0)
        XCTAssertEqual(w.spaces.map(\.id), [c, a, b], "an offset that isn't there moves nothing")
    }

    func testAFileFromBeforeColoursBookmarksAndPinsStillReads() throws {
        let saved = #"""
        {"spaces":[{"id":"A6E46D39-6E2E-4D3A-9F2B-2F6B1B3C4D5E","name":"Work","symbol":"paintpalette",
        "tabs":[{"id":"B6E46D39-6E2E-4D3A-9F2B-2F6B1B3C4D5E","url":"https://www.figma.com/files","title":"Figma","shown":0}],
        "selected":"B6E46D39-6E2E-4D3A-9F2B-2F6B1B3C4D5E"}],"closed":[]}
        """#
        let w = try JSONDecoder().decode(Workspace.self, from: Data(saved.utf8))
        XCTAssertEqual(w.spaces[0].color, SpaceColor.standard(for: "paintpalette"))
        XCTAssertTrue(w.spaces[0].bookmarks.isEmpty)
        XCTAssertNil(w.spaces[0].tabs[0].pinned)
        let again = try JSONDecoder().decode(Workspace.self, from: JSONEncoder().encode(w))
        XCTAssertEqual(again, w)
    }

    func testEachSpaceKeepsItsOwnBookmarks() throws {
        var w = Workspace.onFigma()
        let work = w.spaces[0].id
        let client = w.addSpace(named: "Client")
        let url = try XCTUnwrap(URL(string: "https://linear.app/"))
        let id = try XCTUnwrap(w.addBookmark(url, title: "Linear", in: work))
        XCTAssertEqual(w.addBookmark(try XCTUnwrap(URL(string: "https://LINEAR.app")), title: "Again", in: work), id,
                       "the same page is bookmarked once")
        XCTAssertEqual(w.space(work)?.bookmarks.count, 1)
        XCTAssertNil(w.bookmark(for: url, in: client))
        XCTAssertEqual(w.bookmark(for: url, in: work)?.title, "Linear")
        w.removeBookmark(id, in: work)
        XCTAssertNil(w.bookmark(for: url, in: work))
    }

    func testOnlyThePathsTrailingSlashIsTheSamePage() throws {
        var w = Workspace.onFigma()
        let work = w.spaces[0].id
        func add(_ text: String) throws -> UUID? {
            w.addBookmark(try XCTUnwrap(URL(string: text)), title: text, in: work)
        }
        let docs = try add("https://example.test/docs/")
        XCTAssertEqual(try add("https://example.test/docs"), docs, "a slash at the end of the path changes nothing")
        let next = try add("https://example.test/?next=/a/")
        XCTAssertNotEqual(try add("https://example.test/?next=/a"), next, "one in the query is part of the link")
        let route = try add("https://example.test/app#/home/")
        XCTAssertNotEqual(try add("https://example.test/app#/home"), route, "so is one in the fragment")
        XCTAssertEqual(w.space(work)?.bookmarks.count, 5)
    }
}
