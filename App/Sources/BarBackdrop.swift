import UIKit

/// What lies behind the phone bar: the page through it, blurred more the
/// lower it is, with a wash of the ground over it so the bar's controls read
/// on any page.
///
/// UIKit has no blur that varies, so three blurs are stacked, each fading
/// in a little lower than the one above: the blur deepens towards the
/// bottom. (A scroll view's soft edge, iOS 26's, would draw this for the
/// page, but it takes no shape from the SwiftUI bar over it, and there is no
/// scroll view under the start page or the desktop view.) Under Reduce
/// Transparency it is the plain ground.
final class BarBackdrop: UIView {
    // The thinnest material: each carries its own tint, and three stacked
    // ones of a thicker kind turn the bottom to frosted white.
    private let blurs: [UIVisualEffectView] = (0..<3).map { _ in UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial)) }
    private let masks: [GradientView] = (0..<3).map { _ in GradientView() }
    private let wash = GradientView()

    /// Where each blur starts and where it is whole, as fractions of the height.
    private static let bands: [(CGFloat, CGFloat)] = [(0, 0.35), (0.25, 0.6), (0.5, 0.85)]

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        for (blur, mask) in zip(blurs, masks) {
            blur.mask = mask
            addSubview(blur)
        }
        addSubview(wash)
        NotificationCenter.default.addObserver(self, selector: #selector(refresh),
                                               name: UIAccessibility.reduceTransparencyStatusDidChangeNotification, object: nil)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: BarBackdrop, _) in self.refresh() }
        refresh()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        for (blur, mask) in zip(blurs, masks) {
            blur.frame = bounds
            mask.frame = blur.bounds
        }
        wash.frame = bounds
    }

    @objc private func refresh() {
        let solid = UIAccessibility.isReduceTransparencyEnabled
        let ground = Palette.UI.ground.resolvedColor(with: traitCollection)
        for (index, (mask, band)) in zip(masks, Self.bands).enumerated() {
            mask.colors = [.clear, .black, .black]
            mask.locations = [band.0, band.1, 1]
            blurs[index].isHidden = solid
        }
        // Clear where the page meets the bar, the ground's colour thickening below.
        wash.colors = solid ? [ground, ground] : [ground.withAlphaComponent(0), ground.withAlphaComponent(0.25), ground.withAlphaComponent(0.45)]
        wash.locations = solid ? [0, 1] : [0, 0.45, 1]
    }
}

/// A vertical gradient, as a view: a blur's mask, or a wash of colour.
private final class GradientView: UIView {
    override class var layerClass: AnyClass { CAGradientLayer.self }

    private var gradient: CAGradientLayer? { layer as? CAGradientLayer }

    var colors: [UIColor] = [] {
        didSet { gradient?.colors = colors.map(\.cgColor) }
    }

    var locations: [CGFloat] = [] {
        didSet { gradient?.locations = locations.map { NSNumber(value: Double($0)) } }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        gradient?.startPoint = CGPoint(x: 0.5, y: 0)
        gradient?.endPoint = CGPoint(x: 0.5, y: 1)
    }

    required init?(coder: NSCoder) {
        nil
    }
}
