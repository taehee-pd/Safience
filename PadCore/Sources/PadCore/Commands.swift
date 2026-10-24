import Foundation

/// Everything the browser itself can be asked to do, from a key, the menu
/// bar or the address bar, which finds each by its name.
public enum Command: String, CaseIterable, Sendable {
    /// The command bar opened empty, listing every tab, space, command and
    /// setting to choose from or narrow by typing, without making a new tab
    /// first as ⌘T does.
    case everything
    case newTab
    case closeTab
    case reopenTab
    case address
    case reload
    case stop
    case back
    case forward
    case nextTab
    case previousTab
    case nextSpace
    case previousSpace
    case newSpace
    case newWindow
    case closeWindow
    case tabBar
    case diagnostics
    case settings
    case focusPage
    case pinTab
    case splitTab
    case bookmark
    case share
    case copyLink
    case siteMode
    case spaceSettings
    case importBookmarks
    case contentBlocking
    case linkMenu
    case find
    case handoff
    case history

    public var title: String {
        switch self {
        case .everything: return BrowserText.localized("Commands")
        case .newTab: return BrowserText.localized("New Tab")
        case .closeTab: return BrowserText.localized("Close Tab")
        case .reopenTab: return BrowserText.localized("Reopen Closed Tab")
        case .address: return BrowserText.localized("Open Address")
        case .reload: return BrowserText.localized("Reload Page")
        case .stop: return BrowserText.localized("Stop Loading")
        case .back: return BrowserText.localized("Back")
        case .forward: return BrowserText.localized("Forward")
        case .nextTab: return BrowserText.localized("Next Tab")
        case .previousTab: return BrowserText.localized("Previous Tab")
        case .nextSpace: return BrowserText.localized("Next Space")
        case .previousSpace: return BrowserText.localized("Previous Space")
        case .newSpace: return BrowserText.localized("New Space")
        case .newWindow: return BrowserText.localized("New Window")
        case .closeWindow: return BrowserText.localized("Close Window")
        case .tabBar: return BrowserText.localized("Show or Hide Tab Bar")
        case .diagnostics: return BrowserText.localized("Show or Hide Diagnostics")
        case .settings: return BrowserText.localized("Settings")
        case .focusPage: return BrowserText.localized("Focus Page")
        case .pinTab: return BrowserText.localized("Pin or Unpin Tab")
        case .splitTab: return BrowserText.localized("Split or Separate Tabs")
        case .bookmark: return BrowserText.localized("Bookmark This Page")
        case .share: return BrowserText.localized("Share Page…")
        case .copyLink: return BrowserText.localized("Copy Link")
        case .siteMode: return BrowserText.localized("Request Desktop or Mobile Site")
        case .spaceSettings: return BrowserText.localized("Space Settings")
        case .importBookmarks: return BrowserText.localized("Import Bookmarks")
        case .contentBlocking: return BrowserText.localized("Block or Allow Ads on This Site")
        case .linkMenu: return BrowserText.localized("Site Link Menus")
        case .find: return BrowserText.localized("Find on Page…")
        case .handoff: return BrowserText.localized("Send Page to App…")
        case .history: return BrowserText.localized("Show All History")
        }
    }

    /// Words the address bar also finds it by.
    public var keywords: [String] {
        switch self {
        case .everything: return ["command palette", "find anything", "search", "switch", "list"]
        case .newTab: return ["open", "add"]
        case .closeTab: return ["remove"]
        case .reopenTab: return ["undo", "restore", "closed"]
        case .address: return ["url", "location", "go", "address bar"]
        case .reload: return ["refresh"]
        case .stop: return ["cancel"]
        case .back, .forward: return ["history", "navigate"]
        case .nextTab, .previousTab: return ["switch", "tab"]
        case .nextSpace, .previousSpace: return ["switch", "space", "profile"]
        case .newSpace: return ["profile", "workspace", "cookies"]
        case .newWindow: return ["stage manager", "scene"]
        case .closeWindow: return ["stage manager", "scene"]
        case .tabBar: return ["toolbar", "chrome", "full screen", "sidebar"]
        case .diagnostics: return ["debug", "hud", "bridge", "memory"]
        case .settings: return ["preferences", "options"]
        case .focusPage: return ["keyboard", "first responder", "focus"]
        case .pinTab: return ["pin", "keep", "unpin"]
        case .splitTab: return ["split view", "side by side", "two", "pane", "unsplit"]
        case .bookmark: return ["save", "favorite", "star", "remove bookmark"]
        case .share: return ["add to home screen", "send", "airdrop", "web app"]
        case .copyLink: return ["copy address", "copy url", "clipboard", "link"]
        case .siteMode: return ["desktop site", "mobile site", "user agent", "phone"]
        case .spaceSettings: return ["profile", "colour", "color", "icon", "rename"]
        case .importBookmarks: return ["chrome", "safari", "html", "favorites"]
        case .contentBlocking: return ["ad blocker", "adblock", "trackers", "content blocker", "easylist", "turn off", "allow ads"]
        case .linkMenu: return ["context menu", "right click", "long press", "link menu", "open in new tab", "callout"]
        case .find: return ["search", "text", "look for", "in page", "word"]
        case .handoff:
            return ["ai", "ask", "assistant", "claude", "chatgpt", "gemini", "markdown", "summarize", "summarise",
                    "send", "hand off"]
        case .history: return ["history", "visited", "recent pages", "clear history", "delete history"]
        }
    }
}

