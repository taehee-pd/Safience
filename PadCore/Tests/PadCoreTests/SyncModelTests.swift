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

    func testAPinnedTabRemovedElsewhereKeepsItsLocalPageAndSelection() throws {
        var w = try workspace()
        w.spaces[0].tabs = [TabRecord(url: URL(string: "https://figma.com"), pinned: URL(string: "https://figma.com")),
                            TabRecord(url: URL(string: "https://linear.app"))]
        let pinned = w.spaces[0].tabs[0].id
        w.spaces[0].selected = pinned
        let page = URL(string: "https://figma.com/file/draft")
        w.spaces[0].tabs[0].url = page
        w.spaces[0].tabs[0].title = "Unsaved draft"
        var mirror = SyncPlan.records(of: w, keeping: SyncMirror())
        XCTAssertEqual(mirror.pinned.keys.first, pinned.uuidString, "its own id, when iCloud gave it none")
        mirror.pinned = [:]
        let applied = SyncPlan.apply(mirror, to: &w)
        XCTAssertEqual(applied.unpinnedTabs, [pinned])
        XCTAssertFalse(w.spaces[0].tabs.contains { $0.isPinned })
        XCTAssertEqual(w.spaces[0].selected, pinned)
        XCTAssertEqual(w.tab(pinned)?.url, page)
        XCTAssertEqual(w.tab(pinned)?.title, "Unsaved draft")
        XCTAssertEqual(w.spaces[0].tabs.count, 2)
        XCTAssertNil(w.tab(pinned)?.cloudID)
        XCTAssertTrue(SyncPlan.apply(mirror, to: &w).unpinnedTabs.isEmpty)
        XCTAssertTrue(SyncPlan.records(of: w, keeping: mirror).pinned.isEmpty, "does not re-upload the removed pin")
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

    func testJoiningKeepsSameNameSpacesSeparateAndDeletesNothing() throws {
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
        XCTAssertEqual(Set(work.bookmarks.compactMap(\.url?.host)), ["linear.app"], "remote bookmarks stay in their own space")
        XCTAssertEqual(work.tabs.filter(\.isPinned).count, 1)
        let local = try XCTUnwrap(w.spaces.first { $0.name == "Work" })
        XCTAssertNotEqual(local.cloudID, work.cloudID)
        XCTAssertEqual(local.color, .blue)
        XCTAssertEqual(local.bookmarks.compactMap(\.url?.host), ["figma.com"])
        XCTAssertEqual(w.spaces.count, 4, "same names do not imply the same client")
        XCTAssertNotNil(w.spaces.first { $0.name == "Home" }?.cloudID, "a space with no match comes in as new")
        XCTAssertNotNil(w.spaces.first { $0.cloudID == theirs.spaces[1].cloudID }, "iCloud's other space comes in")
        let changes = SyncPlan.changes(from: remote, to: result)
        XCTAssertEqual(changes.delete, [], "joining never deletes")
        XCTAssertTrue(changes.save.contains(try XCTUnwrap(w.spaces.first { $0.name == "Home" }?.cloudID?.uuidString)))
    }

    func testIdentityMatchSurvivesRenameAndRepeatedSyncEnablement() throws {
        var local = try workspace()
        var other = local
        other.spaces[0].name = "Renamed Client"
        let cloud = try XCTUnwrap(local.spaces[0].cloudID)
        let localID = local.spaces[0].id
        var remote = SyncPlan.records(of: other, keeping: SyncMirror())
        for _ in 0..<3 { remote = SyncPlan.join(&local, remote: remote) }
        XCTAssertEqual(local.spaces.count, 1)
        XCTAssertEqual(local.spaces[0].id, localID)
        XCTAssertEqual(local.spaces[0].cloudID, cloud)
        XCTAssertEqual(local.spaces[0].name, "Renamed Client")
    }

    func testDuplicateSameNameRemoteSpacesNeverAdoptALocalClient() {
        var local = Workspace.starting()
        let localID = local.spaces[0].id
        var remote = SyncMirror()
        for _ in 0..<2 {
            let id = UUID().uuidString
            remote.spaces[id] = SyncSpace(id: id, name: " work ", symbol: "house", color: "pink")
        }
        let joined = SyncPlan.join(&local, remote: remote)
        XCTAssertEqual(local.spaces.count, 3)
        XCTAssertEqual(local.spaces.first { $0.id == localID }?.name, "Work")
        XCTAssertEqual(Set(local.spaces.compactMap(\.cloudID)).count, 3)
        XCTAssertTrue(SyncPlan.changes(from: remote, to: joined).delete.isEmpty)
    }

    func testSignInPagesAndCredentialsNeverLeaveTheDevice() throws {
        let shareable = ["https://figma.com/file/1", "https://accounts.google.com/signin",
                         "https://app.example.com/callback?code=abc&state=1", "https://example.com/#access_token=abc"]
            .compactMap(URL.init(string:)).filter(SyncPlan.isShareable)
        XCTAssertEqual(shareable.map(\.absoluteString), ["https://figma.com/file/1"])
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

    // MARK: Chrome extensions, between Macs

    private func local(_ id: String, _ spaces: Set<String>, access: String = "allSites") -> SyncPlan.LocalExtension {
        .init(storeID: id, title: id.uppercased(), siteAccess: access, spaces: spaces)
    }

    private func namer() -> () -> String {
        var count = 0
        return { count += 1; return "r\(count)" }
    }

    func testExtensionRecordsAreEncryptedAndRoundTrip() {
        XCTAssertTrue(SyncKind.extensionItem.isEncrypted && SyncKind.extensionUse.isEncrypted)
        XCTAssertFalse(SyncKind.space.isEncrypted, "the desktop extension reads spaces")
        let item = SyncExtension(id: "R", storeID: "abc", title: "Dark Reader", siteAccess: "onClick")
        let use = SyncExtensionUse(id: "U", extensionRecord: "R", space: "S")
        var mirror = SyncMirror()
        XCTAssertTrue(mirror.take(item.record) && mirror.take(use.record))
        XCTAssertEqual(mirror.extensions["R"], item)
        XCTAssertEqual(mirror.names(in: "S"), ["S", "U"], "a space's uses go with it")
        XCTAssertFalse(mirror.take(SyncRecord(kind: .extensionItem, name: "X", fields: [:])), "no store id, left out")
    }

    func testAMirrorKeptBeforeExtensionsSyncedStillReads() throws {
        let old = #"{"spaces": {}, "bookmarks": {}, "pinned": {}, "deviceTabs": {}}"#
        let mirror = try JSONDecoder().decode(SyncMirror.self, from: Data(old.utf8))
        XCTAssertTrue(mirror.extensions.isEmpty && mirror.extensionUses.isEmpty)
    }

    func testAMacPublishesOnlyItsOwnChanges() {
        var mirror = SyncMirror()
        // Another Mac's extension, which this one hasn't got.
        mirror.extensions["theirs"] = SyncExtension(id: "theirs", storeID: "z", title: "Z", siteAccess: "allSites")
        let first = SyncPlan.publish(from: nil, to: [local("a", ["S1", "S2"])], in: &mirror, name: namer())
        XCTAssertEqual(first.save, ["r1", "r2", "r3"])
        XCTAssertEqual(first.delete, [])
        XCTAssertNotNil(mirror.extensions["theirs"], "what only another Mac has stays")
        // Off in S2, and site access changed.
        let second = SyncPlan.publish(from: [local("a", ["S1", "S2"])], to: [local("a", ["S1"], access: "onClick")], in: &mirror, name: namer())
        XCTAssertEqual(second.save, ["r1"])
        XCTAssertEqual(second.delete, ["r3"])
        XCTAssertEqual(mirror.extensions["r1"]?.siteAccess, "onClick")
        // Removed here: its record and its uses.
        let third = SyncPlan.publish(from: [local("a", ["S1"])], to: [], in: &mirror, name: namer())
        XCTAssertEqual(Set(third.delete), ["r1", "r2"])
        XCTAssertEqual(Array(mirror.extensions.keys), ["theirs"])
    }

    func testAnExtensionAnotherMacHasKeepsItsRecord() {
        var mirror = SyncMirror()
        mirror.extensions["theirs"] = SyncExtension(id: "theirs", storeID: "a", title: "A", siteAccess: "allSites")
        let published = SyncPlan.publish(from: nil, to: [local("a", ["S1"])], in: &mirror, name: namer())
        XCTAssertEqual(published.save, ["r1"], "the same store id: their record, and a use of it")
        XCTAssertEqual(mirror.extensionUses["r1"]?.extensionRecord, "theirs")
        XCTAssertEqual(mirror.extensions.count, 1)
    }

    func testAMacFollowsAnothersChanges() {
        var before = SyncMirror()
        before.extensions["R"] = SyncExtension(id: "R", storeID: "a", title: "A", siteAccess: "allSites")
        before.extensions["Q"] = SyncExtension(id: "Q", storeID: "b", title: "B", siteAccess: "allSites")
        before.extensionUses["U1"] = SyncExtensionUse(id: "U1", extensionRecord: "R", space: "S1")
        var after = before
        after.extensionUses["U1"] = nil
        after.extensionUses["U2"] = SyncExtensionUse(id: "U2", extensionRecord: "R", space: "S2")
        after.extensions["Q"] = nil
        after.extensions["P"] = SyncExtension(id: "P", storeID: "c", title: "C", siteAccess: "allSites")
        let here = [local("a", ["S1"]), local("b", [])]
        let follow = SyncPlan.follow(from: before, to: after, local: here)
        XCTAssertEqual(follow.removed, ["b"], "removed there, removed here")
        XCTAssertEqual(follow.on, [.init(storeID: "a", space: "S2")])
        XCTAssertEqual(follow.off, [.init(storeID: "a", space: "S1")])
        XCTAssertEqual(SyncPlan.offers(in: after, local: here).map(\.storeID), ["c"], "offered, never installed unasked")
        XCTAssertTrue(SyncPlan.follow(from: after, to: after, local: here) == ([], [], []), "nothing changed, nothing to do")
    }

    func testAUseOfASpaceRemovedHereGoesAndOneNotSeenYetStays() throws {
        var w = try workspace()
        let cloud = try XCTUnwrap(w.spaces[0].cloudID?.uuidString)
        var mirror = SyncPlan.records(of: w, keeping: SyncMirror())
        mirror.extensions["R"] = SyncExtension(id: "R", storeID: "a", title: "A", siteAccess: "allSites")
        mirror.extensionUses["U1"] = SyncExtensionUse(id: "U1", extensionRecord: "R", space: cloud)
        mirror.extensionUses["U2"] = SyncExtensionUse(id: "U2", extensionRecord: "R", space: "not-arrived")
        let same = SyncPlan.records(of: w, keeping: mirror)
        XCTAssertEqual(SyncPlan.changes(from: mirror, to: same).save + SyncPlan.changes(from: mirror, to: same).delete, [],
                       "extension records come along as they are")
        w.spaces.removeAll()
        let next = SyncPlan.records(of: w, keeping: mirror)
        XCTAssertNil(next.extensionUses["U1"])
        XCTAssertNotNil(next.extensionUses["U2"], "its space may not have arrived yet")
        XCTAssertTrue(SyncPlan.changes(from: mirror, to: next).delete.contains("U1"))
        XCTAssertEqual(SyncPlan.uses(ofRemoved: ["not-arrived"], in: mirror), ["U2"])
    }

    func testTwoRecordsOfOneExtensionAreOne() {
        var mirror = SyncMirror()
        // Two Macs added it at once, offline: two records, a use each in S1.
        mirror.extensions["A1"] = SyncExtension(id: "A1", storeID: "a", title: "A", siteAccess: "allSites")
        mirror.extensions["A2"] = SyncExtension(id: "A2", storeID: "a", title: "A", siteAccess: "allSites")
        mirror.extensionUses["U1"] = SyncExtensionUse(id: "U1", extensionRecord: "A1", space: "S1")
        mirror.extensionUses["U2"] = SyncExtensionUse(id: "U2", extensionRecord: "A2", space: "S1")
        let off = SyncPlan.publish(from: [local("a", ["S1"])], to: [local("a", [])], in: &mirror, name: namer())
        XCTAssertEqual(Set(off.delete), ["U1", "U2"], "off is off for both")
        let on = SyncPlan.publish(from: [local("a", [])], to: [local("a", ["S1"])], in: &mirror, name: namer())
        XCTAssertEqual(on.save, ["r1"], "one use, not one a record")
    }

    func testJoiningTakesUpTheOtherMacsSpacesForWhatIsHere() {
        var mirror = SyncMirror()
        mirror.extensions["R"] = SyncExtension(id: "R", storeID: "a", title: "A", siteAccess: "allSites")
        mirror.extensions["Q"] = SyncExtension(id: "Q", storeID: "b", title: "B", siteAccess: "allSites")
        mirror.extensionUses["U1"] = SyncExtensionUse(id: "U1", extensionRecord: "R", space: "S2")
        mirror.extensionUses["U2"] = SyncExtensionUse(id: "U2", extensionRecord: "Q", space: "S2")
        XCTAssertEqual(SyncPlan.joining(mirror, local: [local("a", ["S1"])]), [.init(storeID: "a", space: "S2")],
                       "only for what is installed here; nothing turned off")
    }

    func testAnExtensionsStorePageIsntSharedWithOtherDevices() throws {
        let page = try XCTUnwrap(URL(string: "https://chromewebstore.google.com/detail/dark-reader/eimadpbcbfnmbkopoojfekhnkhdbieeh"))
        XCTAssertFalse(SyncPlan.isShareable(page), "it would name what the encrypted list keeps")
        XCTAssertTrue(SyncPlan.isShareable(try XCTUnwrap(URL(string: "https://chromewebstore.google.com/category/extensions"))))
    }
}
