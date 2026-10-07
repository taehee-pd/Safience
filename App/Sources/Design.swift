import PadCore
import SwiftUI
import UIKit

// Every colour is a pair, one for light and one for dark, resolved against
// the window's own appearance. The page is the ground, so everything the app
// draws stays grey and quiet around it.
enum Palette {
    static let ground = Color(uiColor: UI.ground)
    static let ink = Color(uiColor: UI.ink)
    static let muted = Color(uiColor: UI.muted)
    static let faint = Color(uiColor: UI.faint)
    static let hairline = Color(uiColor: UI.hairline)
    static let wash = Color(uiColor: UI.wash)
    static let hover = Color(uiColor: UI.hover)
    /// See-through dark, for what lies on the bars: they take the page's
    /// colour, and a grey of its own would sit on it as a patch, where a
    /// dark that lets the colour through reads as a deeper shade of it. A
    /// split's shared ground, and a tab under the pointer.
    static let shade = Color(uiColor: UI.shade)
    static let hoverShade = Color(uiColor: UI.hoverShade)
    /// The only two that aren't grey: a connection nobody can read on the
    /// way, and one anybody can.
    static let safe = Color(uiColor: UI.safe)
    static let unsafe = Color(uiColor: UI.unsafe)

    enum UI {
        static let ground = pair(1.0, 0.11)
        static let ink = pair(0.09, 0.93)
        static let muted = pair(0.55, 0.58)
        static let faint = pair(0.83, 0.32)
        static let hairline = pair(0.91, 0.20)
        static let wash = pair(0.937, 0.175)
        static let hover = pair(0.965, 0.15)
        static let shade = dark(0.06, 0.24)
        static let hoverShade = dark(0.04, 0.14)
        static let safe = tint(light: (0.08, 0.50, 0.24), dark: (0.29, 0.87, 0.50))
        static let unsafe = tint(light: (0.71, 0.33, 0.04), dark: (0.98, 0.75, 0.14))

        private static func pair(_ light: CGFloat, _ dark: CGFloat) -> UIColor {
            UIColor { traits in
                UIColor(white: traits.userInterfaceStyle == .dark ? dark : light, alpha: 1)
            }
        }

        private static func dark(_ light: CGFloat, _ dark: CGFloat) -> UIColor {
            UIColor { traits in
                UIColor(white: 0, alpha: traits.userInterfaceStyle == .dark ? dark : light)
            }
        }

        private static func tint(light: (CGFloat, CGFloat, CGFloat), dark: (CGFloat, CGFloat, CGFloat)) -> UIColor {
            UIColor { traits in
                let c = traits.userInterfaceStyle == .dark ? dark : light
                return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
            }
        }
    }
}

enum Metrics {
    /// The row of tabs, and the address bar under it when it shows. Tall
    /// enough for 40-point hit areas with room above and below.
    static let bar: CGFloat = 44
    static let corner: CGFloat = 8
    /// What a control on a bar draws, and the area that answers a touch or
    /// a click, which is never smaller than 40 points a side.
    static let control: CGFloat = 32
    static let target: CGFloat = 40
}

/// How big the address and what is in it are drawn: for a pointer, beside
/// the tabs, or for a thumb, on the phone bar, where the address has a row
/// of its own and a touch needs the 44 points Apple asks for.
enum BarScale {
    case pointer
    case thumb

    /// The address's height.
    var control: CGFloat { self == .thumb ? 44 : Metrics.control }
    /// The area that answers: the drawn height, never under 40.
    var target: CGFloat { max(control, Metrics.target) }
    var text: CGFloat { self == .thumb ? 16 : 13 }
    var icon: CGFloat { self == .thumb ? 18 : 16 }
    /// The star's, reload's and clear's width.
    var button: CGFloat { self == .thumb ? 40 : 30 }
    /// From the capsule's end to the icon's slot: a thumb-sized capsule's
    /// end curves further in.
    var lead: CGFloat { self == .thumb ? 8 : TabFace.lead }
}

private struct BarScaleKey: EnvironmentKey {
    static let defaultValue = BarScale.pointer
}

extension EnvironmentValues {
    var barScale: BarScale {
        get { self[BarScaleKey.self] }
        set { self[BarScaleKey.self] = newValue }
    }
}

// MARK: A space's colour

extension SpaceColor {
    /// The system's own shades, which turn lighter in the dark as Apple's
    /// colours do.
    var uiColor: UIColor {
        switch self {
        case .blue: return .systemBlue
        case .purple: return .systemPurple
        case .pink: return .systemPink
        case .red: return .systemRed
        case .orange: return .systemOrange
        case .yellow: return .systemYellow
        case .green: return .systemGreen
        case .teal: return .systemTeal
        case .indigo: return .systemIndigo
        case .gray: return .systemGray
        }
    }

    var color: Color {
        Color(uiColor: uiColor)
    }

    /// Words on the colour: dark on the light ones, white on the rest.
    var ink: Color {
        self == .yellow ? Color.black.opacity(0.85) : .white
    }

    var name: String {
        rawValue.capitalized
    }
}

// MARK: The site's colour (PadCore's SiteColor) in UIKit's terms.

