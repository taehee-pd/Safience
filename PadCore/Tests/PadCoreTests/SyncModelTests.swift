import XCTest
@testable import PadCore

final class SyncModelTests: XCTestCase {
    private func link(_ title: String, _ address: String) throws -> Bookmark {
        Bookmark(title: title, url: try XCTUnwrap(URL(string: address)))
    }

    /// A synced space: Figma and Linear at the top, a folder holding GitHub.
    private func workspace() throws -> Workspace {
        var space = Space(name: "Work", symbol: "briefcase", bookmarks: [
            try link("Figma", "https://figma.com"),
            Bookmark(folder: "Code", children: [try link("GitHub", "https://github.com")]),
            try link("Linear", "https://linear.app"),
        ])
        space.cloudID = UUID()
        return Workspace(spaces: [space])
    }

    func testBookmarksGoToRecordsAndComeBackTheSame() throws {
        let w = try workspace()
        let mirror = SyncPlan.records(of: w, keeping: SyncMirror())
        XCTAssertEqual(mirror.bookmarks.count, 4, "a record for each bookmark and folder")
        let cloud = try XCTUnwrap(w.spaces[0].cloudID?.uuidString)
        XCTAssertEqual(SyncPlan.tree(of: cloud, in: mirror), w.spaces[0].bookmarks)
        let folder = try XCTUnwrap(w.spaces[0].bookmarks[1].id.uuidString)
        XCTAssertEqual(mirror.bookmarks.values.filter { $0.parent == folder }.count, 1)
    }

    func testMovingOneBookmarkRewritesOneRecord() throws {
        var w = try workspace()
        let before = SyncPlan.records(of: w, keeping: SyncMirror())
        // Linear to the front.
        let linear = w.spaces[0].bookmarks.remove(at: 2)
        w.spaces[0].bookmarks.insert(linear, at: 0)
        let after = SyncPlan.records(of: w, keeping: before)
        let changes = SyncPlan.changes(from: before, to: after)
        XCTAssertEqual(changes.save, [linear.id.uuidString])
        XCTAssertEqual(changes.delete, [])
        XCTAssertEqual(SyncPlan.tree(of: try XCTUnwrap(w.spaces[0].cloudID?.uuidString), in: after), w.spaces[0].bookmarks)
    }

    func testRemovingAFolderRemovesWhatIsInIt() throws {
        var w = try workspace()
        let before = SyncPlan.records(of: w, keeping: SyncMirror())
        w.spaces[0].bookmarks.remove(at: 1)
        let changes = SyncPlan.changes(from: before, to: SyncPlan.records(of: w, keeping: before))
        XCTAssertEqual(changes.delete.count, 2, "the folder and GitHub")
        XCTAssertEqual(changes.save, [])
    }

    func testPositionsKeepTheLongestRunInOrderAndFitTheRestBetween() {
        let previous = ["a": 1.0, "b": 2.0, "c": 3.0, "d": 4.0]
        let places = SyncPlan.positions(["d", "a", "b", "c", "x"], previous: previous)
        XCTAssertEqual(Array(places[1...3]), [1, 2, 3], "a, b and c keep theirs")
        XCTAssertLessThan(places[0], 1, "d goes before a")
        XCTAssertGreaterThan(places[4], 3, "x goes after c")
        XCTAssertEqual(SyncPlan.positions([], previous: [:]), [])
        let between = SyncPlan.positions(["a", "x", "y", "b"], previous: previous)
        XCTAssertTrue(between[0] < between[1] && between[1] < between[2] && between[2] < between[3])
        XCTAssertEqual(SyncPlan.positions(["a", "b"], previous: ["a": 1, "b": 1 + 1e-12]), [1, 2], "no room left: numbered again")
    }

    func testABookmarkWhoseFolderHasNotArrivedWaitsAtTheTopAndStaysInIt() throws {
        let space = UUID().uuidString
        let child = SyncBookmark(id: UUID().uuidString, space: space, parent: UUID().uuidString, position: 1,
                                 title: "GitHub", url: "https://github.com")
        var mirror = SyncMirror()
        mirror.spaces[space] = SyncSpace(id: space, name: "Work", symbol: "briefcase", color: "blue")
        mirror.bookmarks[child.id] = child
        var w = Workspace(spaces: [])
        SyncPlan.apply(mirror, to: &w)
        XCTAssertEqual(w.spaces.first?.bookmarks.map(\.title), ["GitHub"], "shown at the top meanwhile")
        let again = SyncPlan.records(of: w, keeping: mirror)
        XCTAssertEqual(again.bookmarks[child.id]?.parent, child.parent, "and not sent back as moved")
        XCTAssertEqual(SyncPlan.changes(from: mirror, to: again).save, [])
        let folder = SyncBookmark(id: try XCTUnwrap(child.parent), space: space, parent: nil, position: 1, title: "Code", url: nil)
        mirror.bookmarks[folder.id] = folder
        SyncPlan.apply(mirror, to: &w)
        XCTAssertEqual(w.spaces.first?.bookmarks.first?.children?.map(\.title), ["GitHub"], "in its folder once it comes")
    }

