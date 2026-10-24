import Foundation
@testable import PadCore
import XCTest

/// Last edit wins, field by field (SyncCRDT.swift): the merge's laws, and
/// devices that edit apart and exchange records in any order ending the same.
final class SyncCRDTTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: The clock

    func testAnEditMadeAfterSeeingAnotherIsLaterWhateverTheClocks() {
        var ahead = SyncClock(device: "A")
        var behind = SyncClock(device: "B")
        let early = ahead.tick(now: start.addingTimeInterval(3600))
        behind.see(early)
        let late = behind.tick(now: start)
        XCTAssertGreaterThan(late, early, "made after seeing it, though this clock is an hour behind")
        XCTAssertGreaterThan(behind.tick(now: start), late, "and each edit after the last")
        var other = SyncClock(device: "C")
        XCTAssertLessThan(other.tick(now: start), late, "an edit made apart is ordered by its clock")
    }

    func testDatesForHistoryNeverRepeatAndFollowWhatWasSeen() {
        var clock = SyncClock(device: "A")
        let clearing = start.addingTimeInterval(3600)
        clock.see(clearing)
        let first = clock.tickMillis(now: start)
        let second = clock.tickMillis(now: start)
        XCTAssertGreaterThan(first, clearing, "after a clearing an hour ahead, a visit is after it, not at its very time")
        XCTAssertGreaterThan(second, first)
        XCTAssertEqual(clock.tickMillis(now: start.addingTimeInterval(7200)), start.addingTimeInterval(7200), "and back on the wall clock once it passes")
    }

    func testStampsKeepTheirText() throws {
        let stamp = SyncStamp(time: 1_800_000_000_123, count: 4, device: "5E2A-11")
        XCTAssertEqual(SyncStamp(stamp.description), stamp)
        XCTAssertNil(SyncStamp("not a stamp"))
        let marks = SyncStamps(fields: ["title": stamp], deleted: true, life: stamp)
        XCTAssertEqual(SyncStamps(text: marks.text), marks)
        XCTAssertEqual(SyncStamps(text: "garbage"), SyncStamps(), "unreadable stamps are none: the record loses to any stamped")
    }

    // MARK: The merge's laws

    func testMergeIsCommutativeAssociativeAndIdempotent() {
        var random = Random(seed: 7)
        for _ in 0..<2000 {
            let (a, b, c) = (random.record(), random.record(), random.record())
            XCTAssertEqual(SyncRecord.merged(a, b), SyncRecord.merged(b, a), "commutative")
            XCTAssertEqual(SyncRecord.merged(SyncRecord.merged(a, b), c), SyncRecord.merged(a, SyncRecord.merged(b, c)), "associative")
            XCTAssertEqual(SyncRecord.merged(a, a), a, "idempotent")
        }
    }

    // MARK: Devices

    func testDevicesConvergeWhateverOrderEditsArriveIn() {
        for seed in 1...300 {
            var random = Random(seed: UInt64(seed))
            var devices = (0..<4).map { Device(name: "D\($0)", skew: Double(random.int(7200)) - 3600) }
            var now = start
            var inFlight: [(to: Int, record: SyncRecord)] = []
            for _ in 0..<80 {
                now.addTimeInterval(Double(random.int(120)))
                let who = random.int(devices.count)
                if random.int(3) == 0, !inFlight.isEmpty {
                    // Something arrives, in any order; some arrive twice.
                    let index = random.int(inFlight.count)
                    let message = random.int(4) == 0 ? inFlight[index] : inFlight.remove(at: index)
                    devices[message.to].receive(message.record, now: now)
                } else {
                    devices[who].randomEdit(&random, now: now)
                }
                for d in devices.indices {
                    for record in devices[d].outbox {
                        for other in devices.indices where other != d { inFlight.append((other, record)) }
                    }
                    devices[d].outbox = []
                }
            }
            // Everything arrives at last, records sent back on the way too.
            while !inFlight.isEmpty {
                let message = inFlight.removeFirst()
                devices[message.to].receive(message.record, now: now)
                for d in devices.indices {
                    for record in devices[d].outbox {
                        for other in devices.indices where other != d { inFlight.append((other, record)) }
                    }
                    devices[d].outbox = []
                }
            }
            for d in devices.indices.dropFirst() {
                XCTAssertEqual(devices[d].state, devices[0].state, "seed \(seed): device \(d)'s records differ from device 0's")
                XCTAssertEqual(devices[d].mirror, devices[0].mirror, "seed \(seed): device \(d) shows other records than device 0")
            }
        }
    }

    func testTheLaterEditWinsEvenWhenTheEarlierArrivesLast() {
        var (a, b) = (Device(name: "A"), Device(name: "B"))
        a.edit(now: start) { $0.bookmarks["m"] = SyncBookmark(id: "m", space: "s", parent: nil, position: 1, title: "Mark", url: "https://a.example") }
        b.receive(a.outbox.removeFirst(), now: start)
        // B, offline, renames it first; A renames it an hour later.
        b.edit(now: start.addingTimeInterval(60)) { $0.bookmarks["m"]?.title = "Offline" }
        a.edit(now: start.addingTimeInterval(3600)) { $0.bookmarks["m"]?.title = "Latest" }
        a.receive(b.outbox.removeFirst(), now: start.addingTimeInterval(7200))
        b.receive(a.outbox.removeFirst(), now: start.addingTimeInterval(7200))
        XCTAssertEqual(a.mirror.bookmarks["m"]?.title, "Latest")
        XCTAssertEqual(b.mirror.bookmarks["m"]?.title, "Latest")
    }

    func testEditsOfDifferentFieldsMadeApartBothStay() {
        var (a, b) = (Device(name: "A"), Device(name: "B"))
        a.edit(now: start) { $0.bookmarks["m"] = SyncBookmark(id: "m", space: "s", parent: nil, position: 1, title: "Mark", url: "https://a.example") }
        b.receive(a.outbox.removeFirst(), now: start)
        a.edit(now: start.addingTimeInterval(60)) { $0.bookmarks["m"]?.title = "Renamed" }
        b.edit(now: start.addingTimeInterval(61)) { $0.bookmarks["m"]?.position = 9 }
        a.receive(b.outbox.removeFirst(), now: start.addingTimeInterval(120))
        b.receive(a.outbox.removeFirst(), now: start.addingTimeInterval(120))
        for device in [a, b] {
            XCTAssertEqual(device.mirror.bookmarks["m"]?.title, "Renamed")
            XCTAssertEqual(device.mirror.bookmarks["m"]?.position, 9)
        }
    }

    func testADeletionAndAnEditMadeApartGoByTime() {
        for deletionLater in [true, false] {
            var (a, b) = (Device(name: "A"), Device(name: "B"))
            a.edit(now: start) {
                $0.spaces["s"] = SyncSpace(id: "s", name: "Work", symbol: "briefcase", color: "blue")
                $0.bookmarks["m"] = SyncBookmark(id: "m", space: "s", parent: nil, position: 1, title: "Mark", url: "https://a.example")
            }
            while !a.outbox.isEmpty { b.receive(a.outbox.removeFirst(), now: start) }
            let (deletion, edit) = deletionLater ? (start.addingTimeInterval(120), start.addingTimeInterval(60))
                                                 : (start.addingTimeInterval(60), start.addingTimeInterval(120))
            a.edit(now: deletion) { $0.bookmarks["m"] = nil }
            b.edit(now: edit) { $0.bookmarks["m"]?.title = "Edited" }
            let (fromA, fromB) = (a.outbox, b.outbox)
            (a.outbox, b.outbox) = ([], [])
            for record in fromB { a.receive(record, now: start.addingTimeInterval(200)) }
            for record in fromA { b.receive(record, now: start.addingTimeInterval(200)) }
            XCTAssertEqual(a.state, b.state)
            if deletionLater {
                XCTAssertNil(a.mirror.bookmarks["m"], "deleted after the edit: gone")
                XCTAssertTrue(a.mirror.isDeleted("m"))
            } else {
                XCTAssertEqual(a.mirror.bookmarks["m"]?.title, "Edited", "edited after the deletion: back, edited")
            }
        }
    }

    func testARemovedSpaceHidesWhatItHeldAndALaterEditInsideBringsItBack() {
        var (a, b) = (Device(name: "A"), Device(name: "B"))
        a.edit(now: start) {
            $0.spaces["s"] = SyncSpace(id: "s", name: "Work", symbol: "briefcase", color: "blue")
            $0.bookmarks["m"] = SyncBookmark(id: "m", space: "s", parent: nil, position: 1, title: "Mark", url: "https://a.example")
            $0.bookmarks["n"] = SyncBookmark(id: "n", space: "s", parent: nil, position: 2, title: "Note", url: "https://b.example")
        }
        while !a.outbox.isEmpty { b.receive(a.outbox.removeFirst(), now: start) }
        a.edit(now: start.addingTimeInterval(60)) { $0.spaces["s"] = nil }
        XCTAssertEqual(a.mirror.removedSpaces, ["s"])
        XCTAssertNotNil(a.mirror.bookmarks["n"], "hidden with its space, not deleted")
        XCTAssertFalse(a.mirror.isDeleted("n"))
        // B, which hasn't heard, renames a bookmark in it after the removal.
        b.edit(now: start.addingTimeInterval(120)) { $0.bookmarks["m"]?.title = "Kept" }
        while !a.outbox.isEmpty { b.receive(a.outbox.removeFirst(), now: start.addingTimeInterval(200)) }
        while !b.outbox.isEmpty { a.receive(b.outbox.removeFirst(), now: start.addingTimeInterval(200)) }
        for device in [a, b] {
            XCTAssertEqual(device.mirror.spaces["s"]?.name, "Work", "back, as the edit inside it came later")
            XCTAssertEqual(device.mirror.bookmarks["m"]?.title, "Kept")
            XCTAssertNotNil(device.mirror.bookmarks["n"], "with all it held")
        }
        XCTAssertEqual(a.state, b.state)
        // Removed again, after all that: it stays removed.
        a.edit(now: start.addingTimeInterval(300)) { $0.spaces["s"] = nil }
        while !a.outbox.isEmpty { b.receive(a.outbox.removeFirst(), now: start.addingTimeInterval(400)) }
        XCTAssertEqual(b.mirror.removedSpaces, ["s"])
    }

    func testARecordFromBeforeStampsLosesToAStampedOneAndIsSentBack() {
        var a = Device(name: "A")
        a.edit(now: start) { $0.bookmarks["m"] = SyncBookmark(id: "m", space: "s", parent: nil, position: 1, title: "Stamped", url: "https://a.example") }
        a.outbox = []
        let old = SyncBookmark(id: "m", space: "s", parent: nil, position: 5, title: "Unstamped", url: "https://a.example").record
        a.receive(old, now: start.addingTimeInterval(60))
        XCTAssertEqual(a.mirror.bookmarks["m"]?.title, "Stamped")
        XCTAssertEqual(a.outbox.map(\.name), ["m"], "sent back, stamped, so iCloud's copy has them too")
        var fresh = Device(name: "B")
        fresh.receive(old, now: start)
        XCTAssertEqual(fresh.mirror.bookmarks["m"]?.title, "Unstamped", "with nothing here, taken as it is")
    }

    func testTombstonesExpireAfterThirtyDaysWithWhatTheirSpaceHeld() {
        var a = Device(name: "A")
        a.edit(now: start) {
            $0.spaces["s"] = SyncSpace(id: "s", name: "Work", symbol: "briefcase", color: "blue")
            $0.spaces["t"] = SyncSpace(id: "t", name: "Home", symbol: "house", color: "green")
            $0.bookmarks["m"] = SyncBookmark(id: "m", space: "s", parent: nil, position: 1, title: "Mark", url: "https://a.example")
            $0.bookmarks["k"] = SyncBookmark(id: "k", space: "t", parent: nil, position: 1, title: "Kept", url: "https://k.example")
            $0.bookmarks["x"] = SyncBookmark(id: "x", space: "t", parent: nil, position: 2, title: "Gone", url: "https://x.example")
        }
        a.edit(now: start.addingTimeInterval(60)) {
            $0.spaces["s"] = nil
            $0.bookmarks["x"] = nil
        }
        XCTAssertEqual(SyncPlan.expired(in: a.mirror, now: start.addingTimeInterval(29 * 86_400)), [])
        XCTAssertEqual(SyncPlan.expired(in: a.mirror, now: start.addingTimeInterval(31 * 86_400)), ["s", "x"],
                       "the space's tombstone and the deleted bookmark; not what is still there")
        XCTAssertEqual(SyncPlan.expired(in: a.mirror, now: start.addingTimeInterval(31 * 86_400), gone: ["s"]), ["s", "x"],
                       "what the space held waits while the space is here")
        a.mirror.forget("s")
        a.mirror.forget("x")
        XCTAssertEqual(SyncPlan.expired(in: a.mirror, now: start.addingTimeInterval(31 * 86_400), gone: ["s"]), ["m"],
                       "then goes, after the space")
    }

    func testDeletingABookmarkInsideARemovedSpaceAfterwardsAlsoBringsItBack() {
        var (a, b) = (Device(name: "A"), Device(name: "B"))
        a.edit(now: start) {
            $0.spaces["s"] = SyncSpace(id: "s", name: "Work", symbol: "briefcase", color: "blue")
            $0.bookmarks["m"] = SyncBookmark(id: "m", space: "s", parent: nil, position: 1, title: "Mark", url: "https://a.example")
            $0.bookmarks["n"] = SyncBookmark(id: "n", space: "s", parent: nil, position: 2, title: "Note", url: "https://b.example")
        }
        while !a.outbox.isEmpty { b.receive(a.outbox.removeFirst(), now: start) }
        a.edit(now: start.addingTimeInterval(60)) { $0.spaces["s"] = nil }
        b.edit(now: start.addingTimeInterval(120)) { $0.bookmarks["m"] = nil }
        while !b.outbox.isEmpty { a.receive(b.outbox.removeFirst(), now: start.addingTimeInterval(200)) }
        while !a.outbox.isEmpty { b.receive(a.outbox.removeFirst(), now: start.addingTimeInterval(200)) }
        for device in [a, b] {
            XCTAssertNotNil(device.mirror.spaces["s"], "an edit inside it, a deletion too, came after the removal")
            XCTAssertNil(device.mirror.bookmarks["m"])
            XCTAssertNotNil(device.mirror.bookmarks["n"])
        }
    }

    func testExtensionsInARemovedSpaceAreOffWhileItIsAndOnWhenItIsBack() {
        var mirror = SyncMirror()
        mirror.spaces["s"] = SyncSpace(id: "s", name: "Work", symbol: "briefcase", color: "blue")
        mirror.extensions["e"] = SyncExtension(id: "e", storeID: "store", title: "Tool", siteAccess: "allSites")
        mirror.extensionUses["u"] = SyncExtensionUse(id: "u", extensionRecord: "e", space: "s")
        var removed = mirror
        removed.put(SyncRecord(kind: .space, name: "s", fields: mirror.spaces["s"]!.record.fields,
                               stamps: SyncStamps(deleted: true, life: SyncStamp(time: 5, device: "A"))))
        let local = [SyncPlan.LocalExtension(storeID: "store", title: "Tool", siteAccess: "allSites", spaces: [])]
        let back = SyncPlan.follow(from: removed, to: mirror, local: local)
        XCTAssertEqual(back.on, [SyncPlan.ExtensionInSpace(storeID: "store", space: "s")], "on again with the space")
    }

    func testTombstonesExpireByWhenICloudSavedThem() {
        var a = Device(name: "A")
        a.edit(now: start) {
            $0.spaces["t"] = SyncSpace(id: "t", name: "Home", symbol: "house", color: "green")
            $0.bookmarks["x"] = SyncBookmark(id: "x", space: "t", parent: nil, position: 1, title: "Gone", url: "https://x.example")
        }
        a.edit(now: start.addingTimeInterval(60)) { $0.bookmarks["x"] = nil }
        let saved = start.addingTimeInterval(20 * 86_400)
        XCTAssertEqual(SyncPlan.expired(in: a.mirror, now: start.addingTimeInterval(40 * 86_400), saved: { _ in saved }), [],
                       "saved in iCloud 20 days ago, whatever the deletion's stamp says")
        XCTAssertEqual(SyncPlan.expired(in: a.mirror, now: start.addingTimeInterval(51 * 86_400), saved: { _ in saved }), ["x"])
    }

    func testASpaceThatCameBackIsNotCollected() {
        var (a, b) = (Device(name: "A"), Device(name: "B"))
        a.edit(now: start) {
            $0.spaces["s"] = SyncSpace(id: "s", name: "Work", symbol: "briefcase", color: "blue")
            $0.bookmarks["m"] = SyncBookmark(id: "m", space: "s", parent: nil, position: 1, title: "Mark", url: "https://a.example")
        }
        while !a.outbox.isEmpty { b.receive(a.outbox.removeFirst(), now: start) }
        a.edit(now: start.addingTimeInterval(60)) { $0.spaces["s"] = nil }
        b.edit(now: start.addingTimeInterval(120)) { $0.bookmarks["m"]?.title = "Kept" }
        while !b.outbox.isEmpty { a.receive(b.outbox.removeFirst(), now: start.addingTimeInterval(200)) }
        XCTAssertNotNil(a.mirror.spaces["s"])
        XCTAssertEqual(SyncPlan.expired(in: a.mirror, now: start.addingTimeInterval(40 * 86_400)), [],
                       "shown again, so neither it nor what it holds is a tombstone to collect")
    }

    func testASpaceBroughtBackStaysWhenTheEditsTombstoneIsCollected() {
        var (a, b) = (Device(name: "A"), Device(name: "B"))
        a.edit(now: start) {
            $0.spaces["s"] = SyncSpace(id: "s", name: "Work", symbol: "briefcase", color: "blue")
            $0.bookmarks["m"] = SyncBookmark(id: "m", space: "s", parent: nil, position: 1, title: "Mark", url: "https://a.example")
            $0.bookmarks["n"] = SyncBookmark(id: "n", space: "s", parent: nil, position: 2, title: "Note", url: "https://b.example")
        }
        while !a.outbox.isEmpty { b.receive(a.outbox.removeFirst(), now: start) }
        a.edit(now: start.addingTimeInterval(60)) { $0.spaces["s"] = nil }
        let removal = a.outbox
        a.outbox = []
        b.edit(now: start.addingTimeInterval(120)) { $0.bookmarks["m"] = nil }
        while !b.outbox.isEmpty { a.receive(b.outbox.removeFirst(), now: start.addingTimeInterval(200)) }
        XCTAssertEqual(a.outbox.map(\.name), ["s"], "brought back, and sent")
        for record in removal + a.outbox { b.receive(record, now: start.addingTimeInterval(200)) }
        a.outbox = []
        // The deletion's tombstone goes after its 30 days, everywhere.
        let evidence = b.mirror.stamps["m"]?.life
        a.mirror.forget("m")
        b.mirror.forget("m")
        XCTAssertEqual(a.mirror.settleSpaces() + b.mirror.settleSpaces(), [])
        for device in [a, b] {
            XCTAssertNotNil(device.mirror.spaces["s"], "its own record says it is back")
            XCTAssertEqual(device.mirror.stamps["s"]?.deleted, false)
            XCTAssertEqual(device.mirror.stamps["s"]?.life, evidence, "stamped with the edit that brought it back")
        }
        // A device that comes later gets the space and what is left in it.
        var c = Device(name: "C")
        for name in ["s", "n"] { c.receive(a.mirror.entry(named: name)!, now: start.addingTimeInterval(40 * 86_400)) }
        XCTAssertNotNil(c.mirror.spaces["s"])
        XCTAssertEqual(c.mirror, a.mirror)
    }

    func testARecordEditedSinceItsCollectionIsMadeAgain() {
        var a = Device(name: "A")
        a.edit(now: start) {
            $0.spaces["s"] = SyncSpace(id: "s", name: "Work", symbol: "briefcase", color: "blue")
            $0.spaces["t"] = SyncSpace(id: "t", name: "Home", symbol: "house", color: "green")
            $0.bookmarks["m"] = SyncBookmark(id: "m", space: "s", parent: nil, position: 1, title: "Mark", url: "https://a.example")
            $0.bookmarks["n"] = SyncBookmark(id: "n", space: "s", parent: nil, position: 2, title: "Note", url: "https://n.example")
            $0.bookmarks["k"] = SyncBookmark(id: "k", space: "t", parent: nil, position: 1, title: "Kept", url: "https://k.example")
            $0.bookmarks["j"] = SyncBookmark(id: "j", space: "t", parent: nil, position: 2, title: "Just", url: "https://j.example")
        }
        let now = start.addingTimeInterval(61 * 86_400)
        // When iCloud last saved each: the space s a day ago, all else two months ago.
        let old = start
        let saved = { (name: String) -> Date? in name == "s" ? now.addingTimeInterval(-86_400) : old }
        func survivors(_ names: [String], unsent: Set<String> = []) -> Set<String> {
            SyncPlan.survivors(of: names, in: a.mirror, unsent: unsent, saved: saved, now: now)
        }
        XCTAssertEqual(survivors(["s"]), ["s", "m", "n"], "saved a day ago: back, with all it holds, wherever their deletions come")
        XCTAssertEqual(survivors(["m"]), [], "deleted on its own: its space's edit a day ago keeps it no more")
        XCTAssertEqual(survivors(["t", "k", "j"]), [], "unedited for two months: gone, and what it holds with it")
        XCTAssertEqual(survivors(["k"]), [], "unedited, in a space that stays")
        XCTAssertEqual(survivors(["t", "k", "j"], unsent: ["k"]), ["t", "k", "j"],
                       "an edit inside it still to send brings it back with all it holds")
        XCTAssertEqual(survivors(["k"], unsent: ["k"]), ["k"])
        // A stamp a year ahead (a clock that was wrong) says nothing of when it was last edited.
        var ahead = a.mirror
        ahead.stamps["j"]?.life = SyncStamp(time: Int64(now.addingTimeInterval(365 * 86_400).timeIntervalSince1970 * 1000), device: "Z")
        XCTAssertEqual(SyncPlan.survivors(of: ["j"], in: ahead, unsent: [], saved: saved, now: now), [])
        XCTAssertEqual(survivors(["t"], unsent: ["k"]), ["t", "k", "j"])
        a.edit(now: now) { $0.bookmarks["j"] = nil }
        XCTAssertEqual(survivors(["t"], unsent: ["j"]), ["t", "k"],
                       "a deletion inside it still to send brings it back too, with what is left")
        a.edit(now: now) { $0.bookmarks["m"] = nil }
        XCTAssertEqual(survivors(["m"]), [], "a tombstone iCloud saved two months ago goes")
        XCTAssertEqual(survivors(["m"], unsent: ["m"]), ["m"], "a deletion still to send is made again, later than what was taken")
    }

    func testATombstoneWaitsForItsSaveBeforeExpiring() {
        var a = Device(name: "A")
        a.edit(now: start) {
            $0.spaces["t"] = SyncSpace(id: "t", name: "Home", symbol: "house", color: "green")
            $0.bookmarks["x"] = SyncBookmark(id: "x", space: "t", parent: nil, position: 1, title: "Gone", url: "https://x.example")
        }
        a.edit(now: start.addingTimeInterval(60)) { $0.bookmarks["x"] = nil }
        let now = start.addingTimeInterval(40 * 86_400)
        XCTAssertEqual(SyncPlan.expired(in: a.mirror, now: now), ["x"], "by its stamp, with no save known")
        XCTAssertEqual(SyncPlan.expired(in: a.mirror, now: now, waiting: ["x"]), [], "not in iCloud as it is yet")
    }

    func testAPinnedPagesNewNameDoesNotBringItsPinBack() {
        for moved in [false, true] {
            var (a, b) = (Device(name: "A"), Device(name: "B"))
            a.edit(now: start) {
                $0.spaces["s"] = SyncSpace(id: "s", name: "Work", symbol: "briefcase", color: "blue")
                $0.pinned["p"] = SyncPinned(id: "p", space: "s", position: 1, title: "Inbox", url: "https://mail.example")
            }
            while !a.outbox.isEmpty { b.receive(a.outbox.removeFirst(), now: start) }
            a.edit(now: start.addingTimeInterval(60)) { $0.pinned["p"] = nil }
            // B, before it hears of that: the page renames itself and the pin's
            // place is worked out again; or it is pinned at another address.
            b.edit(now: start.addingTimeInterval(120)) {
                if moved {
                    $0.pinned["p"]?.url = "https://mail.example/inbox"
                } else {
                    $0.pinned["p"]?.title = "Inbox (3)"
                    $0.pinned["p"]?.position = 0
                }
            }
            while !a.outbox.isEmpty { b.receive(a.outbox.removeFirst(), now: start.addingTimeInterval(200)) }
            while !b.outbox.isEmpty { a.receive(b.outbox.removeFirst(), now: start.addingTimeInterval(200)) }
            for device in [a, b] {
                if moved {
                    XCTAssertNotNil(device.mirror.pinned["p"], "pinned elsewhere after it was unpinned: back, as the last edit wins")
                } else {
                    XCTAssertNil(device.mirror.pinned["p"], "its page's new name and its new place are no edit: unpinned stays unpinned")
                }
            }
        }
    }

    func testRemoteDeletionOfTheLastSpaceCreatesAFreshReplacementBeforeCleanup() throws {
        let pin = TabRecord(url: URL(string: "https://mail.example")!, title: "Mail", pinned: URL(string: "https://mail.example")!)
        var space = Space(name: "Client", symbol: "briefcase", tabs: [pin],
                          bookmarks: [Bookmark(title: "Docs", url: URL(string: "https://docs.example")!)])
        space.cloudID = UUID()
        var workspace = Workspace(spaces: [space])
        let cloud = try XCTUnwrap(space.cloudID?.uuidString)
        let applied = SyncPlan.apply(SyncMirror(), to: &workspace, deleted: [cloud])
        XCTAssertEqual(applied.removedSpaces, [space.id])
        let replacement = try XCTUnwrap(applied.replacementSpace)
        XCTAssertNotEqual(replacement, space.id)
        XCTAssertNotEqual(workspace.space(replacement)?.tabs.first?.id, pin.id)
        XCTAssertTrue(workspace.space(replacement)?.bookmarks.isEmpty == true)
        XCTAssertNil(workspace.space(replacement)?.cloudID)
        XCTAssertTrue(workspace.space(replacement)?.tabs.allSatisfy { $0.url == nil && !$0.isPinned } == true)
        XCTAssertNil(SyncPlan.apply(SyncMirror(), to: &workspace, deleted: [cloud]).replacementSpace,
                     "replayed delivery must not make another replacement")
        XCTAssertTrue(workspace.removeSpace(space.id), "ordinary app cleanup can now remove the old identity")
        XCTAssertNil(workspace.space(space.id))
        XCTAssertEqual(workspace.spaces.map(\.id), [replacement])
        XCTAssertTrue(SyncPlan.apply(SyncMirror(), to: &workspace, deleted: [cloud]).removedSpaces.isEmpty)
        XCTAssertTrue(SyncPlan.records(of: workspace, keeping: SyncMirror()).spaces[cloud] == nil,
                      "the removed identity is never republished")
    }

    func testOfflineRejoinCleansAllDeletedSpacesBeforeAssigningNewCloudIdentities() throws {
        var workspace = Workspace.starting()
        workspace.spaces[0].cloudID = UUID()
        let second = workspace.addSpace(named: "Second")
        let secondIndex = try XCTUnwrap(workspace.spaces.firstIndex { $0.id == second })
        workspace.spaces[secondIndex].cloudID = UUID()
        let oldIDs = Set(workspace.spaces.map(\.id))
        let deleted = Set(workspace.spaces.compactMap { $0.cloudID?.uuidString })
        let removals = SyncPlan.apply(SyncMirror(), to: &workspace, deleted: deleted)
        XCTAssertEqual(Set(removals.removedSpaces), oldIDs)
        let replacement = try XCTUnwrap(removals.replacementSpace)
        for id in removals.removedSpaces { XCTAssertTrue(workspace.removeSpace(id)) }
        var remote = SyncMirror()
        for _ in 0..<3 {
            remote = SyncPlan.join(&workspace, remote: remote)
            XCTAssertTrue(SyncPlan.apply(SyncMirror(), to: &workspace, deleted: deleted).removedSpaces.isEmpty)
        }
        XCTAssertEqual(workspace.spaces.map(\.id), [replacement])
        XCTAssertTrue(deleted.isDisjoint(with: remote.spaces.keys), "offline deletion cannot be republished during rejoin")
    }

    func testStampingTouchesOnlyWhatChanged() {
        var a = Device(name: "A")
        a.edit(now: start) { $0.bookmarks["m"] = SyncBookmark(id: "m", space: "s", parent: nil, position: 1, title: "Mark", url: "https://a.example") }
        let first = a.mirror.stamps["m"]
        a.outbox = []
        a.edit(now: start.addingTimeInterval(60)) { $0.bookmarks["m"]?.title = "Mark" }
        XCTAssertTrue(a.outbox.isEmpty, "no change, nothing sent")
        a.edit(now: start.addingTimeInterval(120)) { $0.bookmarks["m"]?.title = "Renamed" }
        XCTAssertEqual(a.outbox.map(\.name), ["m"])
        XCTAssertEqual(a.mirror.stamps["m"]?.fields["url"], first?.fields["url"], "the address keeps its stamp")
        XCTAssertGreaterThan(a.mirror.stamps["m"]?.fields["title"] ?? first!.fields["title"]!, first!.fields["title"]!)
    }
}

