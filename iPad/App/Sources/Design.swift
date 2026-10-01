import SwiftUI
import UIKit

// The Mac app's colours (Design.swift there), on iPad: every colour a pair,
// one for light and one for dark, resolved against the window's own
// appearance. The page is the ground, so everything the app draws stays grey
// and quiet around it.
enum Palette {
    static let ground = Color(uiColor: UI.ground)
    static let ink = Color(uiColor: UI.ink)
    static let muted = Color(uiColor: UI.muted)
    static let faint = Color(uiColor: UI.faint)
    static let hairline = Color(uiColor: UI.hairline)
    static let wash = Color(uiColor: UI.wash)
    static let hover = Color(uiColor: UI.hover)
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
        static let safe = tint(light: (0.08, 0.50, 0.24), dark: (0.29, 0.87, 0.50))
        static let unsafe = tint(light: (0.71, 0.33, 0.04), dark: (0.98, 0.75, 0.14))

        private static func pair(_ light: CGFloat, _ dark: CGFloat) -> UIColor {
            UIColor { traits in
                UIColor(white: traits.userInterfaceStyle == .dark ? dark : light, alpha: 1)
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
    /// The row of tabs, and the address bar under it when it shows.
    static let bar: CGFloat = 40
    static let corner: CGFloat = 8
}
