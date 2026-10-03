import XCTest
@testable import PadCore

final class SplitTests: XCTestCase {
    /// A space with tabs a, b and c, in that order, and its id.
    private func three() throws -> (Workspace, UUID, [UUID]) {
        var w = Workspace(spaces: [Space(name: "Work", symbol: "briefcase")])
        let space = w.spaces[0].id
        let ids = try (0..<3).map { n in try XCTUnwrap(w.openTab(URL(string: "https://example.test/\(n)"), in: space)) }
        return (w, space, ids)
    }

    private func order(_ w: Workspace, _ space: UUID) -> [UUID] {
        w.space(space)?.tabs.map(\.id) ?? []
    }

    func testASplitsTabsSitSideBySideLeftFirst() throws {
        var (w, space, t) = try three()
        XCTAssertTrue(w.split(t[0], with: t[2]))
        XCTAssertEqual(order(w, space), [t[0], t[2], t[1]])
        XCTAssertEqual(w.split(containing: t[2]), Split(left: t[0], right: t[2]))
        XCTAssertEqual(w.split(containing: t[0])?.partner(of: t[0]), t[2])
    }

    func testATabIsInOneSplitAtMost() throws {
        var (w, space, t) = try three()
        w.split(t[0], with: t[1])
        w.split(t[2], with: t[1])
        XCTAssertEqual(w.space(space)?.splits, [Split(left: t[2], right: t[1])])
        XCTAssertNil(w.split(containing: t[0]))
        XCTAssertEqual(order(w, space), [t[0], t[2], t[1]])
    }

    func testPinnedTabsAreNeverSplit() throws {
        var (w, _, t) = try three()
        w.pin(t[0])
        XCTAssertFalse(w.split(t[0], with: t[1]))
        XCTAssertFalse(w.split(t[1], with: t[0]))
        XCTAssertNil(w.splitWithNewTab(t[0]))
        w.split(t[1], with: t[2])
        w.pin(t[1])
        XCTAssertNil(w.split(containing: t[2]), "pinning a pane ends its split")
    }

    func testClosingAPaneLeavesTheOtherOnScreen() throws {
        var (w, space, t) = try three()
        w.split(t[0], with: t[1])
        w.select(t[1])
        XCTAssertEqual(w.closeTab(t[1]), t[0])
        XCTAssertEqual(w.space(space)?.splits, [])
        w.split(t[0], with: t[2])
        w.select(t[0])
        XCTAssertEqual(w.closeTab(t[0]), t[2], "the pane beside it, not the tab after it")
    }

    func testANewTabInASplitIsTheOneTypedInto() throws {
        var (w, space, t) = try three()
        let new = try XCTUnwrap(w.splitWithNewTab(t[0]))
        XCTAssertEqual(w.space(space)?.selected, new)
        XCTAssertEqual(order(w, space), [t[0], new, t[1], t[2]])
        XCTAssertEqual(w.split(containing: new), Split(left: t[0], right: new))
    }

    func testATabOpenedFromTheLeftPaneGoesAfterThePair() throws {
        var (w, space, t) = try three()
        w.split(t[0], with: t[1])
        let opened = try XCTUnwrap(w.openTab(nil, in: space, after: t[0]))
        XCTAssertEqual(order(w, space), [t[0], t[1], opened, t[2]])
    }

    func testASplitMovesAsOne() throws {
        var (w, space, t) = try three()
        w.split(t[1], with: t[2])
        w.moveTab(t[2], toIndex: 0)
        XCTAssertEqual(order(w, space), [t[1], t[2], t[0]])
        w.moveTab(t[0], toIndex: 0)
        XCTAssertEqual(order(w, space), [t[0], t[1], t[2]])
    }

    func testMovingAPaneToAnotherSpaceEndsTheSplit() throws {
        var (w, space, t) = try three()
        let other = w.addSpace(named: "Client")
        w.split(t[0], with: t[1])
        w.moveTab(t[1], to: other)
        XCTAssertEqual(w.space(space)?.splits, [])
    }

    func testSidesSwapAndTheDividerStaysWhereItWas() throws {
        var (w, space, t) = try three()
        w.split(t[0], with: t[1])
        w.setSplitRatio(t[0], to: 0.3)
        w.swapSides(t[1])
        XCTAssertEqual(order(w, space), [t[1], t[0], t[2]])
        let split = try XCTUnwrap(w.split(containing: t[0]))
        XCTAssertEqual(split.left, t[1])
        XCTAssertEqual(split.ratio, 0.7, accuracy: 0.0001)
    }

    func testTheDividerKeepsAQuarterForEachPane() throws {
        var (w, _, t) = try three()
        w.split(t[0], with: t[1])
        w.setSplitRatio(t[0], to: 0.05)
        XCTAssertEqual(w.split(containing: t[0])?.ratio, 0.25)
        w.setSplitRatio(t[0], to: 2)
        XCTAssertEqual(w.split(containing: t[0])?.ratio, 0.75)
    }

    func testSeparatingKeepsBothTabsWhereTheyAre() throws {
        var (w, space, t) = try three()
        w.split(t[0], with: t[2])
        w.separate(t[2])
        XCTAssertEqual(w.space(space)?.splits, [])
        XCTAssertEqual(order(w, space), [t[0], t[2], t[1]])
    }

    func testRepairPutsRightABrokenFile() throws {
        var (w, space, t) = try three()
        let ghost = UUID()
        w.spaces[0].splits = [Split(left: t[0], right: t[2]), Split(left: t[1], right: ghost), Split(left: t[2], right: t[1])]
        w.repair()
        XCTAssertEqual(w.space(space)?.splits, [Split(left: t[0], right: t[2])])
        XCTAssertEqual(order(w, space), [t[0], t[2], t[1]])
    }

    func testAFileFromBeforeSplitsStillReads() throws {
        let (w, _, _) = try three()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(w)) as? [String: Any])
        var spaces = try XCTUnwrap(json["spaces"] as? [[String: Any]])
        spaces[0]["splits"] = nil
        json["spaces"] = spaces
        let old = try JSONSerialization.data(withJSONObject: json)
        XCTAssertEqual(try JSONDecoder().decode(Workspace.self, from: old), w)
    }
}
