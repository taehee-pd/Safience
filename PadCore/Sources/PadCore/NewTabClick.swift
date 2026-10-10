import Foundation

/// A click that opens where it goes in a new tab rather than in place, as
/// Safari and every desktop browser have it: ⌘-click puts the tab behind the
/// one you're on, ⌘⇧-click in front of it, and a mouse's middle button
/// behind it. A link, a form that only asks for a page (GET), or a button
/// whose script goes somewhere; never anything that sends something (POST:
/// a new tab would ask with GET and lose what was sent), going back or
/// forward, a reload, or anything but a web address. A click that goes nowhere (Figma's
/// ⌘-click, which picks a layer) is the page's alone.
public enum NewTabClick {
    /// What started the navigation, as WebKit names it.
    public enum Kind: Sendable {
        case link
        case form
        /// A page's own script: location.href, window.open.
        case script
        /// Back, forward, reload, a form sent again.
        case history
    }

    public enum Choice: Equatable, Sendable {
        case here
        case behind
        case inFront
    }

    public static func choice(kind: Kind, command: Bool, shift: Bool, middleButton: Bool,
                              method: String?, scheme: String?, mainFrame: Bool) -> Choice {
        guard command || middleButton else { return .here }
        guard ["http", "https"].contains(scheme?.lowercased() ?? "") else { return .here }
        guard (method ?? "GET").uppercased() == "GET" else { return .here }
        switch kind {
        case .history:
            return .here
        case .form, .link:
            break
        case .script:
            // A frame's own script moving it (an ad's, say) is not your click.
            guard mainFrame else { return .here }
        }
        return shift ? .inFront : .behind
    }
}
