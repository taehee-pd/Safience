import XCTest
@testable import PadCore

/// Bookmark folders: made, renamed, and bookmarks moved in and out of them.
final class FolderTests: XCTestCase {
    private func url(_ text: String) throws -> URL {
        try XCTUnwrap(URL(string: text))
    }

    func testAFolderHoldsBookmarksMovedIntoIt() throws {
        var w = Workspace.starting()
        let work = w.spaces[0].id
        let linear = try XCTUnwrap(w.addBookmark(try url("https://linear.app/"), title: "Linear", in: work))
        let design = try XCTUnwrap(w.addFolder(named: "Design", in: nil, of: work))
        w.moveBookmark(linear, into: design, in: work)
        XCTAssertEqual(w.space(work)?.bookmarks.map(\.id), [design], "the link left the top level")
        XCTAssertEqual(Bookmarks.find(design, in: w.space(work)?.bookmarks ?? [])?.children?.map(\.id), [linear])
        XCTAssertEqual(w.bookmark(for: try url("https://linear.app"), in: work)?.id, linear, "still the same bookmark, at depth")
        w.moveBookmark(linear, into: nil, in: work)
        XCTAssertEqual(w.space(work)?.bookmarks.map(\.id), [design, linear], "back at the top level, at the end")
        w.removeBookmark(design, in: work)
        XCTAssertEqual(w.space(work)?.bookmarks.map(\.id), [linear])
    }

    func testAFolderNeverGoesIntoItselfOrItsOwn() throws {
        var w = Workspace.starting()
        let work = w.spaces[0].id
        let outer = try XCTUnwrap(w.addFolder(named: "Outer", in: nil, of: work))
        let inner = try XCTUnwrap(w.addFolder(named: "Inner", in: outer, of: work))
        XCTAssertEqual(Bookmarks.find(outer, in: w.space(work)?.bookmarks ?? [])?.children?.map(\.id), [inner])
        let before = w
        w.moveBookmark(outer, into: outer, in: work)
        w.moveBookmark(outer, into: inner, in: work)
        XCTAssertEqual(w, before, "a folder inside itself would be lost")
        let link = try XCTUnwrap(w.addBookmark(try url("https://a.test/"), title: "A", in: work))
        w.moveBookmark(inner, into: link, in: work)
        XCTAssertEqual(Bookmarks.find(outer, in: w.space(work)?.bookmarks ?? [])?.children?.map(\.id), [inner],
                       "a link is not a folder to move into")
    }

    func testNamesAreTrimmedAndNeverEmpty() throws {
        var w = Workspace.starting()
        let work = w.spaces[0].id
        let folder = try XCTUnwrap(w.addFolder(named: "  ", in: nil, of: work))
        XCTAssertEqual(Bookmarks.find(folder, in: w.space(work)?.bookmarks ?? [])?.title, "New Folder")
        w.renameBookmark(folder, to: " Reading ", in: work)
        XCTAssertEqual(Bookmarks.find(folder, in: w.space(work)?.bookmarks ?? [])?.title, "Reading")
        w.renameBookmark(folder, to: "", in: work)
        XCTAssertEqual(Bookmarks.find(folder, in: w.space(work)?.bookmarks ?? [])?.title, "Reading", "an empty name changes nothing")
        XCTAssertNil(w.addFolder(named: "Lost", in: UUID(), of: work), "no such parent")
    }
}
