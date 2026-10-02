import PadCore
import QuartzCore
import UIKit
import UIKit.UIGestureRecognizerSubclass

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
/// - A page's own cursor picture, which WebKit on iPad never shows, is
///   drawn where the pointer is, over the hidden system pointer (below).
@MainActor
final class Pointer: NSObject, UIGestureRecognizerDelegate, UIPointerInteractionDelegate {
    private weak var page: Page?
    private let hover: UIHoverGestureRecognizer
    private let pinch: UIPinchGestureRecognizer
    private let scroll: UIPanGestureRecognizer
    private let press: PressWatcher

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

    /// The page's own cursor: the one it asks for, the pictures it has sent
    /// by bridge.js's id, the view that draws the one showing, and the
    /// interaction that hides the system pointer while it shows.
    private(set) var pageCursor: PageCursor = .system
    private var pictures: [Int: CursorPicture] = [:]
    private let drawn = UIImageView()
    private var hider: UIPointerInteraction?
    private var hiding = false
    /// Where the pointer is while its button is down, which the hover
    /// recognizer doesn't follow; and when the hover recognizer last did.
    private var pressed: CGPoint?
    private var lastHover: CFTimeInterval = 0

    init(page: Page) {
        self.page = page
        hover = UIHoverGestureRecognizer()
        pinch = UIPinchGestureRecognizer()
        scroll = UIPanGestureRecognizer()
        press = PressWatcher()
        super.init()
        hover.addTarget(self, action: #selector(hovered(_:)))
        pinch.addTarget(self, action: #selector(pinched(_:)))
        scroll.addTarget(self, action: #selector(scrolled(_:)))
        let pointer = [NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)]
        press.allowedTouchTypes = pointer
        press.moved = { [weak self] point in self?.pressMoved(point) }
        pinch.allowedTouchTypes = pointer
        // Scroll events, from a trackpad or a mouse wheel. Fingers on the
        // glass never reach it; a click-drag with the pointer does, and is
        // told apart in scrolled(_:) by having a touch, which a scroll
        // doesn't. Either stays the page's.
        scroll.allowedScrollTypesMask = .all
        scroll.allowedTouchTypes = pointer
        for recognizer in [hover, pinch, scroll, press] as [UIGestureRecognizer] {
            recognizer.delegate = self
            recognizer.cancelsTouchesInView = false
            recognizer.delaysTouchesBegan = false
            recognizer.delaysTouchesEnded = false
            page.view.addGestureRecognizer(recognizer)
        }

        drawn.isUserInteractionEnabled = false
        drawn.isHidden = true
        drawn.accessibilityElementsHidden = true
        page.view.addSubview(drawn)
        let hider = UIPointerInteraction(delegate: self)
        hider.isEnabled = false
        page.view.addInteraction(hider)
        self.hider = hider
    }

    func stop() {
        stopGlide()
        for recognizer in [hover, pinch, scroll, press] as [UIGestureRecognizer] {
            recognizer.view?.removeGestureRecognizer(recognizer)
        }
        hideSystemPointer(false)
        if let hider { hider.view?.removeInteraction(hider) }
        hider = nil
        drawn.removeFromSuperview()
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
            lastHover = CACurrentMediaTime()
        default:
            // Gone from the page, or hidden while typing: the gestures' own
            // location stands in until it is back.
            cursor = nil
        }
        updateCursor()
    }

    /// The button went down, moved or came up (nil). On the way up the
    /// pointer is taken to stay where it was, until the hover recognizer
    /// says otherwise, so the page's cursor doesn't blink between the two.
    private func pressMoved(_ point: CGPoint?) {
        if let point {
            pressed = point
        } else if let last = pressed {
            pressed = nil
            cursor = page.map { $0.view.bounds.contains(last) } == true ? last : nil
            let released = CACurrentMediaTime()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self, self.pressed == nil, self.lastHover < released else { return }
                self.cursor = nil
                self.updateCursor()
            }
        }
        updateCursor()
    }

    // MARK: The page's own cursor

