import Foundation

/// A part of Settings the address bar goes straight to: "change icon" typed
/// there offers App Icon, and taking the row opens Settings scrolled to it.
/// One for each section of the Settings screen (SettingsView), found by its
/// name and by the words for what is changed there.
public enum SettingsAnchor: String, CaseIterable, Sendable {
    case defaultBrowser
    case sync
    case appIcon
    case desktopView
    case addressBar
    case window
    case spaces
    case memory
    case trackpad
    case search
    case history
    case blocking
    case linkMenu
    case handoff
    case diagnostics
    case shortcuts

    /// The section, as its row names it.
    public var title: String {
        switch self {
        case .defaultBrowser: return BrowserText.localized("Default browser")
        case .sync: return BrowserText.localized("iCloud")
        case .appIcon: return BrowserText.localized("App icon")
        case .desktopView: return BrowserText.localized("Trackpad View")
        case .addressBar: return BrowserText.localized("The address bar shows")
        case .window: return BrowserText.localized("Window")
        case .spaces: return BrowserText.localized("Spaces and bookmarks")
        case .memory: return BrowserText.localized("Memory")
        case .trackpad: return BrowserText.localized("Trackpad and keyboard")
        case .search: return BrowserText.localized("Search")
        case .history: return BrowserText.localized("History")
        case .blocking: return BrowserText.localized("Ads and trackers")
        case .linkMenu: return BrowserText.localized("Link menu")
        case .handoff: return BrowserText.localized("Send to App")
        case .diagnostics: return BrowserText.localized("Developer diagnostics")
        case .shortcuts: return BrowserText.localized("Shortcuts")
        }
    }

    /// What is changed there, for the line under the name.
    public var detail: String {
        switch self {
        case .defaultBrowser: return BrowserText.localized("Open links from other apps here")
        case .sync: return BrowserText.localized("Spaces, bookmarks and pinned tabs on your devices")
        case .appIcon: return BrowserText.localized("The Home Screen icon")
        case .desktopView: return BrowserText.localized("How far the cursor goes")
        case .addressBar: return BrowserText.localized("The page's address or its title")
        case .window: return BrowserText.localized("Tabs along the top or in a sidebar")
        case .spaces: return BrowserText.localized("Edit spaces, import bookmarks")
        case .memory: return BrowserText.localized("Tabs kept open off screen")
        case .trackpad: return BrowserText.localized("Scrolling, Tab and arrow keys, cursors")
        case .search: return BrowserText.localized("The engine, suggestions, Apple Intelligence")
        case .history: return BrowserText.localized("How long it is kept, clearing it")
        case .blocking: return BrowserText.localized("The content blocker and its lists")
        case .linkMenu: return BrowserText.localized("Sites with their own menus")
        case .handoff: return BrowserText.localized("A page and a question, to another app")
        case .diagnostics: return BrowserText.localized("The panel over the page")
        case .shortcuts: return BrowserText.localized("Every command's keys")
        }
    }

