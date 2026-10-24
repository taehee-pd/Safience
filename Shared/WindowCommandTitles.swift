import PadCore

extension WindowModel {
    /// Menus and command results name the action that the current state permits.
    func title(for command: Command) -> String {
        let session = Session.shared
        let current = tabID.flatMap { session.workspace.tab($0) }
        switch command {
        case .closeTab: return current?.isPinned == true ? "Hide Pinned Tab" : "Close Tab"
        case .pinTab: return BrowserText.localized(current?.isPinned == true ? "Unpin Tab" : "Pin Tab")
        case .splitTab: return BrowserText.localized(tabID.flatMap { session.workspace.split(containing: $0) } == nil ? "Split with New Tab" : "Separate Tabs")
        #if os(iOS)
        case .tabBar:
            if session.preferences.tabsPlacement == .sidebar {
                return BrowserText.localized(session.preferences.tabBar ? "Hide Sidebar" : "Show Sidebar")
            }
            return BrowserText.localized(session.preferences.tabBar ? "Hide Tabs" : "Show Tabs")
        case .diagnostics: return BrowserText.localized(session.preferences.diagnostics ? "Hide Diagnostics" : "Show Diagnostics")
        case .bookmark: return BrowserText.localized(bookmarked ? "Remove Bookmark" : "Bookmark This Page")
        case .siteMode: return BrowserText.localized(mobileSite ? "Request Desktop Site" : "Request Mobile Site")
        case .contentBlocking: return BrowserText.localized(blocking == false ? "Block Ads on This Site" : "Allow Ads on This Site")
        case .linkMenu: return BrowserText.localized(ownMenus == true ? "Use Safience Link Menus" : "Use This Site's Own Menus")
        #else
        case .tabBar: return BrowserText.localized(sidebarShown ? "Hide Sidebar" : "Keep Sidebar Open")
        case .bookmark: return BrowserText.localized(isBookmarked ? "Remove Bookmark" : "Bookmark This Page")
        case .contentBlocking: return BrowserText.localized(blocksContentHere ? "Allow Ads on This Site" : "Block Ads on This Site")
        #endif
        default: return command.title
        }
    }
}
