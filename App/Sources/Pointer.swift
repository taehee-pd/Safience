import PadCore
import QuartzCore
import UIKit

/// The trackpad, as a Mac's WebKit would hand it to the page.
///
/// Hover, click and move are WebKit's own: on iPad it already sends a page
/// mouse and pointer events for them. What it doesn't send is a pinch on the
/// trackpad (it zooms the whole page instead, which is off here), and, with
/// its own scrolling off, maybe not two fingers moving either. So:
///
/// - The cursor's position comes from a hover recognizer: wheel events need
///   a place on the page, and a pinch has no pointer position of its own.
/// - A pinch on the trackpad, and only the trackpad (`.indirectPointer`, a
///   finger pinch on the glass is not one), becomes wheel events with
///   ctrlKey at the cursor: what Chrome sends for a pinch, and what Figma
///   and other canvas apps zoom on (Pinch.wheelDelta).
/// - Two fingers with ⌘ held zoom the same way.
/// - Two fingers alone become wheel events too (the wheel bridge), unless
///   WebKit is sending the page its own, which bridge.js checks event by
///   event; a release with speed glides on, as on a Mac.
@MainActor
final class Pointer: NSObject, UIGestureRecognizerDelegate {
    private weak var page: Page?
    private let hover: UIHoverGestureRecognizer
    private let pinch: UIPinchGestureRecognizer
    private let scroll: UIPanGestureRecognizer

    /// Where the cursor last was over the page, in the page view's points.
    private(set) var cursor: CGPoint?
    private var lastScale: CGFloat = 1
    private var lastTranslation: CGPoint = .zero
    /// This pan's own: whether it is a scroll at all (not a click-drag),
    /// whether WebKit's wheel events were arriving, whether any of it
    /// zoomed, how many steps it had, and where the last one was sent.
    private var isScroll = false
    private var webKitScrolls = false
    private var zoomed = false
    private var steps = 0
    private var lastPoint: CGPoint = .zero

    private var glide: Momentum?
    private var link: CADisplayLink?
    private var lastTick: CFTimeInterval = 0