// MARK: A device, as Sync uses the mirror

private struct Device {
    var mirror = SyncMirror()
    var clock: SyncClock
    /// How far this device's clock is off.
    var skew: TimeInterval
    /// Records it has to send.
    var outbox: [SyncRecord] = []

    init(name: String, skew: TimeInterval = 0) {
        clock = SyncClock(device: name)
        self.skew = skew
    }

    /// An edit here: the records as the workspace now has them, stamped
    /// over what they were (Sync.queueChanges).
    mutating func edit(now: Date, _ change: (inout SyncMirror) -> Void) {
        var next = mirror
        change(&next)
        let (stamped, changed) = SyncPlan.stamp(next, over: mirror, clock: &clock, now: now.addingTimeInterval(skew))
        mirror = stamped
        let back = mirror.settleSpaces()
        outbox += (changed + back).compactMap { mirror.entry(named: $0) }
    }

    /// A record from iCloud (Sync.took), and spaces it brought back, sent.
    mutating func receive(_ record: SyncRecord, now: Date) {
        for stamp in record.stamps.all { clock.see(stamp) }
        if mirror.merge(record), let back = mirror.entry(named: record.name) { outbox.append(back) }
        outbox += mirror.settleSpaces().compactMap { mirror.entry(named: $0) }
    }