extension SiteColor {
    /// A page's theme-color. Nil when it is mostly see-through, which says
    /// nothing about the page.
    init?(_ color: UIColor) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard color.getRed(&r, green: &g, blue: &b, alpha: &a), a >= 0.5 else { return nil }
        // Wide-gamut colours come back outside 0...1.
        self.init(red: Double(min(max(r, 0), 1)), green: Double(min(max(g, 0), 1)), blue: Double(min(max(b, 0), 1)))
    }

    /// The mean colour of a picture of the page's top edge.
    init?(picture: UIImage) {
        guard let image = picture.cgImage, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let width = 16
        var bytes = [UInt8](repeating: 0, count: width * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: 1, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: 1))
            return true
        }
        guard drawn, let color = SiteColor.average(rgba: bytes) else { return nil }
        self = color
    }

    var uiColor: UIColor {
        UIColor(red: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: 1)
    }
}

// MARK: Liquid Glass, where the system has it

/// Which of the system's two glasses: regular for what you act on now, clear
/// for what sits beside it (the other tabs).
enum GlassKind {
    case regular
    case clear
}

extension View {
    /// Liquid Glass in `shape` on iPadOS 26 and later, tinted with `tint`
    /// when there is one; the flat `fallback` fill (or the tint) before, as
    /// the bars always looked.
    ///
    /// `reacting`: the glass itself answers a press, for a control that is
    /// all glass (a round button). Glass holding controls of its own (the
    /// address with its star and reload) must not: it takes the touch, and
    /// the controls inside never hear it.
    @ViewBuilder
    func liquidGlass<S: Shape>(_ kind: GlassKind = .regular, tint: Color? = nil, reacting: Bool = true, in shape: S,
                               otherwise fallback: Color) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect((kind == .regular ? Glass.regular : Glass.clear).tint(tint).interactive(reacting), in: shape)
        } else {
            background(tint ?? fallback, in: shape)
        }
    }

    /// An icon that comes and goes as Apple's do: from a quarter of its size,
    /// out of a blur, fading in; and back the same way.
    func iconSwap() -> some View {
        transition(.modifier(active: IconSwap(progress: 0), identity: IconSwap(progress: 1)))
    }
}

private struct IconSwap: ViewModifier {
    let progress: Double

    func body(content: Content) -> some View {
        content
            .scaleEffect(0.25 + 0.75 * progress)
            .opacity(progress)
            .blur(radius: 4 * (1 - progress))
    }
}

/// A tab's capsule; a split's half, its end against the other half nearly
/// square, so the two read as one piece. The squared end eases into a round
/// one, as the address field grows out of a half into the whole row.
struct TabShape: Shape {
    /// The radius at the end against the other half; half the height or
    /// more is a capsule.
    var joined: CGFloat
    /// That end is the leading one.
    var leading: Bool

    /// A capsule.
    static let whole = TabShape(joined: Metrics.control / 2, leading: false)
    /// The radius where two halves of a split meet.
    static let seam: CGFloat = 6

    /// The half of a split meeting the other at `edge`; nil, a capsule.
    static func half(meeting edge: HorizontalEdge?) -> TabShape {
        edge.map { TabShape(joined: seam, leading: $0 == .leading) } ?? whole
    }

    var animatableData: CGFloat {
        get { joined }
        set { joined = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let round = rect.height / 2
        let seam = min(max(joined, 0), round)
        return UnevenRoundedRectangle(topLeadingRadius: leading ? seam : round,
                                      bottomLeadingRadius: leading ? seam : round,
                                      bottomTrailingRadius: leading ? round : seam,
                                      topTrailingRadius: leading ? round : seam,
                                      style: .continuous).path(in: rect)
    }
}

/// The motion of everything on the bars: a spring with no bounce, which
/// starts from wherever the last one left off when interrupted.
extension Animation {
    static let bar = Animation.spring(duration: 0.3, bounce: 0)
}

/// A press that shows: the control gives a little, to 0.96, while held.
struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.bar, value: configuration.isPressed)
    }
}

// MARK: A site's icon

/// A site's icon as SiteIcons has it, or its first letter on a colour of
/// its own until it does. A thin outline, black in light and white in dark,
/// gives every icon the same edge, whatever colour it is.
struct SiteIconView: View {
    let url: URL?
    var size: CGFloat = 16
    @ObservedObject private var icons = SiteIcons.shared
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
        Group {
            if let image = icons.image(for: url) {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                ZStack {
                    letterColor
                    Text(letter)
                        .font(.system(size: size * 0.56, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.strokeBorder(scheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1), lineWidth: 1))
        .accessibilityHidden(true)
    }

    private var host: String {
        guard let host = url?.host() else { return "" }
        return Destination.registrable(host.hasPrefix("www.") ? String(host.dropFirst(4)) : host)
    }

    private var letter: String {
        host.first.map { String($0).uppercased() } ?? "•"
    }

    /// The same colour for a site every time: from its name, not at random.
    private var letterColor: Color {
        let palette: [SpaceColor] = [.blue, .purple, .pink, .red, .orange, .green, .teal, .indigo]
        let sum = host.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return palette[sum % palette.count].color
    }
}

/// Glass shapes near each other, drawn as one material that flows between
/// them, as the system's own bars do; just the content before iPadOS 26.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 6
    @ViewBuilder var content: Content

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}
