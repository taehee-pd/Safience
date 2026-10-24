import UIKit
import UIKit.UIGestureRecognizerSubclass

/// The gap between a split's two cards (Browser.layoutPanes), drawn as the
/// frame's other gaps are: the window's ground shows through it, as round
/// the cards, and a short grip stands in its middle, as the Mac's. Under the
/// pointer, pressed or dragged, the grip grows and darkens; dragged, the
/// pages follow it; tapped twice, they are made even.
final class SplitDivider: UIView {
    /// As wide as the frame's other gaps: between the cards and the sidebar,
    /// and the window's edges.
    static let width = Side.bezel

    /// Where the drag is, across the stage.
    var moved: ((CGFloat) -> Void)?
    var ended: (() -> Void)?
    var centered: (() -> Void)?
    var adjusted: ((Int) -> Void)?
    var ratio = 0.5 {
        didSet { accessibilityValue = "Left page \(Int(ratio * 100)) percent" }
    }

    private let grip = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        grip.backgroundColor = Palette.UI.muted
        grip.layer.cornerCurve = .continuous
        grip.isUserInteractionEnabled = false
        addSubview(grip)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(dragged(_:)))
        // A second finger doesn't join a drag already going.
        pan.maximumNumberOfTouches = 1
        addGestureRecognizer(pan)
        let twice = UITapGestureRecognizer(target: self, action: #selector(tappedTwice))
        twice.numberOfTapsRequired = 2
        addGestureRecognizer(twice)
        addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hovered(_:))))
        isAccessibilityElement = true
        accessibilityLabel = "Split divider"
        accessibilityTraits = .adjustable
        accessibilityHint = "Double-tap to make the two pages even"
        isHidden = true
    }

    required init?(coder: NSCoder) {
        nil
    }

    /// The grip's three states, as the Mac's: at rest, faint and short; under
    /// the pointer, darker and taller; held, taller still. The press shows
    /// the moment the finger lands, before the drag has moved far enough to begin.
    private enum Grip { case rest, hover, held }

    private var hovering = false { didSet { show() } }
    private var pressed = false { didSet { show() } }
    private var dragging = false { didSet { show() } }
    private var shown = Grip.rest

    private var wanted: Grip {
        pressed || dragging ? .held : hovering ? .hover : .rest
    }

    /// A state change says the divider heard: quick, and a spring without
    /// bounce from wherever the grip is, so a press let go halfway through
    /// growing shrinks back from there. In place under Reduce Motion.
    private func show() {
        let state = wanted
        guard state != shown else { return }
        shown = state
        let change = {
            self.grip.backgroundColor = Palette.UI.muted
            self.setNeedsLayout()
            self.layoutIfNeeded()
        }
        guard !UIAccessibility.isReduceMotionEnabled else { return change() }
        UIView.animate(springDuration: 0.25, bounce: 0, options: [.beginFromCurrentState, .allowUserInteraction],
                       animations: change)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let height: CGFloat = switch shown {
        case .rest: 44
        case .hover: 64
        case .held: 80
        }
        let width: CGFloat = 3
        grip.frame = CGRect(x: (bounds.width - width) / 2, y: (bounds.height - height) / 2, width: width, height: height)
        grip.layer.cornerRadius = width / 2
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        pressed = true
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        pressed = false
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        pressed = false
    }

    /// The gap is narrow for a finger: ten points into each page take the
    /// drag too, at their very edges.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -(44 - bounds.width) / 2, dy: 0).contains(point)
    }

    @objc private func dragged(_ pan: UIPanGestureRecognizer) {
        switch pan.state {
        case .began:
            dragging = true
        case .changed:
            if let stage = superview { moved?(pan.location(in: stage).x) }
        case .ended, .cancelled, .failed:
            dragging = false
            ended?()
        default:
            break
        }
    }

    @objc private func hovered(_ hover: UIHoverGestureRecognizer) {
        hovering = hover.state == .began || hover.state == .changed
    }

    @objc private func tappedTwice() {
        centered?()
    }

    override func accessibilityActivate() -> Bool {
        centered?()
        return true
    }

    override func accessibilityIncrement() { adjusted?(1) }
    override func accessibilityDecrement() { adjusted?(-1) }
}

/// Where a tab dragged from the row along the top or the sidebar can go on
/// the page, as Dia's: a card at each side of the stage, and the one the
/// finger is over grown to the pane the tab will open as, ringed in the
/// space's colour. Over the pages only while a tab is dragged
/// (WindowModel.draggedTab): WebKit takes any drop over a page, so a place
/// to drop under the pages would never hear of it.
final class SplitDrop: UIView, UIDropInteractionDelegate {
    enum Half { case left, right }

    /// The split's area, and the pane the tab would be on each side, in this view.
    var area: CGRect = .zero
    var panes: (left: CGRect, right: CGRect) = (.zero, .zero)
    /// The space's colour, for the side the finger is over.
    var tint: UIColor = .tintColor
    /// The tab was let go over a half.
    var dropped: ((Half) -> Void)?
    /// The drag is over, wherever it ended: the layer can come off even if
    /// the row the tab came from has gone and can't say so.
    var ended: (() -> Void)?

