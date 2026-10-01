import Foundation

/// The arithmetic behind the pointer bridges, kept apart from UIKit so it can
/// be tested anywhere.
public enum Pinch {
    /// The wheel delta Chrome sends for one step of a trackpad pinch on a
    /// Mac: minus `factor` times the natural log of the step's scale, with
    /// ctrlKey set. Negative zooms in. Steps add up: two steps of 1.1 send the
    /// same total as one of 1.21.
    public static func wheelDelta(step: Double, factor: Double = 100) -> Double {
        guard step > 0, step.isFinite else { return 0 }
        return -factor * Foundation.log(step)
    }
}

public enum Wheel {
    /// A two-finger pan as the wheel delta a Mac sends for the same swipe.
    /// With natural scrolling the content follows the fingers, so fingers
    /// moving up (y falling) scroll down, a positive deltaY.
    public static func delta(translationX dx: Double, translationY dy: Double) -> (x: Double, y: Double) {
        (-dx, -dy)
    }
}

/// The glide after the fingers leave the trackpad, which a Mac's trackpad
/// sends as more wheel events and an iPad pan doesn't send at all.
///
/// The speed falls the way a UIScrollView's does at its normal deceleration
/// rate, 0.998 for each millisecond, and the glide ends below `stopSpeed`.
public struct Momentum: Equatable, Sendable {
    public var velocityX: Double
    public var velocityY: Double
    public var rate: Double
    public var stopSpeed: Double

    /// Velocities in wheel units (points) per second.
    public init(velocityX: Double, velocityY: Double, rate: Double = 0.998, stopSpeed: Double = 12) {
        self.velocityX = velocityX
        self.velocityY = velocityY
        self.rate = rate
        self.stopSpeed = stopSpeed
    }

    public var isDone: Bool {
        (velocityX * velocityX + velocityY * velocityY).squareRoot() < stopSpeed
    }

    /// The distance covered in the next `seconds`, or nil once the glide is over.
    public mutating func advance(by seconds: Double) -> (x: Double, y: Double)? {
        guard !isDone, seconds > 0 else { return nil }
        let milliseconds = seconds * 1000
        let decay = Foundation.pow(rate, milliseconds)
        // The distance under exponential decay, not speed times time: the
        // same total whatever the frame rate.
        let k = Foundation.log(rate) * 1000
        let travelled = (decay - 1) / k
        let step = (velocityX * travelled, velocityY * travelled)
        velocityX *= decay
        velocityY *= decay
        return step
    }
}

/// Where the zoom is held.
///
/// At 1: no pinch, double tap or anything else zooms the page itself. The
/// exception is a window narrower than the page's desktop layout, which
/// WebKit can make wider than a narrow window (a portrait iPad, a small Stage
/// Manager window) and then scale down to fit. There WebKit's fit is kept,
/// the smallest scale it allows, so the whole page stays in view instead of
/// being cut off at the window's edge with no way to scroll to the rest.
public enum ZoomLock {
    public static func scale(webKitMinimum: Double?) -> Double {
        guard let minimum = webKitMinimum, minimum > 0, minimum.isFinite else { return 1 }
        return min(1, minimum)
    }
}
