import UIKit

/// The phone's tabs, as a sheet the bar turns into. A swipe up on the bar
/// draws the sheet's top edge up under the finger, the bar riding on that
/// edge and fading as the tabs come in; let go and it carries on at the
/// finger's speed to open, or sinks back into the bar. A swipe down on it
/// (on its title, or on the tabs scrolled to the top) is the way back, and
/// so are Done, a tab, a tap above it and Escape.
///
/// Not UIKit's sheet: that can't be drawn up by a finger before it is
/// presented, and it rises from the bottom of the screen, not out of the
/// bar. A spring of its own moves it, so a touch can catch it anywhere on
/// the way and the throw that ends a drag carries on at the same speed.
@MainActor
final class TabSheet: UIViewController, UIGestureRecognizerDelegate {
    /// How far along: 0 is the bar, 1 the sheet open.
    private(set) var progress: CGFloat = 0
    /// Back in the bar, for its owner to take it away.
    var closed: (() -> Void)?

    private let content: UIViewController
    private weak var bar: UIView?
    private let dim = UIView()
    private let sheet = UIView()
    private let ground = UIView()
    private lazy var pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
    private weak var scroller: UIScrollView?

    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    /// In progress a second.
    private var velocity: CGFloat = 0
    private var target: CGFloat = 0
    private var response: CGFloat = 0.4
    private var damping: CGFloat = 1
    private var dragFrom: CGFloat = 0
    private var dragging = false
    /// The finger last moved it, rather than a button.
    private var wasDragged = false
    /// Whether letting go where the finger is would open it: a tick as that changes.
    private var wouldOpen = false
    private var landed = false
    /// Firm enough to feel through a case: a medium tap where letting go
    /// changes what happens, a rigid knock as the sheet lands open.
    private let tick = UIImpactFeedbackGenerator(style: .medium)
    private let thud = UIImpactFeedbackGenerator(style: .rigid)
    private let sink = UIImpactFeedbackGenerator(style: .light)

    /// The sheet's top corners, as a large sheet's are.
    private static let radius: CGFloat = 32
    /// How far it must be drawn for a slow let-go to open it: under halfway,
    /// as the sheet is most of the screen and a thumb from the bottom reaches
    /// so far. Back down the same way to close.
    private static let commit: CGFloat = 0.3

