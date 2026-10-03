import UIKit
import UIKit.UIGestureRecognizerSubclass

/// The line between a split's two panes (Browser.layoutPanes): its handle
/// drags the room from one page to the other; a double tap puts it back in
/// the middle.
final class SplitDivider: UIView, UIPointerInteractionDelegate {
    /// The gap the panes leave between them.
    static let width: CGFloat = 8

    /// Where the drag is, across the stage.
    var moved: ((CGFloat) -> Void)?
    var ended: (() -> Void)?
    var centered: (() -> Void)?

    private let handle = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        handle.backgroundColor = Palette.UI.faint
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

    override func layoutSubviews() {
        super.layoutSubviews()
        handle.frame = CGRect(x: (bounds.width - 4) / 2, y: (bounds.height - 40) / 2, width: 4, height: 40)
    }

    /// Eight points is narrow for a finger: a few more on each side take the
    /// drag too, at the very edges of the pages.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -6, dy: 0).contains(point)
    }

    @objc private func dragged(_ pan: UIPanGestureRecognizer) {
        switch pan.state {
        case .changed:
            if let stage = superview { moved?(pan.location(in: stage).x) }
        case .ended, .cancelled, .failed:
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