    /// Everything that should match between devices.
    var state: [String: SyncRecord] {
        Dictionary(uniqueKeysWithValues: mirror.entryNames.compactMap { name in mirror.entry(named: name).map { (name, $0) } })
    }

    mutating func randomEdit(_ random: inout Random, now: Date) {
        let spaces = ["s1", "s2"]
        let marks = ["m1", "m2", "m3", "m4"]
        let pins = ["p1", "p2"]
        switch random.int(10) {
        case 7:
            let id = pins[random.int(pins.count)]
            let space = spaces[random.int(spaces.count)]
            edit(now: now) {
                $0.pinned[id] = SyncPinned(id: id, space: space, position: Double(random.int(5)), title: random.word(),
                                           url: "https://\(random.word()).example")
            }
        case 8:
            let id = pins[random.int(pins.count)]
            edit(now: now) { $0.pinned[id]?.title = random.word() }
        case 9:
            let id = pins[random.int(pins.count)]
            edit(now: now) { $0.pinned[id] = nil }
        case 0:
            let id = spaces[random.int(spaces.count)]
            edit(now: now) { $0.spaces[id] = SyncSpace(id: id, name: random.word(), symbol: "star", color: "blue") }
        case 1:
            let id = spaces[random.int(spaces.count)]
            edit(now: now) { $0.spaces[id] = nil }
        case 2:
            let id = marks[random.int(marks.count)]
            let space = spaces[random.int(spaces.count)]
            edit(now: now) {
                $0.bookmarks[id] = SyncBookmark(id: id, space: space, parent: nil, position: Double(random.int(10)), title: random.word(),
                                                url: "https://\(random.word()).example")
            }
        case 3:
            let id = marks[random.int(marks.count)]
            edit(now: now) { $0.bookmarks[id]?.title = random.word() }
        case 4:
            let id = marks[random.int(marks.count)]
            edit(now: now) { $0.bookmarks[id]?.position = Double(random.int(10)) }
        case 5:
            let id = marks[random.int(marks.count)]
            let parent = random.int(2) == 0 ? nil : marks[random.int(marks.count)]
            edit(now: now) { $0.bookmarks[id]?.parent = parent }
        default:
            let id = marks[random.int(marks.count)]
            edit(now: now) { $0.bookmarks[id] = nil }
        }
    }
}

