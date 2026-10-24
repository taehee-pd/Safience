import AppKit
import PadCore
import SwiftUI

// The Mac's window is the space's colour, seen through the desktop behind
// it, as Arc's is its theme's; the page is a card on it. What the app draws
// stays quiet: the sidebar's words and icons in the label colours, and the
// controls in Liquid Glass, which takes its colour from what is under it.

extension SpaceColor {
    /// The system's own shades, which turn lighter in the dark as Apple's colours do.
    var nsColor: NSColor {
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
        Color(nsColor: nsColor)
    }

    /// Resolve the actual appearance, then choose the higher-contrast opaque ink.
    var ink: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            var result = NSColor.labelColor
            appearance.performAsCurrentDrawingAppearance {
                guard let colour = self.nsColor.usingColorSpace(.sRGB) else { return }
                let background = SiteColor(red: colour.redComponent, green: colour.greenComponent, blue: colour.blueComponent)
                result = background.isDark ? .white : .black
            }
            return result
        })
    }

    var name: String {
        BrowserText.localized(rawValue.capitalized)
    }
}

/// The greys the app draws with, by the iPad's names, so what the two share
/// (HandoffGuide) draws the same: each a pair, for light and for dark.
enum Palette {
    static let muted = pair(0.55, 0.58)
    /// What stands on glass is never a solid grey, which sits on the glass
    /// as a patch: a see-through dark lets the glass's own colour through
    /// and reads as a shade of it, as the iPad's bars' shade does.
    static let faint = dim(light: 0.12, dark: 0.32)
    static let wash = dim(light: 0.05, dark: 0.22)
    /// A hairline round a site's icon, so a white or a black one keeps its edge on glass.
    static let outline = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(white: 1, alpha: 0.1) : NSColor(white: 0, alpha: 0.1)
    })
    /// Under what the pointer is on, and under what is held down: black in
    /// the light and white in the dark, strong enough to be seen at a
    /// glance on the sidebar's colour and on glass alike.
    static let hover = shade(light: 0.09, dark: 0.13)
    static let press = shade(light: 0.16, dark: 0.22)

    private static func pair(_ light: CGFloat, _ dark: CGFloat) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            NSColor(white: appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light, alpha: 1)
        })
    }

    /// See-through black, darker in the dark: a well in the glass.
    private static func dim(light: CGFloat, dark: CGFloat) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            NSColor(white: 0, alpha: appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light)
        })
    }

    private static func shade(light: CGFloat, dark: CGFloat) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(white: 1, alpha: dark) : NSColor(white: 0, alpha: light)
        })
    }
}

extension Animation {
    /// A highlight coming and going under the pointer: quick, and slowing as it ends.
    static let hover = Animation.easeOut(duration: 0.12)
}

/// The motion of everything in the window: a spring with no bounce, which
/// starts from wherever the last one left off when interrupted.
extension Animation {
    static let bar = Animation.spring(duration: 0.3, bounce: 0)
}

enum Metrics {
    /// The one step the window is spaced by: the page's card from the
    /// window's edges and from the sidebar, the sidebar's rows from its edges,
    /// and its groups (the top row, the address, the tiles, the tabs, the
    /// spaces) from each other.
    static let gap: CGFloat = 8
    /// The window's own corners, as macOS 26 draws a window with no toolbar.
    static let window: CGFloat = 16
    /// The window's ground round the page's card, at its top, its side and
    /// its foot, and between it and the sidebar: thinner than the gaps
    /// inside the sidebar, so the page has the room.
    static let bezel: CGFloat = 5
    /// The page's card, `bezel` inside the window's corners: smaller by as
    /// much, so the two curves run side by side.
    static let card: CGFloat = window - bezel
    /// The glass buttons of the top row, and the cell the window's own
    /// buttons are centred in beside them (WindowButtons).
    static let control: CGFloat = 28
    /// The address, the share button, and the controls of the space bar.
    static let field: CGFloat = 32
    static let row: CGFloat = 34
    /// A row's corners: its 16-point icon's own (3.6) and the 9 points round it.
    static let rowCorner: CGFloat = 12
    /// A pinned tile: its icon 18 points, a little larger than a row's 16,
    /// 13 from the tile's top and foot, the tile's corners the icon's (4)
    /// and those 13.
    static let tile: CGFloat = 44
    static let tileIcon: CGFloat = 18
    static let tileCorner: CGFloat = 17
    /// A pane of rows (the command bar, the peeking sidebar): the rows'
    /// corners and the gap round them.
    static let pane: CGFloat = rowCorner + gap
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

/// A site's icon as SiteIcons has it, or its first letter on the space's
/// colour until it does.
struct SiteIconView: View {
    let url: URL?
    var size: CGFloat = 16
    @ObservedObject private var icons = SiteIcons.shared
    /// A drawn icon with a dark look of its own shows it on a dark screen.
    @Environment(\.colorScheme) private var scheme
    @Environment(\.spaceColor) private var space

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
        let lightGround = icons.needsLightGround(url, dark: scheme == .dark)
        Group {
            if let image = icons.image(for: url, dark: scheme == .dark) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    // A dark shape on clear, on a dark screen: on a light ground, as Safari shows it.
                    .padding(lightGround ? size * 0.14 : 0)
                    .background { if lightGround { Color.white.opacity(0.92) } }
            } else if url == nil {
                Image(systemName: "globe")
                    .font(.system(size: size * 0.8))
                    .foregroundStyle(.secondary)
            } else {
                ZStack {
                    space.color
                    Text(letter)
                        .font(.system(size: size * 0.6, weight: .semibold, design: .rounded))
                        .foregroundStyle(space.ink)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .accessibilityHidden(true)
    }

    private var letter: String {
        guard let host = url?.host() else { return "•" }
        let site = Destination.registrable(host.hasPrefix("www.") ? String(host.dropFirst(4)) : host)
        return site.first.map { String($0).uppercased() } ?? "•"
    }
}

// MARK: The window behind everything

/// What is behind the window, through Liquid Glass: the ground the space's
/// colour is laid over. Clearer than a sidebar's material, which was close
/// to opaque, and clear still in a window that isn't in front, where that
/// material turns flat. The window is clear for it (WindowReader).
struct Backdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSGlassEffectView {
        let view = NSGlassEffectView()
        view.style = .regular
        return view
    }

    func updateNSView(_ view: NSGlassEffectView, context: Context) {}
}

/// The space's colour over the window's glass: stronger at the top, where
/// the sidebar's space name is, fading toward the foot; paler in the dark,
/// where a strong colour would glare beside the page.
struct SpaceWash: View {
    let color: SpaceColor
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let strength = scheme == .dark ? 0.26 : 0.34
        ZStack {
            Backdrop()
            LinearGradient(colors: [color.color.opacity(strength), color.color.opacity(strength * 0.45)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .animation(.easeInOut(duration: 0.35), value: color)
        }
        .ignoresSafeArea()
    }
}