    /// What bridge.js says the page asks for under the pointer. A picture
    /// that doesn't decode, or one this page never sent, is the system's
    /// pointer: never no pointer at all.
    func show(_ asked: PageCursor) {
        var asked = asked
        if case .image(let image) = asked {
            if let png = image.png {
                if let picture = UIImage(data: png, scale: CGFloat(image.scale)) {
                    if pictures.count >= 128 { pictures.removeAll() }
                    pictures[image.id] = CursorPicture(
                        image: picture,
                        size: CGSize(width: image.width, height: image.height),
                        hotspot: CGPoint(x: image.hotspotX, y: image.hotspotY)
                    )
                } else {
                    asked = .system
                }
            } else if pictures[image.id] == nil {
                asked = .system
            }
        }
        pageCursor = asked
        updateCursor()
    }

    /// Over the page, the page's cursor: its picture drawn at the pointer,
    /// the system pointer hidden under it. Anywhere else, or for a keyword,
    /// the system pointer as WebKit chooses it.
    private func updateCursor() {
        let point = pressed ?? cursor
        var picture: CursorPicture?
        var hide = false
        if point != nil {
            switch pageCursor {
            case .system:
                break
            case .hidden:
                hide = true
            case .image(let image):
                picture = pictures[image.id]
                hide = picture != nil
            }
        }
        hideSystemPointer(hide)
        guard let point, let picture else {
            drawn.isHidden = true
            return
        }
        UIView.performWithoutAnimation {
            if drawn.image !== picture.image { drawn.image = picture.image }
            drawn.frame = CGRect(x: point.x - picture.hotspot.x, y: point.y - picture.hotspot.y,
                                 width: picture.size.width, height: picture.size.height)
            if drawn.isHidden {
                drawn.superview?.bringSubviewToFront(drawn)
                drawn.isHidden = false
            }
        }
    }

    /// WebKit's own pointer interactions choose the pointer over the page,
    /// and choose the system's whatever the page asks. While the page's own
    /// cursor shows they are turned off, so that this one, which hides the
    /// pointer, chooses instead; turned on again, the beam over text and the
    /// rest are WebKit's as before.
    private func hideSystemPointer(_ hide: Bool) {
        guard hide != hiding, let view = page?.view, let hider else { return }
        hiding = hide
        for interaction in Self.pointerInteractions(in: view) where interaction !== hider {
            interaction.isEnabled = !hide
        }
        hider.isEnabled = hide
        hider.invalidate()
    }

    private static func pointerInteractions(in view: UIView) -> [UIPointerInteraction] {
        view.interactions.compactMap { $0 as? UIPointerInteraction } + view.subviews.flatMap(pointerInteractions(in:))
    }

    func pointerInteraction(_ interaction: UIPointerInteraction, regionFor request: UIPointerRegionRequest,
                            defaultRegion: UIPointerRegion) -> UIPointerRegion? {
        defaultRegion
    }

    func pointerInteraction(_ interaction: UIPointerInteraction, styleFor region: UIPointerRegion) -> UIPointerStyle? {
        .hidden()
    }

    /// For Diagnostics.
    var cursorSummary: String {
        switch pageCursor {
        case .system:
            return "the system's"
        case .hidden:
            return "none, the pointer hidden"
        case .image(let image):
            guard let picture = pictures[image.id] else { return "the system's (picture missing)" }
            let size = "\(Int(picture.size.width))×\(Int(picture.size.height)) at \(Int(picture.hotspot.x)),\(Int(picture.hotspot.y))"
            return "the page's, \(size)\(hiding ? "" : ", pointer elsewhere")"
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

/// A page's cursor picture, ready to draw: its size and hotspot in points.
private struct CursorPicture {
    let image: UIImage
    let size: CGSize
    let hotspot: CGPoint
}

/// Follows the pointer while its button is down, a click or a drag, which
/// the hover recognizer doesn't. It never recognizes anything, so every
/// touch stays the page's.
private final class PressWatcher: UIGestureRecognizer {
    var moved: ((CGPoint?) -> Void)?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        report(touches)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        report(touches)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        moved?(nil)
        state = .failed
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        moved?(nil)
        state = .failed
    }

    private func report(_ touches: Set<UITouch>) {
        if let touch = touches.first { moved?(touch.location(in: view)) }
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