/// A key as a shortcut names it.
public enum Key: Hashable, Sendable {
    case character(String)
    case left, right, up, down
    case escape, tab
}

/// The browser's own shortcuts are ⌃⌥ and a key, with ⇧ on a few: a pair of
/// modifiers pages almost never use, so ⌘ and everything else stays theirs.
/// Figma alone has hundreds of shortcuts on ⌘, ⌥ and ⇧. The exceptions are
/// the keys every browser keeps for itself, which no page can count on:
/// ⌘T, ⌘W, ⌘N and the like, on the commands Chrome reserves from pages
/// (Shortcuts.reserved).
public struct Chord: Hashable, Sendable {
    /// What is held with the key, ⇧ aside.
    public enum Base: Hashable, Sendable {
        case controlOption
        case command
        case control
    }

    public var key: Key
    public var shift: Bool
    public var base: Base

    public init(_ key: Key, shift: Bool = false, _ base: Base = .controlOption) {
        self.key = key
        self.shift = shift
        self.base = base
    }

    /// As the menu bar writes it, modifiers in Apple's order: ⌃⌥⇧T, ⇧⌘T.
    public var label: String {
        caps.joined()
    }

    /// The keys held, one by one in that order, to draw each as a key
    /// beside its command (the command bar, Settings).
    public var caps: [String] {
        let name: String
        switch key {
        case .character(let c): name = c.uppercased()
        case .left: name = "←"
        case .right: name = "→"
        case .up: name = "↑"
        case .down: name = "↓"
        case .escape: name = "⎋"
        case .tab: name = "⇥"
        }
        let shifted = shift ? ["⇧"] : []
        switch base {
        case .controlOption: return ["⌃", "⌥"] + shifted + [name]
        case .command: return shifted + ["⌘", name]
        case .control: return ["⌃"] + shifted + [name]
        }
    }
}

/// The commands as the menu bar has them, a menu each, and in that order
/// wherever they are listed with their keys (the command bar, Settings):
/// every command in one group and only one.
public enum ShortcutGroup: String, CaseIterable, Sendable {
    case go = "Go"
    case tabs = "Tabs"
    case spaces = "Spaces"
    case window = "Window"

    public var title: String {
        rawValue
    }

    public var commands: [Command] {
        switch self {
        case .go:
            return [.address, .everything, .back, .forward, .history, .reload, .stop, .share, .copyLink, .handoff, .siteMode,
                    .contentBlocking, .linkMenu, .find]
        case .tabs: return [.newTab, .closeTab, .reopenTab, .pinTab, .splitTab, .bookmark, .nextTab, .previousTab]
        case .spaces: return [.nextSpace, .previousSpace, .newSpace, .spaceSettings, .importBookmarks, .newWindow, .closeWindow]
        // Settings is in the app's own menu, where an app's settings go; it
        // is listed with the window's here.
        case .window: return [.tabBar, .diagnostics, .focusPage, .settings]
        }
    }
}

public enum Shortcuts {
    public static let chords: [Command: Chord] = [
        .everything: Chord(.character("k")),
        .newTab: Chord(.character("t"), .command),
        .closeTab: Chord(.character("w"), .command),
        .reopenTab: Chord(.character("t"), shift: true, .command),
        .address: Chord(.character("l")),
        .reload: Chord(.character("r")),
        .stop: Chord(.character(".")),
        .back: Chord(.character("[")),
        .forward: Chord(.character("]")),
        .nextTab: Chord(.tab, .control),
        .previousTab: Chord(.tab, shift: true, .control),
        .nextSpace: Chord(.down),
        .previousSpace: Chord(.up),
        .newSpace: Chord(.character("n"), shift: true),
        .newWindow: Chord(.character("n"), .command),
        .closeWindow: Chord(.character("w"), shift: true, .command),
        .tabBar: Chord(.character("b")),
        .diagnostics: Chord(.character("d")),
        .settings: Chord(.character(",")),
        .focusPage: Chord(.character("p")),
        .pinTab: Chord(.character("p"), shift: true),
        .splitTab: Chord(.character("\\")),
        .bookmark: Chord(.character("d"), shift: true),
        .share: Chord(.character("s")),
        .copyLink: Chord(.character("c"), shift: true),
        .siteMode: Chord(.character("m"), shift: true),
        .spaceSettings: Chord(.character("s"), shift: true),
        .importBookmarks: Chord(.character("i"), shift: true),
        .contentBlocking: Chord(.character("a"), shift: true),
        .linkMenu: Chord(.character("l"), shift: true),
        .find: Chord(.character("f")),
        .handoff: Chord(.character("h")),
        .history: Chord(.character("y")),
    ]

