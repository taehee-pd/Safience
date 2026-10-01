import Foundation

/// Host names as the rest of PadCore compares them.
enum Hosts {
    /// Lowercased and without the trailing dot a fully qualified name may
    /// carry ("figma.com." is figma.com), or nil when there is no host.
    static func normal(_ host: String?) -> String? {
        guard var name = host?.lowercased(), !name.isEmpty else { return nil }
        while name.hasSuffix(".") { name.removeLast() }
        return name.isEmpty ? nil : name
    }

    static func host(of url: URL?) -> String? {
        normal(url?.host())
    }

    /// `host` is `domain` itself or a name under it: www.figma.com is within
    /// figma.com, notfigma.com is not.
    static func host(_ host: String, isWithin domain: String) -> Bool {
        host == domain || host.hasSuffix("." + domain)
    }
}
