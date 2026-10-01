import XCTest
@testable import PadCore

final class FreezerTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_000_000)

    func tab(_ heavy: Bool, onScreen: Bool = false, live: Bool = true, ago: TimeInterval, stay: Bool = false) -> TabLoad {
        TabLoad(id: UUID(), heavy: heavy, onScreen: onScreen, live: live, lastShown: now.addingTimeInterval(-ago), mustStay: stay)
    }

    func testOneHeavyTabStaysLiveThatIsTheOneOnScreen() {
        let shown = tab(true, onScreen: true, ago: 0)
        let older = tab(true, ago: 60)
        let plan = Freezer.plan([shown, older], limits: LiveLimits(), pressure: false)
        XCTAssertEqual(plan, [older.id])
    }

    func testTheLastHeavyTabStaysLiveBehindALightOne() {
        // From a design file to Slack and back: the file is still open.
        let slack = tab(false, onScreen: true, ago: 0)
        let file = tab(true, ago: 30)
        let olderFile = tab(true, ago: 600)
        let plan = Freezer.plan([slack, file, olderFile], limits: LiveLimits(), pressure: false)
        XCTAssertEqual(plan, [olderFile.id])
    }

    func testLightTabsBeyondTheirRoomFreezeOldestFirst() {
        let shown = tab(false, onScreen: true, ago: 0)
        let a = tab(false, ago: 10)
        let b = tab(false, ago: 20)
        let c = tab(false, ago: 30)
        let d = tab(false, ago: 40)
        let plan = Freezer.plan([shown, d, b, a, c], limits: LiveLimits(heavy: 1, lightOffScreen: 2), pressure: false)
        XCTAssertEqual(plan, [d.id, c.id])
    }

    func testZeroRoomFreezesEveryTabOffScreen() {
        let shown = tab(true, onScreen: true, ago: 0)
        let light = tab(false, ago: 10)
        let heavy = tab(true, ago: 20)
        let plan = Freezer.plan([shown, light, heavy], limits: LiveLimits(heavy: 1, lightOffScreen: 0), pressure: false)
        XCTAssertEqual(Set(plan), [light.id, heavy.id])
    }

    func testTabsOnScreenNeverFreezeEvenTwoHeavyOnes() {
        let left = tab(true, onScreen: true, ago: 0)
        let right = tab(true, onScreen: true, ago: 5)
        XCTAssertEqual(Freezer.plan([left, right], limits: LiveLimits(), pressure: true), [])
    }

    func testPressureFreezesEverythingOffScreenThatCanGo() {
        let shown = tab(false, onScreen: true, ago: 0)
        let file = tab(true, ago: 10)
        let call = tab(false, ago: 20, stay: true)
        let frozen = tab(false, live: false, ago: 30)
        let light = tab(false, ago: 40)
        let plan = Freezer.plan([shown, file, call, frozen, light], limits: LiveLimits(), pressure: true)
        XCTAssertEqual(plan, [light.id, file.id])
    }

    func testTabsThatMustStayStillTakeTheirRoom() {
        let shown = tab(false, onScreen: true, ago: 0)
        let call = tab(false, ago: 5, stay: true)
        let a = tab(false, ago: 10)
        let b = tab(false, ago: 20)
        let plan = Freezer.plan([shown, call, a, b], limits: LiveLimits(heavy: 1, lightOffScreen: 2), pressure: false)
        XCTAssertEqual(plan, [b.id])
    }
}

final class CrashGuardTests: XCTestCase {
    func testReloadsUntilItKeepsEnding() {
        var guardian = CrashGuard(limit: 3, window: 60)
        let start = Date(timeIntervalSince1970: 0)
        XCTAssertTrue(guardian.shouldReload(at: start))
        XCTAssertTrue(guardian.shouldReload(at: start.addingTimeInterval(10)))
        XCTAssertFalse(guardian.shouldReload(at: start.addingTimeInterval(20)))
    }

    func testEndingsFarApartAlwaysReload() {
        var guardian = CrashGuard(limit: 3, window: 60)
        let start = Date(timeIntervalSince1970: 0)
        for minute in 0..<10 {
            XCTAssertTrue(guardian.shouldReload(at: start.addingTimeInterval(Double(minute) * 61)))
        }
    }

    func testResetStartsOver() {
        var guardian = CrashGuard(limit: 2, window: 60)
        let start = Date(timeIntervalSince1970: 0)
        XCTAssertTrue(guardian.shouldReload(at: start))
        XCTAssertFalse(guardian.shouldReload(at: start.addingTimeInterval(1)))
        guardian.reset()
        XCTAssertTrue(guardian.shouldReload(at: start.addingTimeInterval(2)))
    }
}
