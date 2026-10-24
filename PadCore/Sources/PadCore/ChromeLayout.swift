import Foundation

/// Which of a window's bars show, worked out from its width, Settings and
/// the page without UIKit, so the rules can be tested (Browser.refreshChrome
/// puts it on screen, and only when it has changed).
public struct ChromeLayout: Equatable, Sendable {
    /// The phone bar's form at the bottom of a phone-width window.
    public enum PhoneBar: Equatable, Sendable {
        /// The address over a row of tools.
        case twoRows
        /// Beside the iPhone Duo's strip: the space, then the address.
        case oneRow
        /// The address alone, riding the keyboard.
        case typing
    }

    /// The bars are at the bottom, as on an iPhone; nil for the phone bar
    /// in a wide window, which has its bars along the top or a sidebar.
    public let phoneBar: PhoneBar?
    /// The tabs down the window's side (Settings › Tabs).
    public let sidebar: Bool
    public let topBar: Bool
    /// The address bar, for a sidebar put away.
    public let addressBar: Bool
    public let bookmarksBar: Bool

    /// - Parameters:
    ///   - compact: the window is phone-width.
    ///   - strip: it has the iPhone Duo's strip beside it.
    ///   - placement: where Settings puts the tabs in a wide window.
    ///   - tabBar: Show or Hide Tab Bar: the tabs are shown.
    ///   - bookmarksBar: Settings shows the bookmarks bar.
    ///   - addressRequired: the address must show whatever Settings says
    ///     (a sign-in page, a page that failed, a new tab).
    ///   - typing: an address is being typed and the keyboard is on its way.
    public init(compact: Bool, strip: Bool, placement: Preferences.TabsPlacement?, tabBar: Bool,
                bookmarksBar: Bool, addressRequired: Bool, typing: Bool) {
        if compact {
            // On a phone the bar at the bottom is the only way around: always there.
            phoneBar = typing ? .typing : strip ? .oneRow : .twoRows
            sidebar = false
            topBar = false
            addressBar = false
            self.bookmarksBar = false
            return
        }
        phoneBar = nil
        // The tabs in a sidebar have the address too, and while they show
        // neither bar does. Put away, the address bar stays, with the way back.
        let side = placement == .sidebar
        sidebar = side && tabBar
        // Hiding tabs always retains navigation and a visible route back.
        topBar = !side && tabBar
        addressBar = !tabBar
        // The sidebar has its own Bookmarks section.
        self.bookmarksBar = !side && bookmarksBar
    }
}