    init(page: Page) {
        self.page = page
        hover = UIHoverGestureRecognizer()
        pinch = UIPinchGestureRecognizer()
        scroll = UIPanGestureRecognizer()
        super.init()
        hover.addTarget(self, action: #selector(hovered(_:)))
        pinch.addTarget(self, action: #selector(pinched(_:)))
        scroll.addTarget(self, action: #selector(scrolled(_:)))
        let pointer = [NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)]
        pinch.allowedTouchTypes = pointer
        // Scroll events, from a trackpad or a mouse wheel. Fingers on the
        // glass never reach it; a click-drag with the pointer does, and is
        // told apart in scrolled(_:) by having a touch, which a scroll
        // doesn't. Either stays the page's.
        scroll.allowedScrollTypesMask = .all
        scroll.allowedTouchTypes = pointer
        for recognizer in [hover, pinch, scroll] as [UIGestureRecognizer] {
            recognizer.delegate = self
            recognizer.cancelsTouchesInView = false
            recognizer.delaysTouchesBegan = false
            recognizer.delaysTouchesEnded = false
            page.view.addGestureRecognizer(recognizer)
        }
    }

    func stop() {
        stopGlide()
        for recognizer in [hover, pinch, scroll] as [UIGestureRecognizer] {
            recognizer.view?.removeGestureRecognizer(recognizer)
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }

    // MARK: The cursor

    @objc private func hovered(_ recognizer: UIHoverGestureRecognizer) {
        switch recognizer.state {
        case .began, .changed:
            cursor = recognizer.location(in: recognizer.view)
        default:
            // Gone from the page, or hidden while typing: the gestures' own
            // location stands in until it is back.
            cursor = nil
        }
    }

    private func place(of recognizer: UIGestureRecognizer) -> CGPoint {
        cursor ?? recognizer.location(in: recognizer.view)
    }

    // MARK: Pinch

    @objc private func pinched(_ recognizer: UIPinchGestureRecognizer) {
        guard let page, page.bridges.pinch else { return }
        switch recognizer.state {
        case .began:
            stopGlide()
            lastScale = 1
            send(pinch: recognizer)
        case .changed:
            send(pinch: recognizer)
        default:
            lastScale = 1
        }
    }

    private func send(pinch recognizer: UIPinchGestureRecognizer) {
        guard let page, lastScale > 0 else { return }
        let step = Double(recognizer.scale / lastScale)
        lastScale = recognizer.scale
        let delta = Pinch.wheelDelta(step: step, factor: page.bridges.pinchFactor)
        guard delta != 0 else { return }
        page.stats.pinchSteps += 1
        page.wheel(at: place(of: recognizer), dx: 0, dy: delta, modifiers: recognizer.modifierFlags,
                   zoom: true, guarded: "pinch")
    }

    // MARK: Two fingers

    @objc private func scrolled(_ recognizer: UIPanGestureRecognizer) {
        guard let page, let view = recognizer.view else { return }
        switch recognizer.state {
        case .began:
            isScroll = recognizer.numberOfTouches == 0
            guard isScroll else { return }
            stopGlide()
            lastTranslation = .zero
            webKitScrolls = false
            zoomed = false
            steps = 0
            moved(recognizer, in: view)
        case .changed:
            guard isScroll else { return }
            moved(recognizer, in: view)
        case .ended:
            // A glide follows a swipe on the trackpad, not a notch or two of
            // a mouse wheel, which ends after a step or two.
            guard isScroll, !zoomed, !webKitScrolls, steps >= 3, page.bridges.wheel != .off else { return }
            let velocity = recognizer.velocity(in: view)
            let speed = Wheel.delta(translationX: Double(velocity.x), translationY: Double(velocity.y))
            startGlide(Momentum(velocityX: speed.x, velocityY: speed.y))
        default:
            break
        }
    }

    private func moved(_ recognizer: UIPanGestureRecognizer, in view: UIView) {
        guard let page else { return }
        let translation = recognizer.translation(in: view)
        let delta = Wheel.delta(translationX: Double(translation.x - lastTranslation.x),
                                translationY: Double(translation.y - lastTranslation.y))
        lastTranslation = translation
        guard delta.x != 0 || delta.y != 0 else { return }
        let point = place(of: recognizer)
        lastPoint = point
        steps += 1
        // ⌘ is read at every step, as a Mac reads it with every wheel event.
        if page.bridges.commandZoom && recognizer.modifierFlags.contains(.command) {
            zoomed = true
            // ⌘ itself is not passed on: the page sees a pinch.
            page.stats.commandZoomSteps += 1
            page.wheel(at: point, dx: 0, dy: delta.y, modifiers: recognizer.modifierFlags.subtracting(.command),
                       zoom: true, guarded: "scroll") { [weak self] outcome in
                if outcome == "native" { self?.webKitScrolls = true }
            }
            return
        }
        guard page.bridges.wheel != .off else { return }
        page.wheel(at: point, dx: delta.x, dy: delta.y, modifiers: recognizer.modifierFlags,
                   zoom: false, guarded: "scroll") { [weak self] outcome in
            if outcome == "native" { self?.webKitScrolls = true }
        }
    }

    // MARK: The glide after the fingers leave

    private func startGlide(_ momentum: Momentum) {
        guard !momentum.isDone else { return }
        glide = momentum
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
        lastTick = 0
    }

    private func stopGlide() {
        link?.invalidate()
        link = nil
        glide = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        guard let page, var glide else {
            stopGlide()
            return
        }
        let now = link.timestamp
        let elapsed = lastTick == 0 ? link.duration : now - lastTick
        lastTick = now
        guard let step = glide.advance(by: elapsed) else {
            stopGlide()
            return
        }
        self.glide = glide
        page.wheel(at: cursor ?? lastPoint, dx: step.x, dy: step.y, modifiers: [], zoom: false, guarded: "scroll")
    }
}

/// Holds the page's zoom where ZoomLock says, whatever tries to change it:
/// the scroll view's pinch is off, and anything else that zooms (a double
/// tap a page didn't turn off, WebKit zooming in on a field) is set back.
@MainActor
final class ZoomHold: NSObject {
    private weak var scrollView: UIScrollView?
    private var observations: [NSKeyValueObservation] = []
    private var holding = false

    init(_ scrollView: UIScrollView) {
        self.scrollView = scrollView
        super.init()
        let changed: @Sendable (UIScrollView, NSKeyValueObservedChange<CGFloat>) -> Void = { [weak self] _, _ in
            DispatchQueue.main.async { self?.hold() }
        }
        observations = [
            scrollView.observe(\.zoomScale, changeHandler: changed),
            scrollView.observe(\.minimumZoomScale, changeHandler: changed),
            scrollView.observe(\.maximumZoomScale, changeHandler: changed),
        ]
    }

    func hold() {
        guard let scrollView, !holding else { return }
        holding = true
        defer { holding = false }
        scrollView.pinchGestureRecognizer?.isEnabled = false
        scrollView.bouncesZoom = false
        let target = CGFloat(ZoomLock.scale(webKitMinimum: Double(scrollView.minimumZoomScale)))
        if abs(scrollView.zoomScale - target) > 0.001 {
            scrollView.setZoomScale(target, animated: false)
        }
    }
}
