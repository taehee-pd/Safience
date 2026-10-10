import UIKit
import UIKit.UIGestureRecognizerSubclass

/// The line between a split's two panes (Browser.layoutPanes): its handle
/// drags the room from one page to the other; a double tap puts it back in
/// the middle.
final class SplitDivider: UIView, UIPointerInteractionDelegate {
    /// The band the panes leave between them, in a grey no page is, so the two
    /// pages read as two even when both are white.
    static let width: CGFloat = 8
    /// The panes' corners along the band: rounded, so each page reads as a card on it.
    static let corner: CGFloat = 10

    /// Where the drag is, across the stage.
    var moved: ((CGFloat) -> Void)?
    var ended: (() -> Void)?
    var centered: (() -> Void)?

    private let handle = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Palette.UI.splitBand
        handle.backgroundColor = Palette.UI.splitHandle
        handle.layer.cornerRadius = 2
        handle.layer.cornerCurve = .continuous
        handle.isUserInteractionEnabled = false
        addSubview(handle)
        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(dragged(_:))))
        let twice = UITapGestureRecognizer(target: self, action: #selector(tappedTwice))
        twice.numberOfTapsRequired = 2
        addGestureRecognizer(twice)
        addInteraction(UIPointerInteraction(delegate: self))
        isAccessibilityElement = true
        accessibilityLabel = "Split divider"
        accessibilityHint = "Double-tap to put it in the middle"
        isHidden = true
    }

    required init?(coder: NSCoder) {
        nil
    }

    /// While it is pressed or dragged, the handle stands out more: taller and
    /// darker. The press shows the moment the finger or the click lands, before
    /// the drag has moved far enough to begin.
    private var pressed = false { didSet { show() } }
    private var dragging = false { didSet { show() } }
    private var active = false

    /// A spring without bounce from wherever the handle is, so a press let go
    /// halfway through growing shrinks back from there.
    private func show() {
        let active = pressed || dragging
        guard active != self.active else { return }
        self.active = active
        UIView.animate(springDuration: 0.3, bounce: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.handle.backgroundColor = active ? Palette.UI.splitHandleActive : Palette.UI.splitHandle
            self.setNeedsLayout()
            self.layoutIfNeeded()
        }
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

    override func layoutSubviews() {
        super.layoutSubviews()
        let height: CGFloat = active ? 80 : 48
        handle.frame = CGRect(x: (bounds.width - 4) / 2, y: (bounds.height - height) / 2, width: 4, height: height)
    }

    /// Eight points is narrow for a finger: a few more on each side take the
    /// drag too, at the very edges of the pages.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -6, dy: 0).contains(point)
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

    @objc private func tappedTwice() {
        centered?()
    }

    override func accessibilityActivate() -> Bool {
        centered?()
        return true
    }

    func pointerInteraction(_ interaction: UIPointerInteraction, styleFor region: UIPointerRegion) -> UIPointerStyle? {
        UIPointerStyle(effect: .lift(UITargetedPreview(view: handle)))
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
