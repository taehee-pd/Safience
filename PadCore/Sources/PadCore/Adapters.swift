import Foundation

/// How the page hears about two fingers moving on the trackpad.
///
/// WebKit's own scrolling is off (see `Scrolling`), and with it off WebKit
/// may stop sending the page wheel events at all. The bridge sends them
/// itself, built from the trackpad's pan, the way a Mac's WebKit would.
public enum WheelMode: String, Codable, CaseIterable, Sendable {
    /// Never: the page gets only what WebKit sends.
    case off
    /// Sent unless the page is already getting WebKit's own wheel events,
    /// checked event by event in the page (bridge.js), so the two never add up.
    case auto
    /// Always sent, even alongside WebKit's own.
    case always
}

/// Keys the system can take for itself on iPad, moving focus between
/// controls or the text cursor, before the page sees them.
public enum RelayKey: String, Codable, CaseIterable, Sendable {
    case tab
    case arrows
}

/// Which of the bridges between the iPad's input and the page are on.
public struct Bridges: Equatable, Codable, Sendable {
    /// A trackpad pinch becomes a wheel event with ctrlKey, what Chrome and
    /// Firefox send for a pinch on a Mac and what Figma zooms on.
    public var pinch: Bool
    /// ⌘ held while scrolling with two fingers zooms the same way.
    public var commandZoom: Bool
    public var wheel: WheelMode
    /// Taken from the system with priority and handed to the page.
    public var keys: Set<RelayKey>
    /// The wheel delta for a pinch, per unit of the natural log of the scale
    /// step. 100 is Chrome's: a pinch to twice the size sends -69.3 in all.
    public var pinchFactor: Double

    public init(pinch: Bool = true, commandZoom: Bool = true, wheel: WheelMode = .auto,
                keys: Set<RelayKey> = [], pinchFactor: Double = 100) {
        self.pinch = pinch
        self.commandZoom = commandZoom
        self.wheel = wheel
        self.keys = keys
        self.pinchFactor = pinchFactor
    }

    public static let standard = Bridges()
}

/// What one site needs that others don't: a stylesheet, a script, a user
/// agent, its own choice of bridges, and which of its pages are heavy.
public struct SiteAdapter: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    /// The site's domains; each covers its subdomains too.
    public let domains: [String]
    /// A whole user agent in place of Mac Safari's, or nil to keep Safari's.
    public let userAgent: String?
    /// Added to every page of the site after the app's own stylesheet.
    public let css: String
    /// Runs at document start in the app's own world, beside bridge.js:
    /// sees the page's DOM, not its variables.
    public let script: String
    /// Runs at document start in the page's own world, for what has to
    /// change the page's view of the browser. Empty when nothing has to.
    public let pageScript: String
    public let bridges: Bridges
    /// Path prefixes of the pages that cost the most memory, a design file
    /// rather than the file browser. A heavy tab is one of these.
    public let heavyPaths: [String]

    public init(id: String, name: String, domains: [String], userAgent: String? = nil,
                css: String = "", script: String = "", pageScript: String = "",
                bridges: Bridges = .standard, heavyPaths: [String] = []) {
        self.id = id
        self.name = name
        self.domains = domains.map { $0.lowercased() }
        self.userAgent = userAgent
        self.css = css
        self.script = script
        self.pageScript = pageScript
        self.bridges = bridges
        self.heavyPaths = heavyPaths
    }

    public func covers(_ url: URL?) -> Bool {
        guard let host = Hosts.host(of: url) else { return false }
        return domains.contains { Hosts.host(host, isWithin: $0) }
    }

    public func isHeavy(_ url: URL?) -> Bool {
        guard covers(url), let path = url?.path(), !heavyPaths.isEmpty else { return false }
        return heavyPaths.contains { path.hasPrefix($0) }
    }
}

public enum Adapters {
    /// Figma, FigJam, Slides, Make and Sites, all on figma.com.
    ///
    /// Its page script hides the touch screen from the page. A Mac user agent
    /// with five touch points is how sites tell an iPad asking for desktop
    /// pages from a Mac, and a site that tells them apart can switch to touch
    /// handling the bridges don't feed. With no touch points the page gets the
    /// Mac it was told it is. Fingers on the glass still work: WebKit sends
    /// their pointer and mouse events either way.
    public static let figma = SiteAdapter(
        id: "figma",
        name: "Figma",
        domains: ["figma.com"],
        pageScript: Snippets.noTouchPoints,
        bridges: Bridges(pinch: true, commandZoom: true, wheel: .auto, keys: [], pinchFactor: 100),
        heavyPaths: ["/design/", "/file/", "/board/", "/proto/", "/slides/", "/deck/", "/make/", "/site/", "/buzz/"]
    )

    /// Every site no adapter covers: every bridge on, nothing added.
    public static let standard = SiteAdapter(id: "standard", name: "Every other site", domains: [])

    /// Asked in this order, the first that covers a page wins. Figma first.
    public static let all: [SiteAdapter] = [figma]

    public static func adapter(for url: URL?) -> SiteAdapter {
        all.first { $0.covers(url) } ?? standard
    }
}

/// Scripts more than one adapter can use.
public enum Snippets {
    /// `navigator.maxTouchPoints` as a Mac has it, for the page's own world.
    public static let noTouchPoints = """
    (() => {
      try {
        Object.defineProperty(Navigator.prototype, 'maxTouchPoints', {
          configurable: true, enumerable: true, get() { return 0; }
        });
      } catch (_) {}
    })();
    """
}
