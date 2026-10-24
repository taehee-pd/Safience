import UIKit

/// A solid system surface keeps phone-bar controls readable over every page.
final class BarBackdrop: UIView {
    var tint: UIColor? { didSet { refresh() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitAccessibilityContrast.self]) { (self: BarBackdrop, _) in
            self.refresh()
        }
        refresh()
    }

    required init?(coder: NSCoder) { nil }

    private func refresh() {
        backgroundColor = Palette.UI.ground.resolvedColor(with: traitCollection)
    }
}
