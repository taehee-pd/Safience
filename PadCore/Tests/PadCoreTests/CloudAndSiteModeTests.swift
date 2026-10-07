import XCTest
@testable import PadCore

final class SiteModeTests: XCTestCase {
    func testTheWindowsSizeChooses() {
        // Points: an iPhone 17 Pro either way up, the Duo folded and
        // unfolded (third-party figures), an iPad Pro, a third of one.
        XCTAssertEqual(SiteMode.choose(host: "figma.com", width: 402, height: 874, overrides: [:]), .mobile)
        XCTAssertEqual(SiteMode.choose(host: "figma.com", width: 874, height: 402, overrides: [:]), .mobile)
        XCTAssertEqual(SiteMode.choose(host: "figma.com", width: 466, height: 678, overrides: [:]), .mobile)
        XCTAssertEqual(SiteMode.choose(host: "figma.com", width: 626, height: 890, overrides: [:]), .desktop)
        XCTAssertEqual(SiteMode.choose(host: "figma.com", width: 1032, height: 1376, overrides: [:]), .desktop)
        XCTAssertEqual(SiteMode.choose(host: "figma.com", width: 320, height: 1376, overrides: [:]), .mobile)
    }

    func testASitesOwnChoiceWins() {
        let overrides: [String: SiteMode] = ["figma.com": .desktop, "linear.app": .mobile]
        XCTAssertEqual(SiteMode.choose(host: "www.figma.com", width: 402, height: 874, overrides: overrides), .desktop)
        XCTAssertEqual(SiteMode.choose(host: "linear.app", width: 1032, height: 1376, overrides: overrides), .mobile)
        XCTAssertEqual(SiteMode.choose(host: nil, width: 402, height: 874, overrides: overrides), .mobile)
    }

    func testMobileUserAgentsAreSafarisOwn() {
        XCTAssertEqual(Identity.mobileUserAgent(major: 27, minor: 0, pad: false),
                       "Mozilla/5.0 (iPhone; CPU iPhone OS 27_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/27.0 Mobile/15E148 Safari/604.1")
        XCTAssertEqual(Identity.mobileUserAgent(major: 27, minor: 1, patch: 2, pad: true),
                       "Mozilla/5.0 (iPad; CPU OS 27_1_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/27.1.2 Mobile/15E148 Safari/604.1")
    }

    func testPreferencesFromBeforeSiteModesAndSyncStillRead() throws {
        let old = try XCTUnwrap(#"{"layout":"compact","pageCursors":true}"#.data(using: .utf8))
        let preferences = try JSONDecoder().decode(Preferences.self, from: old)
        XCTAssertEqual(preferences.siteModes, [:])
        XCTAssertFalse(preferences.iCloudSync)
    }
}

final class CloudSyncTests: XCTestCase {
    private func link(_ title: String, _ address: String) throws -> Bookmark {
        Bookmark(title: title, url: try XCTUnwrap(URL(string: address)))
    }

    func testJoiningMatchesSpacesByNameAndKeepsBothDevicesBookmarks() throws {
        var w = Workspace(spaces: [Space(name: "Work", symbol: "briefcase", bookmarks: [try link("Figma", "https://figma.com")]),
                                   Space(name: "Home", symbol: "house")])
        let remoteWork = CloudSpace(id: UUID(), name: "work ", symbol: "paintpalette", color: .teal,
                                    bookmarks: [try link("Linear", "https://linear.app")])
        let remoteClient = CloudSpace(id: UUID(), name: "Client", symbol: "person.2", color: .orange, bookmarks: [])
        let writes = CloudSync.join(&w, remote: [remoteWork, remoteClient])
        let work = try XCTUnwrap(w.spaces.first { $0.cloudID == remoteWork.id })
        XCTAssertEqual(work.color, .teal, "iCloud's colour and icon")
        XCTAssertEqual(work.bookmarks.compactMap(\.url?.host), ["linear.app", "figma.com"], "both devices' bookmarks")
        XCTAssertNotNil(w.spaces.first { $0.name == "Home" }?.cloudID, "a space with no match comes in as new")
        let client = try XCTUnwrap(w.spaces.first { $0.cloudID == remoteClient.id })
        XCTAssertEqual(client.tabs.count, 1, "a space new to this device comes with one empty tab")
        XCTAssertEqual(Set(writes.map(\.name)), ["work ", "Home"], "what changed goes back: the joined space and the new one")
    }