    func testTwoFoldersInsideEachOtherAreBrokenAtTheTop() {
        let space = UUID().uuidString
        let a = UUID().uuidString, b = UUID().uuidString
        var mirror = SyncMirror()
        mirror.bookmarks[a] = SyncBookmark(id: a, space: space, parent: b, position: 1, title: "A", url: nil)
        mirror.bookmarks[b] = SyncBookmark(id: b, space: space, parent: a, position: 1, title: "B", url: nil)
        let tree = SyncPlan.tree(of: space, in: mirror)
        XCTAssertEqual(tree.count, 1, "one of them at the top")
        XCTAssertEqual(tree.first?.children?.count, 1, "the other in it")
    }

    func testWhatComesInChangesTheSpaceAddsSpacesAndReportsRemovedOnes() throws {
        var w = try workspace()
        var mirror = SyncPlan.records(of: w, keeping: SyncMirror())
        let cloud = try XCTUnwrap(w.spaces[0].cloudID?.uuidString)
        mirror.spaces[cloud]?.name = "Studio"
        mirror.spaces[cloud]?.color = "pink"
        let client = UUID().uuidString
        mirror.spaces[client] = SyncSpace(id: client, name: "Client", symbol: "person.2", color: "orange")
        let pin = UUID().uuidString
        mirror.pinned[pin] = SyncPinned(id: pin, space: client, position: 1, title: "Figma", url: "https://figma.com")
        SyncPlan.apply(mirror, to: &w)
        XCTAssertEqual(w.spaces[0].name, "Studio")
        XCTAssertEqual(w.spaces[0].color, .pink)
        let added = try XCTUnwrap(w.spaces.first { $0.cloudID?.uuidString == client })
        XCTAssertEqual(added.tabs.filter(\.isPinned).map(\.cloudID?.uuidString), [pin], "its pinned tab, known by iCloud's id")
        XCTAssertEqual(added.tabs.filter { !$0.isPinned }.count, 1, "and one empty tab")
        let applied = SyncPlan.apply(mirror, to: &w, deleted: [cloud])
        XCTAssertEqual(applied.removedSpaces, [w.spaces[0].id], "for the app to remove, with its sign-ins")
    }

    func testAPinnedTabRemovedElsewhereIsUnpinnedHereToBeClosed() throws {
        var w = try workspace()
        w.spaces[0].tabs = [TabRecord(url: URL(string: "https://figma.com"), pinned: URL(string: "https://figma.com")),
                            TabRecord(url: URL(string: "https://linear.app"))]
        let pinned = w.spaces[0].tabs[0].id
        var mirror = SyncPlan.records(of: w, keeping: SyncMirror())
        XCTAssertEqual(mirror.pinned.keys.first, pinned.uuidString, "its own id, when iCloud gave it none")
        mirror.pinned = [:]
        let applied = SyncPlan.apply(mirror, to: &w)
        XCTAssertEqual(applied.removedTabs, [pinned])
        XCTAssertFalse(w.spaces[0].tabs.contains { $0.isPinned })
    }

    func testAPinnedTabsTitleIsThePinnedPagesNotWhereverItWent() throws {
        var w = try workspace()
        var tab = TabRecord(url: URL(string: "https://figma.com"), title: "Figma", pinned: URL(string: "https://figma.com"))
        w.spaces[0].tabs = [tab]
        let before = SyncPlan.records(of: w, keeping: SyncMirror())
        tab.url = URL(string: "https://figma.com/file/1")
        tab.title = "Onboarding v3"
        w.spaces[0].tabs = [tab]
        XCTAssertEqual(SyncPlan.changes(from: before, to: SyncPlan.records(of: w, keeping: before)).save, [],
                       "browsing in a pinned tab writes nothing")
    }

