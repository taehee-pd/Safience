import Foundation

/// The colour along the top of a page, which the bars above it take on, as
/// Safari's do: what its top edge shows, or its theme-color while nothing
/// is drawn yet.
public struct SiteColor: Equatable, Sendable {
    /// sRGB, each from 0 to 1.
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// The mean of a strip of pixels, RGBA one byte each, skipping the ones
    /// that are see-through (nothing drawn there yet). Nil when none is solid.
    public static func average(rgba bytes: [UInt8]) -> SiteColor? {
        guard bytes.count >= 4 else { return nil }
        var sum = (r: 0.0, g: 0.0, b: 0.0)
        var count = 0.0
        var index = 0
        while index + 3 < bytes.count {
            if bytes[index + 3] >= 128 {
                sum.r += Double(bytes[index])
                sum.g += Double(bytes[index + 1])
                sum.b += Double(bytes[index + 2])
                count += 1
            }
            index += 4
        }
        guard count > 0 else { return nil }
        return SiteColor(red: sum.r / count / 255, green: sum.g / count / 255, blue: sum.b / count / 255)
    }

    /// Whether light text reads better on it than dark text: the one of the
    /// two with more contrast, by WCAG's relative luminance.
    public var isDark: Bool {
        func linear(_ c: Double) -> Double {
            c <= 0.04045 ? c / 12.92 : Foundation.pow((c + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        return (1.05 / (luminance + 0.05)) > ((luminance + 0.05) / 0.05)
    }
}