/// A seeded generator, so a failure can be run again.
private struct Random {
    var state: UInt64

    init(seed: UInt64) {
        state = seed &* 0x9E37_79B9_7F4A_7C15 | 1
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }

    mutating func int(_ bound: Int) -> Int {
        Int(next() % UInt64(bound))
    }

    mutating func word() -> String {
        ["alpha", "beta", "gamma", "delta", "omega"][int(5)]
    }

    mutating func stamp() -> SyncStamp? {
        int(5) == 0 ? nil : SyncStamp(time: Int64(int(4)), count: Int32(int(2)), device: ["A", "B"][int(2)])
    }

    mutating func record() -> SyncRecord {
        var fields: [String: SyncField] = ["space": .string("s")]
        var marks = SyncStamps()
        for key in ["title", "position", "url", "parent"] {
            switch int(3) {
            case 0: break
            case 1: fields[key] = key == "position" ? .double(Double(int(3))) : .string(word())
            default: fields[key] = .string(word())
            }
            marks.fields[key] = stamp()
        }
        marks.deleted = int(2) == 0
        marks.life = stamp()
        return SyncRecord(kind: .bookmark, name: "m", fields: fields, stamps: marks)
    }
}

// MARK: Through the app's own path

/// Devices as Sync drives them: an edit to the workspace becomes records
/// (SyncPlan.records), stamped over the mirror; a record that comes is
/// merged, and the workspace made from the mirror (SyncPlan.apply).
final class SyncWorkspaceTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    func testWorkspacesEditedApartEndTheSame() {
        var seen = (bookmarks: 0, tombstones: 0, removedSpaces: 0, folders: 0, pins: 0, sentBack: 0)
        for seed in 1...150 {
            var random = Random(seed: UInt64(seed) &+ 1000)
            var apps = (0..<3).map { App(name: "D\($0)") }
            var now = start
            // One space to start from, which every device takes.
            apps[0].change(now: now) { workspace in
                var space = Space(name: "Work", symbol: "briefcase", tabs: [TabRecord(url: nil)])
                space.cloudID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")
                workspace.spaces.append(space)
            }
            var inFlight: [(to: Int, record: SyncRecord)] = []
            func post() {
                for d in apps.indices {
                    for record in apps[d].outbox {
                        for other in apps.indices where other != d { inFlight.append((other, record)) }
                    }
                    apps[d].outbox = []
                }
            }
            post()
            for _ in 0..<70 {
                now.addTimeInterval(Double(random.int(90) + 1))
                if random.int(3) == 0, !inFlight.isEmpty {
                    let message = inFlight.remove(at: random.int(inFlight.count))
                    apps[message.to].receive(message.record)
                } else {
                    apps[random.int(apps.count)].randomChange(&random, now: now)
                }
                post()
            }
            while !inFlight.isEmpty {
                let message = inFlight.removeFirst()
                apps[message.to].receive(message.record)
                post()
            }
            let mirror = apps[0].mirror
            seen.bookmarks += mirror.bookmarks.count
            seen.tombstones += mirror.buried.count
            seen.removedSpaces += mirror.removedSpaces.count
            seen.folders += mirror.bookmarks.values.filter { $0.url == nil }.count
            seen.pins += mirror.pinned.count
            seen.sentBack += apps.map(\.sentBack).reduce(0, +)
            for d in apps.indices.dropFirst() {
                XCTAssertEqual(apps[d].mirror, apps[0].mirror, "seed \(seed): device \(d)'s records differ")
                XCTAssertEqual(apps[d].face, apps[0].face, "seed \(seed): device \(d)'s spaces differ")
            }
        }
        // The runs reached what they are for, not only empty spaces.
        XCTAssertGreaterThan(seen.bookmarks, 300)
        XCTAssertGreaterThan(seen.tombstones, 100)
        XCTAssertGreaterThan(seen.removedSpaces, 20)
        XCTAssertGreaterThan(seen.folders, 20)
        XCTAssertGreaterThan(seen.pins, 50)
        XCTAssertGreaterThan(seen.sentBack, 10, "and devices sent back what they had later")
    }

    func testARemovedSpaceComesBackWithItsBookmarksWhenOneIsEditedLater() {
        var (a, b) = (App(name: "A"), App(name: "B"))
        let cloud = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let mark = UUID()
        a.change(now: start) { workspace in
            var space = Space(name: "Trip", symbol: "airplane", tabs: [TabRecord(url: nil)],
                              bookmarks: [Bookmark(id: mark, title: "Hotel", url: URL(string: "https://hotel.example")!),
                                          Bookmark(title: "Train", url: URL(string: "https://train.example")!)])
            space.cloudID = cloud
            workspace.spaces = [Space(name: "Home", symbol: "house", tabs: [TabRecord(url: nil)]), space]
        }
        for record in a.outbox { b.receive(record) }
        a.outbox = []
        a.change(now: start.addingTimeInterval(60)) { $0.spaces.removeAll { $0.cloudID == cloud } }
        b.change(now: start.addingTimeInterval(120)) { workspace in
            let s = workspace.spaces.firstIndex { $0.cloudID == cloud }!
            let m = workspace.spaces[s].bookmarks.firstIndex { $0.id == mark }!
            workspace.spaces[s].bookmarks[m].title = "Hotel, booked"
        }
        for record in a.outbox { b.receive(record) }
        for record in b.outbox { a.receive(record) }
        for app in [a, b] {
            let trip = app.workspace.spaces.first { $0.cloudID == cloud }
            XCTAssertEqual(trip?.name, "Trip", "back on every device, as the edit inside it was later")
            XCTAssertEqual(trip?.bookmarks.map(\.title), ["Hotel, booked", "Train"])
        }
    }
}