    /// Words it is also found by: what one wants done, not what the section
    /// is called.
    public var keywords: [String] {
        switch self {
        case .defaultBrowser: return ["set as default", "make default", "browser app", "open links"]
        case .sync: return ["sync", "icloud", "cloudkit", "other devices", "mac", "turn on sync"]
        case .appIcon:
            return ["change icon", "change app icon", "home screen icon", "alternate icon", "icon style", "logo"]
        case .desktopView: return ["cursor speed", "pointer speed", "sensitivity", "tracking speed"]
        case .addressBar: return ["show address", "show title", "url", "page title"]
        case .window:
            return ["layout", "compact", "separate", "tab layout", "hide tab bar", "show tab bar", "window", "sidebar",
                    "vertical tabs",
                    "show address", "show title", "url"]
        case .spaces: return ["manage spaces", "edit spaces", "rename space", "delete space", "reorder spaces", "profiles"]
        case .memory: return ["light tabs", "tabs kept open", "freeze tabs", "frozen tabs", "background tabs", "ram"]
        case .trackpad:
            return ["two-finger scroll", "scroll", "wheel", "tab key", "arrow keys", "page cursor", "pointer", "bridge"]
        case .search:
            return ["change search engine", "default search", "suggestions", "search suggestions", "autocomplete",
                    "apple intelligence"] + Engine.allCases.map { $0.title.lowercased() }
        case .history:
            return ["clear history", "delete history", "browsing history", "keep history", "forget", "erase"]
        case .blocking: return ["ad blocker", "adblock", "block ads", "content blocker", "privacy", "easylist"]
        case .linkMenu: return ["context menu", "long press", "right click", "secondary click", "own menus"]
        case .handoff:
            return ["ai", "ask ai", "assistant", "claude", "chatgpt", "gemini", "markdown", "summarize", "question", "prompt"]
        case .diagnostics: return ["debug", "hud", "show diagnostics", "user agent"]
        case .shortcuts: return ["shortcuts", "cheat sheet", "cheatsheet", "keys", "hotkeys", "key commands"]
        }
    }

    /// Whether Settings has the section on this kind of device: an iPhone
    /// has one bar and no trackpad, an iPad no Desktop View.
    public func isOffered(phone: Bool) -> Bool {
        isOffered(phoneLayout: phone, padLayout: !phone)
    }

    /// Whether Settings has the section where windows take the phone's
    /// layout, the iPad's, or either: the iPhone Duo and a large iPhone have
    /// both, as they open or turn (Docs/iPhoneDuoPlan.md, decisions 5 and 9).
    public func isOffered(phoneLayout: Bool, padLayout: Bool) -> Bool {
        switch self {
        case .desktopView, .addressBar: return phoneLayout
        case .window, .trackpad, .shortcuts: return padLayout
        default: return true
        }
    }
}


/// Settings categories and command-search destinations share one routing policy.
public enum SettingsGroup: String, CaseIterable, Hashable, Sendable {
    case general, spaces, browsing, privacy, input, shortcuts, diagnostics

    public var title: String {
        switch self {
        case .general: return BrowserText.localized("General")
        case .spaces: return BrowserText.localized("Spaces and iCloud")
        case .browsing: return BrowserText.localized("Browsing")
        case .privacy: return BrowserText.localized("Search and privacy")
        case .input: return BrowserText.localized("Keyboard and trackpad")
        case .shortcuts: return BrowserText.localized("Shortcuts")
        case .diagnostics: return BrowserText.localized("Developer diagnostics")
        }
    }

    public var detail: String {
        switch self {
        case .general: return BrowserText.localized("Default browser and app icon")
        case .spaces: return BrowserText.localized("Spaces, bookmarks, pinned tabs and sync")
        case .browsing: return BrowserText.localized("Tabs, address bar, cursor, link menus and memory")
        case .privacy: return BrowserText.localized("Search suggestions, history, ads and trackers")
        case .input: return BrowserText.localized("Scrolling, keys and cursor styles")
        case .shortcuts: return BrowserText.localized("Browser commands and system limitations")
        case .diagnostics: return BrowserText.localized("Local troubleshooting information")
        }
    }

    public func isOffered(padLayout: Bool, keyboard: Bool, diagnostics: Bool) -> Bool {
        switch self {
        case .input, .shortcuts: return padLayout || keyboard
        case .diagnostics: return diagnostics
        default: return true
        }
    }
}

public extension SettingsAnchor {
    var group: SettingsGroup {
        switch self {
        case .defaultBrowser, .appIcon: return .general
        case .sync, .spaces: return .spaces
        case .desktopView, .addressBar, .window, .memory, .linkMenu: return .browsing
        case .search, .history, .blocking, .handoff: return .privacy
        case .trackpad: return .input
        case .shortcuts: return .shortcuts
        case .diagnostics: return .diagnostics
        }
    }
}
