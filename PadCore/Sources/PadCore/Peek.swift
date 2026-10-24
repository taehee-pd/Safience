import CoreGraphics
import Foundation

/// Peek, as in Arc: a page over the tab it came from, in a pane of glass,
/// for a look without leaving. A pop-up a page opens at a size of its own
/// (a sign-in, a share dialog) is one, at that size; so is a link that
/// leaves a pinned tab's site, at nearly the page's size, so the pinned tab
/// stays on its own site. A Peek goes with a click outside it, its ×, or
/// ⌘W, and Open in New Tab keeps its page as it is, in a tab of its own.
/// Only for the Mac (Mac/Sources/Peek.swift).
public enum Peek {
    /// Whether a navigation in a pinned tab goes to a Peek: a click on a
    /// link (a GET, never a form or a page's own script) to a web address on
    /// another site than the one the tab is on. A sign-in goes where it was
    /// asked for, and comes back to the tab that started it, and a hands-off
    /// host is never in a pane of the app's.
    public static func opensFromPinned(from: URL?, to: URL?, kind: NewTabClick.Kind, method: String?,
                                       mainFrame: Bool) -> Bool {
        guard mainFrame, kind == .link, (method ?? "GET").uppercased() == "GET" else { return false }
        guard let to, ["http", "https"].contains(to.scheme?.lowercased() ?? ""),
              let toHost = Hosts.host(of: to), let fromHost = Hosts.host(of: from)
        else { return false }
        guard !SignIn.isSignInPage(to), !SignIn.isSignInPage(from), !HandsOff.covers(to) else { return false }
        return Destination.registrable(toHost) != Destination.registrable(fromHost)
    }

    /// The room left round a Peek of a link, inside the page's card, as Arc
    /// leaves the tab's edges in sight.
    public static let margin: CGFloat = 36
    /// A Peek of a link is no wider than this, as a page of reading is.
    public static let widest: CGFloat = 1200
    /// No smaller than this where the room has it, so its header's buttons and a sign-in's form fit.
    public static let smallest = CGSize(width: 320, height: 240)

    /// The page's size in a Peek within `room` (the card's, less the pane's
    /// own edges): a pop-up's at the size it asked for; a link's, or a
    /// pop-up's that asked for one side only, nearly the room, `margin` in
    /// from each side and no wider than `widest`. Never more than the room,
    /// however small the window: the pane's buttons stay on the card.
    public static func size(width: Double?, height: Double?, within room: CGSize) -> CGSize {
        var wanted = CGSize(width: max(smallest.width, min(widest, room.width - 2 * margin)),
                            height: max(smallest.height, room.height - 2 * margin))
        if let width, let height, width > 0, height > 0 {
            wanted = CGSize(width: max(width, smallest.width), height: max(height, smallest.height))
        }
        return CGSize(width: max(1, min(wanted.width, room.width)).rounded(),
                      height: max(1, min(wanted.height, room.height)).rounded())
    }
}
