import Foundation

/// What every page is told this browser is: Safari on a Mac.
///
/// WebKit on iPad, asked for desktop pages, already starts the user agent the
/// way Mac Safari does ("Macintosh; Intel Mac OS X 10_15_7", then
/// "AppleWebKit/605.1.15 (KHTML, like Gecko)"). The end of the string, where
/// Safari names its version, is left to the app as `applicationNameForUserAgent`.
/// Without it, sites read the app as an embedded web view: Google refuses to
/// sign in, and web apps serve their "unsupported browser" page.
public enum Identity {
    /// The WebKit build number Safari has reported since 2017, frozen on every
    /// platform; it no longer moves with releases.
    public static let engine = "605.1.15"

    /// "Version/18.6 Safari/605.1.15" on iPadOS 18.6. The version is the
    /// Safari this iPad has, because its WebKit is the one every tab runs on.
    /// iPadOS and Safari have shared their numbers since 17, iPadOS 26 is
    /// Safari 26. A patch number is said only when there is one, as Safari does.
    public static func applicationName(major: Int, minor: Int, patch: Int = 0) -> String {
        var version = "\(major).\(minor)"
        if patch > 0 { version += ".\(patch)" }
        return "Version/\(version) Safari/\(engine)"
    }

    public static func applicationName(for system: OperatingSystemVersion) -> String {
        applicationName(major: system.majorVersion, minor: system.minorVersion, patch: system.patchVersion)
    }

    /// The whole string Mac Safari sends. WebKit builds it from the
    /// application name above; this copy exists so Diagnostics can compare it
    /// with what a page reads in `navigator.userAgent`.
    public static func macUserAgent(applicationName: String) -> String {
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/\(engine) (KHTML, like Gecko) \(applicationName)"
    }
}