    private let left = Zone(.left)
    private let right = Zone(.right)
    private var target: Half?
    /// The drag is over the stage: the zones show; or they are going.
    private var over = false
    private var fading = false
    private let tick = UISelectionFeedbackGenerator()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isHidden = true
        addSubview(left)
        addSubview(right)
        addInteraction(UIDropInteraction(delegate: self))
    }

    required init?(coder: NSCoder) {
        nil
    }

    /// Laid over the pages while a tab is dragged, or taken off once the
    /// zones have gone.
    func arm(_ armed: Bool) {
        if armed {
            isHidden = false
            isUserInteractionEnabled = true
        } else {
            isUserInteractionEnabled = false
            if !over, !fading { isHidden = true }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        place()
        accessibilityDropPointDescriptors = [left, right].map {
            UIAccessibilityLocationDescriptor(name: $0.name.text ?? "", point: CGPoint(x: $0.bounds.midX, y: $0.bounds.midY), in: $0)
        }
    }

    /// A half at rest: a tall card a little in from that edge of the area.
    private func rest(_ side: Half) -> CGRect {
        let width = min(max(area.width * 0.24, 120), 240)
        let height = min(area.height, max(area.height * 0.7, 200))
        let x = side == .left ? area.minX + 12 : area.maxX - 12 - width
        return CGRect(x: x, y: area.midY - height / 2, width: width, height: height)
    }

    private func place() {
        // The grown side over the other, which it covers in a window too
        // narrow for two panes.
        if let target { bringSubviewToFront(target == .left ? left : right) }
        // Bounds and centre, not the frame: a side coming in is scaled still.
        for (zone, frame) in [(left, target == .left ? panes.left : rest(.left)),
                              (right, target == .right ? panes.right : rest(.right))] {
            zone.bounds = CGRect(origin: .zero, size: frame.size)
            zone.center = CGPoint(x: frame.midX, y: frame.midY)
        }
        left.show(active: target == .left, tint: tint)
        right.show(active: target == .right, tint: tint)
        left.layoutIfNeeded()
        right.layoutIfNeeded()
    }

    /// The finger went from one side to another: the side grows to its pane,
    /// or back, quick and without bounce, and from wherever it was. In place
    /// under Reduce Motion, the colours fading.
    private func retarget(_ side: Half?) {
        guard side != target else { return }
        target = side
        if side != nil { tick.selectionChanged() }
        guard !UIAccessibility.isReduceMotionEnabled else {
            return UIView.transition(with: self, duration: 0.15, options: [.transitionCrossDissolve, .allowUserInteraction],
                                     animations: { self.place() })
        }
        UIView.animate(springDuration: 0.3, bounce: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.place()
        }
    }

    /// The page under a tab carried over it: a little darker, so the glass
    /// stands off a white page as well as a dark one.
    private static let dim = UIColor { $0.userInterfaceStyle == .dark ? UIColor.black.withAlphaComponent(0.3)
                                                                       : UIColor.black.withAlphaComponent(0.12) }

    /// The zones come in as the drag reaches the stage, a little smaller
    /// first, the page dimming under them, and go as it leaves, a side let
    /// go over going where it grew; the layer is taken off after them once
    /// the drag has ended.
    private func appear(_ shown: Bool) {
        over = shown
        fading = !shown
        let zones = [left, right]
        if shown, !UIAccessibility.isReduceMotionEnabled {
            for zone in zones where !zone.revealed { zone.transform = CGAffineTransform(scaleX: 0.96, y: 0.96) }
        }
        UIView.animate(springDuration: shown ? 0.25 : 0.2, bounce: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.backgroundColor = shown ? Self.dim : .clear
            for zone in zones {
                zone.reveal(shown)
                zone.transform = .identity
            }
        } completion: { _ in
            guard !self.over, self.fading else { return }
            self.fading = false
            self.target = nil
            self.place()
            if !self.isUserInteractionEnabled { self.isHidden = true }
        }
    }

    /// The outer two fifths of the area are each a side's; the middle is
    /// neither, so a tab can be carried across and let go there for nothing.
    private func side(at point: CGPoint) -> Half? {
        guard area.width > 0 else { return nil }
        let across = (point.x - area.minX) / area.width
        return across < 0.4 ? .left : across > 0.6 ? .right : nil
    }

    // MARK: UIDropInteractionDelegate

    func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
        session.localDragSession != nil && session.items.count == 1
    }

    func dropInteraction(_ interaction: UIDropInteraction, sessionDidEnter session: UIDropSession) {
        tick.prepare()
        appear(true)
    }

    func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession) -> UIDropProposal {
        let side = side(at: session.location(in: self))
        retarget(side)
        guard side != nil else { return UIDropProposal(operation: .cancel) }
        return UIDropProposal(operation: session.allowsMoveOperation ? .move : .copy)
    }

    func dropInteraction(_ interaction: UIDropInteraction, sessionDidExit session: UIDropSession) {
        retarget(nil)
        appear(false)
    }

    func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
        guard let target else { return }
        dropped?(target)
    }

    /// What was dragged goes into the middle of the pane it opens as, and
    /// shrinks there.
    func dropInteraction(_ interaction: UIDropInteraction, previewForDropping item: UIDragItem,
                         withDefault defaultPreview: UITargetedDragPreview) -> UITargetedDragPreview? {
        guard let target else { return nil }
        let pane = target == .left ? panes.left : panes.right
        return defaultPreview.retargetedPreview(with: UIDragPreviewTarget(
            container: self, center: CGPoint(x: pane.midX, y: pane.midY), transform: CGAffineTransform(scaleX: 0.6, y: 0.6)))
    }

    /// The pane's page is under the grown side by now: the side fades off it.
    func dropInteraction(_ interaction: UIDropInteraction, concludeDrop session: UIDropSession) {
        appear(false)
    }

    /// Let go in the middle, or anywhere a drop was refused, no conclusion
    /// comes: the zones go here instead.
    func dropInteraction(_ interaction: UIDropInteraction, sessionDidEnd session: UIDropSession) {
        if over { appear(false) }
        ended?()
    }

    /// One side: a pane of Liquid Glass, with a symbol and what a drop there
    /// does in the ink of the page's text. It comes and goes by its glass,
    /// which materializes, rather than by its opacity, which a visual effect
    /// can't take part in.
    private final class Zone: UIView {
        let name = UILabel()
        private let glass: UIVisualEffectView
        private let symbol = UIImageView()
        private let stack: UIStackView
        private(set) var revealed = false
        private var active = false
        private var tint = UIColor.tintColor

        init(_ side: Half) {
            if #available(iOS 26.0, *) {
                glass = UIVisualEffectView(effect: nil)
                glass.cornerConfiguration = .corners(radius: .fixed(Side.card))
            } else {
                glass = UIVisualEffectView(effect: nil)
                glass.layer.cornerRadius = Side.card
                glass.layer.cornerCurve = .continuous
                glass.clipsToBounds = true
            }
            symbol.image = UIImage(systemName: side == .left ? "rectangle.lefthalf.inset.filled" : "rectangle.righthalf.inset.filled",
                                   withConfiguration: UIImage.SymbolConfiguration(pointSize: 30, weight: .medium))
            name.text = side == .left ? "Open on the Left" : "Open on the Right"
            name.font = .systemFont(ofSize: 15, weight: .semibold)
            name.textAlignment = .center
            name.numberOfLines = 2
            stack = UIStackView(arrangedSubviews: [symbol, name])
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            layer.cornerRadius = Side.card
            layer.cornerCurve = .continuous
            glass.frame = bounds
            glass.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            addSubview(glass)
            stack.axis = .vertical
            stack.alignment = .center
            stack.spacing = 10
            stack.alpha = 0
            stack.translatesAutoresizingMaskIntoConstraints = false
            glass.contentView.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.centerXAnchor.constraint(equalTo: glass.contentView.centerXAnchor),
                stack.centerYAnchor.constraint(equalTo: glass.contentView.centerYAnchor),
                stack.widthAnchor.constraint(lessThanOrEqualTo: glass.contentView.widthAnchor, constant: -24),
            ])
        }

        required init?(coder: NSCoder) {
            nil
        }

        /// The glass comes, or goes, and what is on it with it.
        func reveal(_ shown: Bool) {
            guard shown != revealed else { return }
            revealed = shown
            apply()
        }

        /// At rest, clear glass with dark ink; the side the finger is over,
        /// the glass tinted and ringed in the space's colour, as the pane
        /// with the keys is ringed.
        func show(active: Bool, tint: UIColor) {
            guard active != self.active || tint != self.tint else { return }
            self.active = active
            self.tint = tint
            apply()
        }

        private func apply() {
            if #available(iOS 26.0, *) {
                let effect = UIGlassEffect()
                effect.tintColor = active ? tint.withAlphaComponent(0.25) : nil
                glass.effect = revealed ? effect : nil
            } else {
                glass.effect = revealed ? UIBlurEffect(style: .systemMaterial) : nil
            }
            stack.alpha = revealed ? 1 : 0
            layer.borderWidth = revealed && active ? 2 : 0
            layer.borderColor = tint.resolvedColor(with: traitCollection).cgColor
            symbol.tintColor = active ? tint : .label
            name.textColor = .label
        }
    }
}

/// Says where a touch or a click lands on the stage the moment it lands, and
/// takes nothing from the page under it: it fails at once, so the page gets
/// the touch as if it weren't there.
final class TouchDown: UIGestureRecognizer {
    var landed: ((CGPoint) -> Void)?

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if let touch = touches.first, let view { landed?(touch.location(in: view)) }
        state = .failed
    }
}

/// Says which keys were held as a touch or a click began anywhere in the
/// window, and where in the window, and takes nothing, as TouchDown: it
/// fails at once.
final class KeyedPress: UIGestureRecognizer {
    var pressed: ((UIKeyModifierFlags, CGPoint) -> Void)?

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if let touch = touches.first { pressed?(event.modifierFlags, touch.location(in: nil)) }
        state = .failed
    }
}
