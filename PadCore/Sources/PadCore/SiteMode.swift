import Foundation

/// Which version of a site a page asks for.
public enum SiteMode: String, Codable, CaseIterable, Sendable {
    case desktop
    case mobile

    /// The narrowest window that gets desktop sites, and the shortest. An
    /// iPad, the iPhone Duo unfolded and an iPad window of half the screen
    /// or more get them; an iPhone either way up, the Duo folded and a narrow
    /// iPad window get mobile sites, as Safari gives them.
    public static let desktopWidth = 600.0
    public static let desktopHeight = 500.0

    /// The mode for a page at `host` in a window `width` by `height` points:
    /// what you asked for that site (Request Desktop or Mobile Site), else
    /// by the window's size.
    public static func choose(host: String?, width: Double, height: Double, overrides: [String: SiteMode]) -> SiteMode {
        if let key = siteKey(host), let chosen = overrides[key] { return chosen }
        return width >= desktopWidth && height >= desktopHeight ? .desktop : .mobile
    }

    /// The key a choice is kept under: the host without `www.`.
    public static func siteKey(_ host: String?) -> String? {
        guard let host = host?.lowercased(), !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

extension Identity {
    /// The whole string Safari on an iPhone or an iPad sends for a mobile
    /// site. WebKit's own, in a mobile layout, leaves out "Mobile/15E148",
    /// and without it sites send their desktop page.
    public static func mobileUserAgent(major: Int, minor: Int, patch: Int = 0, pad: Bool) -> String {
        var system = "\(major)_\(minor)"
        if patch > 0 { system += "_\(patch)" }
        var version = "\(major).\(minor)"
        if patch > 0 { version += ".\(patch)" }
        let device = pad ? "iPad; CPU OS \(system) like Mac OS X" : "iPhone; CPU iPhone OS \(system) like Mac OS X"
        return "Mozilla/5.0 (\(device)) AppleWebKit/\(engine) (KHTML, like Gecko) Version/\(version) Mobile/15E148 Safari/604.1"
    }

    public static func mobileUserAgent(for system: OperatingSystemVersion, pad: Bool) -> String {
        mobileUserAgent(major: system.majorVersion, minor: system.minorVersion, patch: system.patchVersion, pad: pad)
    }
}