private struct App {
    var workspace = Workspace(spaces: [])
    var mirror = SyncMirror()
    var clock: SyncClock
    var outbox: [SyncRecord] = []
    var sentBack = 0

    init(name: String) {
        clock = SyncClock(device: name)
    }

    /// Sync.queueChanges and Sync.commit.
    mutating func change(now: Date, _ edit: (inout Workspace) -> Void) {
        edit(&workspace)
        SyncPlan.assignIDs(&workspace)
        let next = SyncPlan.records(of: workspace, keeping: mirror)
        var (stamped, changed) = SyncPlan.stamp(next, over: mirror, clock: &clock, now: now)
        let back = stamped.settleSpaces()
        mirror = stamped
        outbox += (changed + back).compactMap { mirror.entry(named: $0) }
    }

    /// Sync.took and Sync.applyMirror.
    mutating func receive(_ record: SyncRecord) {
        for stamp in record.stamps.all { clock.see(stamp) }
        if mirror.merge(record), let back = mirror.entry(named: record.name) {
            outbox.append(back)
            sentBack += 1
        }
        outbox += mirror.settleSpaces().compactMap { mirror.entry(named: $0) }
        let applied = SyncPlan.apply(mirror, to: &workspace, deleted: mirror.removedSpaces)
        // Receiving an unpin preserves this device's ordinary tabs.
        workspace.spaces.removeAll { applied.removedSpaces.contains($0.id) }
    }

