import XCTest
@testable import PadCore

final class PinchTests: XCTestCase {
    func testSpreadingZoomsInWithANegativeDelta() {
        XCTAssertLessThan(Pinch.wheelDelta(step: 1.1), 0)
        XCTAssertGreaterThan(Pinch.wheelDelta(step: 0.9), 0)
        XCTAssertEqual(Pinch.wheelDelta(step: 1), 0)
    }

    func testDoublingSendsChromesAmount() {
        XCTAssertEqual(Pinch.wheelDelta(step: 2), -69.3147, accuracy: 0.001)
    }

    func testStepsAddUpToTheWholePinch() {
        let split = Pinch.wheelDelta(step: 1.1) + Pinch.wheelDelta(step: 1.1)
        XCTAssertEqual(split, Pinch.wheelDelta(step: 1.21), accuracy: 1e-9)
    }

    func testNonsenseScalesSendNothing() {
        XCTAssertEqual(Pinch.wheelDelta(step: 0), 0)
        XCTAssertEqual(Pinch.wheelDelta(step: -1), 0)
        XCTAssertEqual(Pinch.wheelDelta(step: .infinity), 0)
    }
}

final class WheelTests: XCTestCase {
    func testFingersUpScrollDown() {
        let delta = Wheel.delta(translationX: 3, translationY: -10)
        XCTAssertEqual(delta.x, -3)
        XCTAssertEqual(delta.y, 10)
    }
}

final class MomentumTests: XCTestCase {
    func testGlideSlowsAndEnds() {
        var glide = Momentum(velocityX: 0, velocityY: 2000)
        var total = 0.0
        var steps = 0
        var last = Double.infinity
        while let step = glide.advance(by: 1.0 / 60) {
            XCTAssertLessThan(step.y, last)
            last = step.y
            total += step.y
            steps += 1
            XCTAssertLessThan(steps, 10_000)
        }
        XCTAssertTrue(glide.isDone)
        // Under exponential decay the whole glide comes to v / -ln(rate) / 1000.
        let whole = 2000 / (-Foundation.log(0.998) * 1000)
        XCTAssertEqual(total, whole, accuracy: whole * 0.01)
    }

    func testFrameRateDoesNotChangeTheDistance() {
        func distance(_ frame: Double) -> Double {
            var glide = Momentum(velocityX: 1500, velocityY: 0)
            var total = 0.0
            while let step = glide.advance(by: frame) { total += step.x }
            return total
        }
        XCTAssertEqual(distance(1.0 / 60), distance(1.0 / 120), accuracy: 2)
    }

    func testSlowReleaseDoesNotGlide() {
        var glide = Momentum(velocityX: 5, velocityY: 5)
        XCTAssertNil(glide.advance(by: 1.0 / 60))
    }
}

final class ZoomLockTests: XCTestCase {
    func testHeldAtOne() {
        XCTAssertEqual(ZoomLock.scale(webKitMinimum: 1), 1)
        XCTAssertEqual(ZoomLock.scale(webKitMinimum: 1.5), 1)
        XCTAssertEqual(ZoomLock.scale(webKitMinimum: nil), 1)
        XCTAssertEqual(ZoomLock.scale(webKitMinimum: 0), 1)
    }

    func testANarrowWindowKeepsWebKitsFit() {
        XCTAssertEqual(ZoomLock.scale(webKitMinimum: 0.78), 0.78)
    }
}