    public static func chord(for command: Command) -> Chord? {
        chords[command]
    }

    /// The commands on the keys every browser keeps for itself, as browsers
    /// and tabbed apps have them: Chrome reserves these from pages
    /// (IsReservedCommandOrKey, browser_command_controller.cc), so no page
    /// counts on ⌘T, ⌘W, ⌘N, ⇧⌘T, ⇧⌘W, ⌃⇥ or ⌃⇧⇥. Every other command is on ⌃⌥.
    public static let reserved: Set<Command> = [.newTab, .closeTab, .reopenTab, .newWindow, .closeWindow,
                                                .nextTab, .previousTab]

    /// ⌃⌥1 to ⌃⌥9: the nth tab of the space, ⌃⌥9 the last, as in every browser.
    public static let tabNumbers = (1...9).map { Chord(.character(String($0))) }

    /// Each chord names one command: a second would be a key that does two things.
    public static var isUnambiguous: Bool {
        let all = Array(chords.values) + tabNumbers
        return Set(all).count == all.count
    }
}

/// A line typed into the address bar, as the place it means:
/// an address when it looks like one (Address.swift), a search with the
/// chosen engine otherwise.
public enum Destination {
    public static func url(for typed: String, engine: String) -> URL? {
        let text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if let address = Address.url(from: text) { return Address.reachable(address) ?? address }
        return search(text, engine: engine)
    }

    /// The typed words as a search, never as an address.
    public static func search(_ text: String, engine: String) -> URL? {
        let chosen = Engine(rawValue: engine) ?? Engine.standard
        return Engine.url(for: text, template: chosen.template)
    }

    /// The words, when `url` is a search with the chosen engine: what the
    /// address shows in place of the engine's address, and what typing
    /// starts with, as Safari does. Nil for every other page.
    public static func searchWords(in url: URL, engine: String) -> String? {
        (Engine(rawValue: engine) ?? Engine.standard).words(in: url)
    }

    /// The address as the field shows it for editing, or the words of a
    /// search with the chosen engine, which sent again search again.
    public static func editable(_ url: URL, engine: String) -> String {
        searchWords(in: url, engine: engine) ?? Address.editable(url)
    }

    /// The engines Settings offers, as (id, name).
    public static var engines: [(id: String, name: String)] {
        Engine.allCases.map { ($0.rawValue, $0.title) }
    }

    public static var standardEngine: String { Engine.standard.rawValue }

    /// The address as a person reads it: no scheme, no www., no lone slash.
    public static func pretty(_ url: URL) -> String {
        Address.pretty(url)
    }

    /// The address as the field shows it for editing.
    public static func editable(_ url: URL) -> String {
        Address.editable(url)
    }

    /// The part of the host that says who you are talking to, figma.com in
    /// www.figma.com, for the address bar to set in bold.
    public static func registrable(_ host: String) -> String {
        Registrable.domain(of: host, isSuffix: PublicSuffixes.contains)
    }
}

/// The handful of public suffixes that matter for telling a site's own name
/// out of a host: two-level country suffixes and the hosting suffixes where
/// every customer is a site of their own. Not the whole list; a host under a
/// suffix not here is shown with one label more than it should be, which only
/// makes the bold part longer.
enum PublicSuffixes {
    static let known: Set<String> = [
        "co.uk", "org.uk", "ac.uk", "gov.uk", "co.jp", "or.jp", "ne.jp", "ac.jp", "co.kr", "or.kr", "ac.kr",
        "com.au", "net.au", "org.au", "co.nz", "com.br", "com.cn", "com.tw", "com.hk", "co.in", "com.sg",
        "github.io", "vercel.app", "netlify.app", "pages.dev", "web.app", "firebaseapp.com",
        "herokuapp.com", "azurewebsites.net", "cloudfront.net", "framer.website", "webflow.io",
    ]

    static func contains(_ suffix: String) -> Bool {
        if known.contains(suffix) { return true }
        // Every single label is a suffix: com, io, design, kr.
        return !suffix.contains(".")
    }
}