    /// What should match between devices: each synced space's name,
    /// bookmarks and pinned addresses.
    var face: [String: String] {
        var out: [String: String] = [:]
        for space in workspace.spaces {
            guard let cloud = space.cloudID?.uuidString else { continue }
            let pins = space.tabs.compactMap { $0.pinned?.absoluteString }
            out[cloud] = "\(space.name) | \(Self.describe(space.bookmarks)) | \(pins)"
        }
        return out
    }

    private static func describe(_ list: [Bookmark]) -> String {
        list.map { item in
            if let children = item.children { return "\(item.id.uuidString.prefix(4)):\(item.title)[\(describe(children))]" }
            return "\(item.id.uuidString.prefix(4)):\(item.title)=\(item.url?.absoluteString ?? "")"
        }.joined(separator: ",")
    }

    mutating func randomChange(_ random: inout Random, now: Date) {
        guard !workspace.spaces.isEmpty else { return }
        let s = random.int(workspace.spaces.count)
        let word = random.word()
        let pick = random.int(10)
        change(now: now) { workspace in
            switch pick {
            case 0:
                workspace.spaces[s].name = word
            case 1:
                workspace.spaces.append(Space(name: word, symbol: "star", tabs: [TabRecord(url: nil)]))
            case 2:
                if workspace.spaces.count > 1 { workspace.spaces.remove(at: s) }
            case 3, 4:
                workspace.spaces[s].bookmarks.append(Bookmark(title: word, url: URL(string: "https://\(word).example")!))
            case 5:
                if !workspace.spaces[s].bookmarks.isEmpty { workspace.spaces[s].bookmarks[0].title = word }
            case 6:
                if !workspace.spaces[s].bookmarks.isEmpty { workspace.spaces[s].bookmarks.removeLast() }
            case 7:
                // A bookmark moved into a new folder.
                if let first = workspace.spaces[s].bookmarks.first, !first.isFolder {
                    workspace.spaces[s].bookmarks[0] = Bookmark(folder: word, children: [first])
                }
            case 8:
                let url = URL(string: "https://\(word).example/pinned")!
                workspace.spaces[s].tabs.append(TabRecord(url: url, title: word, pinned: url))
            default:
                if let pin = workspace.spaces[s].tabs.lastIndex(where: \.isPinned) { workspace.spaces[s].tabs.remove(at: pin) }
            }
        }
    }
}
