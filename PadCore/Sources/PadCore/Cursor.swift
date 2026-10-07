import Foundation

/// The cursor a page asks for under the pointer, as bridge.js reports it.
///
/// WebKit on iPad shows the system pointer for every cursor but the text
/// beam, so a page's own cursor images (Figma's arrow, its pen, its resize
/// arrows) never show. bridge.js reads the cursor under the pointer and
/// draws its image to a PNG; the app hides the system pointer and draws
/// that image where the pointer is (Pointer.swift).
public enum PageCursor: Equatable, Sendable {
    /// The system's pointer, as WebKit chooses it (the beam over text).
    case system
    /// `cursor: none`: no pointer at all, as on a Mac.
    case hidden
    /// One of CSS's own cursors by name (pointer, text, ew-resize…): the
    /// system's pointer on iPad, which WebKit chooses; drawn by the app in
    /// the iPhone's desktop view, which has a cursor of its own.
    case keyword(String)
    /// The page's own picture.
    case image(CursorImage)

    /// Browsers don't show a cursor bigger than this (Chrome's limit), and
    /// neither does the app: a cursor that big could hide the page.
    public static let largest = 128.0

    /// From bridge.js's message. Anything that can't be shown is the
    /// system's pointer, never a missing one.
    public init(message: [String: Any]) {
        if let keyword = message["keyword"] as? String {
            let name = keyword.trimmingCharacters(in: .whitespaces).lowercased()
            switch name {
            case "none": self = .hidden
            case "", "auto", "default": self = .system
            default: self = .keyword(name)
            }
            return
        }
        guard let id = Self.number(message["id"]).map({ Int($0) }) else {
            self = .system
            return
        }
        guard let picture = message["image"] as? String else {
            // Its picture came with an earlier message.
            self = .image(CursorImage(id: id, width: 0, height: 0, hotspotX: 0, hotspotY: 0, scale: 1, png: nil))
            return
        }
        let prefix = "data:image/png;base64,"
        guard let width = Self.number(message["width"]), let height = Self.number(message["height"]),
              width > 0, height > 0, width <= Self.largest, height <= Self.largest,
              picture.hasPrefix(prefix), let png = Data(base64Encoded: String(picture.dropFirst(prefix.count)))
        else {
            self = .system
            return
        }
        let scale = min(max(Self.number(message["scale"]) ?? 2, 1), 3)
        let x = min(max(Self.number(message["x"]) ?? 0, 0), width)
        let y = min(max(Self.number(message["y"]) ?? 0, 0), height)
        self = .image(CursorImage(id: id, width: width, height: height, hotspotX: x, hotspotY: y, scale: scale, png: png))
    }

    /// A number from JavaScript, which WebKit hands over as an NSNumber
    /// (and a test as an Int or a Double).
    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let value as Double: return value.isFinite ? value : nil
        case let value as Int: return Double(value)
        case let value as NSNumber: return value.doubleValue.isFinite ? value.doubleValue : nil
        default: return nil
        }
    }
}

/// One cursor picture of a page's, the first time it is sent; after that
/// the same id comes without the picture, and size and hotspot are zero.
public struct CursorImage: Equatable, Sendable {
    public var id: Int
    /// In points: the page's CSS pixels, its zoom being held at 1.
    public var width: Double
    public var height: Double
    /// The point of the picture that is the pointer's position.
    public var hotspotX: Double
    public var hotspotY: Double
    /// Pixels of `png` to a point.
    public var scale: Double
    public var png: Data?

    public init(id: Int, width: Double, height: Double, hotspotX: Double, hotspotY: Double, scale: Double, png: Data?) {
        self.id = id
        self.width = width
        self.height = height
        self.hotspotX = hotspotX
        self.hotspotY = hotspotY
        self.scale = scale
        self.png = png
    }
}