    init(content: UIViewController, bar: UIView) {
        self.content = content
        self.bar = bar
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        // VoiceOver stays in the sheet, as it would in a presented one.
        view.accessibilityViewIsModal = true
        dim.backgroundColor = .black
        dim.alpha = 0
        dim.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tappedAbove)))
        view.addSubview(dim)
        sheet.clipsToBounds = true
        sheet.layer.cornerRadius = Self.radius
        sheet.layer.cornerCurve = .continuous
        sheet.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        // The overview's own tray, so nothing changes colour as the tabs come in.
        ground.backgroundColor = Palette.UI.tray
        sheet.addSubview(ground)
        addChild(content)
        sheet.addSubview(content.view)
        content.didMove(toParent: self)
        view.addSubview(sheet)
        pan.delegate = self
        sheet.addGestureRecognizer(pan)
        apply()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        apply()
    }

    override func accessibilityPerformEscape() -> Bool {
        close()
        return true
    }

    // MARK: Moving it

    func open() {
        thud.prepare()
        settle(to: 1, velocity: velocity, bouncy: false)
    }

    func close() {
        settle(to: 0, velocity: velocity, bouncy: false)
    }

    /// Straight back into the bar, as when the window stops being a phone's.
    func closeNow() {
        stop()
        target = 0
        progress = 0
        apply()
        arrived()
    }

    /// A finger has it, from the bar or the sheet: wherever it is now, even on the way.
    func beginDrag() {
        stop()
        dragging = true
        wasDragged = true
        dragFrom = progress
        wouldOpen = progress > 0.5
        content.view.isUserInteractionEnabled = false
        tick.prepare()
        thud.prepare()
        sink.prepare()
    }

    /// `up`: how far the finger has gone up since it took hold, in points.
    func drag(up: CGFloat) {
        guard dragging else { return }
        let p = dragFrom + up / distance
        // Past open it gives less and less, as a scroll view's edge does.
        progress = p > 1 ? 1 + Self.rubberband(p - 1, range: 0.06) : max(0, p)
        let opens = progress > (dragFrom > 0.5 ? 1 - Self.commit : Self.commit)
        if opens != wouldOpen {
            wouldOpen = opens
            tick.impactOccurred(intensity: opens ? 1 : 0.7)
        }
        apply()
    }

    /// `up`: the finger's speed upward as it let go, in points a second.
    func release(up speed: CGFloat) {
        guard dragging else { return }
        dragging = false
        // Where a throw would come to rest, as Apple projects a scroll's.
        let rate: CGFloat = 0.998
        let projected = progress + speed / 1000 * rate / (1 - rate) / distance
        // A flick goes the way it was going; a slow let-go, to the nearer end.
        // Closing, the same distance down from open.
        let line = dragFrom > 0.5 ? 1 - Self.commit : Self.commit
        let opens = speed > 300 || (speed > -300 && projected > line)
        settle(to: opens ? 1 : 0, velocity: speed / distance, bouncy: abs(speed) > 300)
    }

    private func settle(to end: CGFloat, velocity: CGFloat, bouncy: Bool) {
        target = end
        self.velocity = velocity
        // A little give only when a throw sent it; critically damped otherwise.
        damping = bouncy && end == 1 ? 0.86 : 1
        response = end == 1 ? 0.42 : 0.36
        landed = progress >= 0.99 && end == 1
        content.view.isUserInteractionEnabled = false
        if UIAccessibility.isReduceMotionEnabled {
            // A fade in place of the rise.
            stop()
            UIView.transition(with: view.superview ?? view, duration: 0.25,
                              options: [.transitionCrossDissolve, .allowUserInteraction]) {
                self.progress = end
                self.apply()
            } completion: { _ in
                if end == 1, !self.landed { self.thud.impactOccurred(intensity: 1) }
                self.arrived()
            }
            return
        }
        guard link == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(step(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
        last = CACurrentMediaTime()
    }

    /// One frame of the spring, from Apple's two numbers: how quickly it
    /// gets there (response) and how much it overshoots (damping).
    @objc private func step(_ link: CADisplayLink) {
        let now = link.targetTimestamp
        let dt = CGFloat(min(max(now - last, 0), 1.0 / 30))
        last = now
        let stiffness = pow(2 * .pi / response, 2)
        let friction = 4 * .pi * damping / response
        // A few small steps a frame keep a stiff spring steady.
        let steps = 8
        let h = dt / CGFloat(steps)
        for _ in 0..<steps {
            velocity += (-stiffness * (progress - target) - friction * velocity) * h
            progress += velocity * h
        }
        // The soft knock of the sheet arriving: the moment it gets there.
        if target == 1, !landed, progress >= 0.99 {
            landed = true
            thud.impactOccurred(intensity: 1)
        }
        if abs(progress - target) < 0.0005, abs(velocity) < 0.005 {
            progress = target
            stop()
            apply()
            arrived()
            return
        }
        apply()
    }

    private func stop() {
        link?.invalidate()
        link = nil
    }

    private func arrived() {
        // Back in the bar after a drag or a throw: a lighter knock than opening's.
        if target == 0, wasDragged { sink.impactOccurred(intensity: 0.8) }
        wasDragged = false
        if target == 1 {
            content.view.isUserInteractionEnabled = true
            // Known before a swipe down on the tabs, so the two gestures can share it.
            if scroller == nil { scroller = Self.largestScroller(in: content.view) }
            UIAccessibility.post(notification: .screenChanged, argument: content.view)
        } else {
            closed?()
        }
    }

    // MARK: Drawing it

    /// The bar's top at rest: from its centre, which its transform leaves alone.
    private var rest: CGFloat {
        guard let bar else { return view.bounds.height }
        return bar.center.y - bar.bounds.height / 2
    }

    /// The sheet's top, open.
    private var openTop: CGFloat {
        view.safeAreaInsets.top + 10
    }

    /// How far the top edge goes, bar to open.
    private var distance: CGFloat {
        max(1, rest - openTop)
    }

    /// Everything from `progress` alone, so a frame of the spring and a
    /// frame of the finger draw it the same way.
    private func apply() {
        let bounds = view.bounds
        let top = rest - distance * progress
        dim.frame = bounds
        dim.alpha = 0.3 * min(max(progress, 0), 1)
        sheet.frame = CGRect(x: 0, y: top, width: bounds.width, height: max(0, bounds.height - top))
        ground.frame = sheet.bounds
        // The bar's blur gives way to the sheet's ground, then the tabs come in.
        ground.alpha = Self.ramp(progress, from: 0, to: 0.2)
        content.view.alpha = Self.ramp(progress, from: 0.1, to: 0.45)
        // At its open size all the way, riding the top edge, so nothing in it
        // lays out again on the way; it ends above the Home indicator.
        content.view.frame = CGRect(x: 0, y: 0, width: bounds.width,
                                    height: max(0, bounds.height - openTop - view.safeAreaInsets.bottom))
        guard let bar else { return }
        // The bar rides the top edge as it fades: the bar is what becomes the sheet.
        bar.transform = CGAffineTransform(translationX: 0, y: top - rest)
        bar.alpha = 1 - Self.ramp(progress, from: 0, to: 0.15)
        // Back in reach as it sinks home, so a swipe can catch it again.
        bar.isUserInteractionEnabled = progress < 0.05
    }

    /// 0 before `from`, 1 after `to`, straight between.
    private static func ramp(_ value: CGFloat, from: CGFloat, to: CGFloat) -> CGFloat {
        min(max((value - from) / (to - from), 0), 1)
    }

    /// Apple's rubber band: one to one at first, never past `range`.
    private static func rubberband(_ distance: CGFloat, range: CGFloat) -> CGFloat {
        distance * range * 0.55 / (range + 0.55 * distance)
    }

    // MARK: Gestures

    @objc private func tappedAbove() {
        close()
    }

    @objc private func panned(_ pan: UIPanGestureRecognizer) {
        switch pan.state {
        case .began:
            // The tabs hold still while the sheet moves: their scroll lets go.
            if let scroller {
                scroller.panGestureRecognizer.isEnabled = false
                scroller.panGestureRecognizer.isEnabled = true
            }
            beginDrag()
        case .changed:
            drag(up: -pan.translation(in: view).y)
        case .ended:
            release(up: -pan.velocity(in: view).y)
        case .cancelled, .failed:
            release(up: 0)
        default:
            break
        }
    }

    func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
        guard gesture === pan else { return true }
        let v = pan.velocity(in: view)
        guard abs(v.y) > abs(v.x) else { return false }
        // Caught on the way, either way.
        if link != nil || progress < 1 { return true }
        guard v.y > 0 else { return false }
        if scroller == nil { scroller = Self.largestScroller(in: content.view) }
        guard let scroller else { return true }
        // Down from the title, or from the tabs already at their top.
        let atTop = scroller.contentOffset.y <= -scroller.adjustedContentInset.top + 1
        let onTitle = pan.location(in: scroller).y - scroller.contentOffset.y < scroller.adjustedContentInset.top
        return atTop || onTitle
    }

    func gestureRecognizer(_ gesture: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        gesture === pan && other === scroller?.panGestureRecognizer
    }

    /// The tabs' scroll view: SwiftUI's ScrollView is a UIScrollView underneath.
    private static func largestScroller(in root: UIView) -> UIScrollView? {
        var best: UIScrollView?
        var queue = [root]
        while !queue.isEmpty {
            let next = queue.removeFirst()
            if let scroll = next as? UIScrollView,
               scroll.bounds.width * scroll.bounds.height > (best.map { $0.bounds.width * $0.bounds.height } ?? 0) {
                best = scroll
            }
            queue.append(contentsOf: next.subviews)
        }
        return best
    }
}
