import XCTest
@testable import PadCore

/// Arrange Tabs By: names or sites, the pinned tabs first, splits whole.
final class ArrangeTests: XCTestCase {
    private func space(_ titles: [(String, String)]) throws -> (Workspace, UUID, [UUID]) {
        var w = Workspace.onFigma()
        let work = w.spaces[0].id
        w.spaces[0].tabs = []
        var ids: [UUID] = []
        for (title, address) in titles {
            ids.append(try XCTUnwrap(w.openTab(URL(string: address), in: work)))
            if let index = w.spaces[0].tabs.firstIndex(where: { $0.id == ids.last }) {
                w.spaces[0].tabs[index].title = title
            }
        }
        return (w, work, ids)
    }

    func testByTitleKeepsPinnedFirstAndSplitsTogether() throws {
        var (w, work, ids) = try space([("Zeta", "https://z.test/"), ("Alpha", "https://a.test/"),
                                        ("Mid", "https://m.test/"), ("Beta", "https://b.test/")])
        XCTAssertTrue(w.pin(ids[2]), "Mid is pinned")
        // Zeta and Alpha side by side, Zeta on the left.
        XCTAssertTrue(w.split(ids[0], with: ids[1]))
        XCTAssertEqual(w.spaces[0].splits.count, 1)
        w.arrangeTabs(in: work, by: .title)
        let titles = w.spaces[0].tabs.map(\.title)
        XCTAssertEqual(titles.first, "Mid", "the pinned tab stays first")
        let left = w.spaces[0].splits.first.flatMap { split in w.spaces[0].tabs.first { $0.id == split.left }?.title }
        XCTAssertEqual(titles, left == "Zeta" ? ["Mid", "Beta", "Zeta", "Alpha"] : ["Mid", "Alpha", "Zeta", "Beta"],
                       "the split goes by its left tab, its two together")
    }

    func testByWebsiteGroupsASitesTabsAndPutsEmptyTabsLast() throws {
        var (w, work, _) = try space([("Docs", "https://docs.b.test/"), ("Blank", ""), ("Home", "https://www.a.test/"),
                                      ("Issues", "https://b.test/issues")])
        w.arrangeTabs(in: work, by: .website)
        XCTAssertEqual(w.spaces[0].tabs.map(\.title), ["Home", "Docs", "Issues", "Blank"])
    }
}