    func testTwoSpacesWithOneNameDontBothJoinOne() throws {
        var w = Workspace(spaces: [Space(name: "Work", symbol: "briefcase"), Space(name: "Work", symbol: "hammer")])
        let remote = CloudSpace(id: UUID(), name: "Work", symbol: "briefcase", color: .blue, bookmarks: [])
        CloudSync.join(&w, remote: [remote])
        XCTAssertEqual(w.spaces.filter { $0.cloudID == remote.id }.count, 1)
        XCTAssertEqual(Set(w.spaces.compactMap(\.cloudID)).count, 2)
    }

    func testWhatComesInReplacesWhatIsHereAndARemovedSpaceIsReported() throws {
        var w = Workspace(spaces: [Space(name: "Work", symbol: "briefcase"), Space(name: "Old", symbol: "folder")])
        let work = UUID(), old = UUID()
        w.spaces[0].cloudID = work
        w.spaces[1].cloudID = old
        let renamed = CloudSpace(id: work, name: "Studio", symbol: "paintpalette", color: .pink,
                                 bookmarks: [try link("Figma", "https://figma.com")])
        let removed = CloudSync.apply([renamed, .tombstone(old)], to: &w)
        XCTAssertEqual(w.spaces[0].name, "Studio")
        XCTAssertEqual(w.spaces[0].bookmarks.count, 1)
        XCTAssertEqual(removed, [w.spaces[1].id], "the app removes it, with its sign-ins")
    }

    func testChangesWriteWhatChangedAndTombstonesWhatWentAway() throws {
        var old = Workspace(spaces: [Space(name: "Work", symbol: "briefcase"), Space(name: "Home", symbol: "house")])
        old.spaces[0].cloudID = UUID()
        old.spaces[1].cloudID = UUID()
        var new = old
        _ = new.addBookmark(try XCTUnwrap(URL(string: "https://figma.com")), title: "Figma", in: new.spaces[0].id)
        let home = try XCTUnwrap(new.spaces[1].cloudID)
        _ = new.removeSpace(new.spaces[1].id)
        let writes = CloudSync.changes(from: old, to: new)
        XCTAssertEqual(writes.count, 2)
        XCTAssertEqual(writes.first?.bookmarks.count, 1)
        XCTAssertEqual(writes.last, .tombstone(home))
        XCTAssertEqual(CloudSync.changes(from: new, to: new), [], "nothing changed, nothing written")
    }

    func testTabsAndSignInsNeverGoToICloud() throws {
        var space = Space(name: "Work", symbol: "briefcase", tabs: [TabRecord(url: URL(string: "https://figma.com"))])
        space.cloudID = UUID()
        let data = try JSONEncoder().encode(try XCTUnwrap(space.cloud))
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(text.contains("figma.com"), "a tab's address stays on the device")
        XCTAssertFalse(text.contains(space.id.uuidString), "nor the id that names its sign-ins")
    }

    func testAFileFromBeforeSyncStillReads() throws {
        let w = Workspace(spaces: [Space(name: "Work", symbol: "briefcase")])
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(w)) as? [String: Any])
        var spaces = try XCTUnwrap(json["spaces"] as? [[String: Any]])
        spaces[0]["cloudID"] = nil
        json["spaces"] = spaces
        let read = try JSONDecoder().decode(Workspace.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(read.spaces[0].cloudID)
    }
}