    func testJoiningMatchesSpacesByNameKeepsBothSetsAndDeletesNothing() throws {
        var w = Workspace(spaces: [
            Space(name: "Work", symbol: "briefcase", tabs: [TabRecord(url: URL(string: "https://figma.com"), pinned: URL(string: "https://figma.com"))],
                  bookmarks: [try link("Figma", "https://figma.com")]),
            Space(name: "Home", symbol: "house"),
        ])
        var theirs = Workspace(spaces: [
            Space(name: "work ", symbol: "paintpalette", color: .teal, bookmarks: [try link("Linear", "https://linear.app")]),
            Space(name: "Client", symbol: "person.2"),
        ])
        theirs.spaces[0].cloudID = UUID()
        theirs.spaces[1].cloudID = UUID()
        theirs.spaces[0].tabs = [TabRecord(url: URL(string: "https://figma.com/"), pinned: URL(string: "https://figma.com/"))]
        let remote = SyncPlan.records(of: theirs, keeping: SyncMirror())
        let result = SyncPlan.join(&w, remote: remote)
        let work = try XCTUnwrap(w.spaces.first { $0.cloudID == theirs.spaces[0].cloudID })
        XCTAssertEqual(work.color, .teal, "iCloud's colour and icon")
        XCTAssertEqual(Set(work.bookmarks.compactMap(\.url?.host)), ["linear.app", "figma.com"], "both sets of bookmarks")
        XCTAssertEqual(work.tabs.filter(\.isPinned).count, 1, "the same pinned address is one pinned tab")
        XCTAssertNotNil(w.spaces.first { $0.name == "Home" }?.cloudID, "a space with no match comes in as new")
        XCTAssertNotNil(w.spaces.first { $0.cloudID == theirs.spaces[1].cloudID }, "iCloud's other space comes in")
        let changes = SyncPlan.changes(from: remote, to: result)
        XCTAssertEqual(changes.delete, [], "joining never deletes")
        XCTAssertTrue(changes.save.contains(try XCTUnwrap(w.spaces.first { $0.name == "Home" }?.cloudID?.uuidString)))
    }

    func testDeviceTabsLeaveOutSignInPagesAndCredentials() throws {
        var w = try workspace()
        w.spaces[0].tabs = [
            TabRecord(url: URL(string: "https://figma.com/file/1"), title: "Onboarding"),
            TabRecord(url: URL(string: "https://accounts.google.com/signin"), title: "Sign in"),
            TabRecord(url: URL(string: "https://app.example.com/callback?code=abc&state=1"), title: "Callback"),
            TabRecord(url: URL(string: "https://example.com/#access_token=abc"), title: "Implicit"),
            TabRecord(url: nil),
        ]
        let tabs = SyncPlan.deviceTabs(of: w, device: "D", deviceName: "iPhone", now: Date())
        XCTAssertEqual(tabs.first?.tabs.map(\.title), ["Onboarding"])
        XCTAssertEqual(tabs.first?.id, "tabs.D.\(try XCTUnwrap(w.spaces[0].cloudID?.uuidString))")
    }

    func testRecordsRoundTripThroughTheirFields() throws {
        let tabs = SyncDeviceTabs(device: "D", deviceName: "Mac", browser: "Chrome", space: "S",
                                  updated: Date(timeIntervalSince1970: 1_000), tabs: [SyncTab(url: "https://a.com", title: "A", group: "Work")])
        var mirror = SyncMirror()
        XCTAssertTrue(mirror.take(tabs.record))
        XCTAssertEqual(mirror.deviceTabs[tabs.id], tabs)
        let json = try XCTUnwrap(tabs.record.fields["tabs"]?.string)
        XCTAssertTrue(json.contains("\"u\""), "short keys, as the extension writes them")
        let folder = SyncBookmark(id: "F", space: "S", parent: nil, position: 2, title: "Code", url: nil)
        XCTAssertNil(folder.record.fields["url"], "a folder has no address")
        XCTAssertNil(folder.record.fields["parent"], "and at the top, no parent")
        XCTAssertEqual(SyncBookmark(folder.record), folder)
        XCTAssertFalse(mirror.take(SyncRecord(kind: .bookmark, name: "X", fields: [:])), "a record without its space is left out")
    }

    func testTheKeyValueStoresSpacesBecomeRecordsOnce() throws {
        let legacy = CloudSpace(id: UUID(), name: "Work", symbol: "briefcase", color: .teal,
                                bookmarks: [Bookmark(folder: "Code", children: [try link("GitHub", "https://github.com")])])
        let gone = CloudSpace(id: UUID(), name: "", symbol: "", color: .gray, bookmarks: [], deleted: true)
        let mirror = SyncPlan.mirror(fromLegacy: [legacy, gone])
        XCTAssertEqual(mirror.spaces.count, 1, "a removed space stays removed")
        XCTAssertEqual(mirror.bookmarks.count, 2)
        XCTAssertEqual(SyncPlan.tree(of: legacy.id.uuidString, in: mirror), legacy.bookmarks)
    }

    func testAFileFromBeforeSyncStillReads() throws {
        let w = Workspace(spaces: [Space(name: "Work", symbol: "briefcase", tabs: [TabRecord(url: nil)])])
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(w)) as? [String: Any])
        var spaces = try XCTUnwrap(json["spaces"] as? [[String: Any]])
        spaces[0]["cloudID"] = nil
        json["spaces"] = spaces
        let read = try JSONDecoder().decode(Workspace.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(read.spaces[0].cloudID)
        XCTAssertNil(read.spaces[0].tabs[0].cloudID)
    }
}
