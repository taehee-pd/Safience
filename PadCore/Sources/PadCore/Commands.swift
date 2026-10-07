import Foundation

/// Everything the browser itself can be asked to do, from a key, the menu
/// bar or the command palette.
public enum Command: String, CaseIterable, Sendable {
    case palette
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
    case siteMode
    case spaceSettings
    case importBookmarks

    public var title: String {
        switch self {
        case .palette: return "Command Palette"
        case .newTab: return "New Tab"
        case .closeTab: return "Close Tab"
        case .reopenTab: return "Reopen Closed Tab"
        case .address: return "Open Address"
        case .reload: return "Reload Page"
        case .stop: return "Stop Loading"
        case .back: return "Back"
        case .forward: return "Forward"
        case .nextTab: return "Next Tab"
        case .previousTab: return "Previous Tab"
        case .nextSpace: return "Next Space"
        case .previousSpace: return "Previous Space"
        case .newSpace: return "New Space"
        case .newWindow: return "New Window"
        case .closeWindow: return "Close Window"
        case .tabBar: return "Show or Hide Tab Bar"
        case .diagnostics: return "Show or Hide Diagnostics"
        case .settings: return "Settings"
        case .focusPage: return "Give Keys Back to the Page"
        case .pinTab: return "Pin or Unpin Tab"
        case .splitTab: return "Split or Separate Tabs"
        case .bookmark: return "Bookmark This Page"
        case .share: return "Share Page…"
        case .siteMode: return "Request Desktop or Mobile Site"
        case .spaceSettings: return "Space Settings"
        case .importBookmarks: return "Import Bookmarks"
        }
    }

    /// Words the palette also finds it by.
    public var keywords: [String] {
        switch self {
        case .palette: return ["search", "switch"]
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
        case .tabBar: return ["toolbar", "chrome", "full screen"]
        case .diagnostics: return ["debug", "hud", "bridge", "memory"]
        case .settings: return ["preferences", "options"]
        case .focusPage: return ["keyboard", "first responder", "focus"]
        case .pinTab: return ["pin", "keep", "unpin"]
        case .splitTab: return ["split view", "side by side", "two", "pane", "unsplit"]
        case .bookmark: return ["save", "favorite", "star", "remove bookmark"]
        case .share: return ["add to home screen", "copy link", "send", "airdrop", "web app"]
        case .siteMode: return ["desktop site", "mobile site", "user agent", "phone"]
        case .spaceSettings: return ["profile", "colour", "color", "icon", "rename"]
        case .importBookmarks: return ["chrome", "safari", "html", "favorites"]
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
        let shifted = shift ? "⇧" : ""
        switch base {
        case .controlOption: return "⌃⌥" + shifted + name
        case .command: return shifted + "⌘" + name
        case .control: return "⌃" + shifted + name
        }
    }
}

public enum Shortcuts {
    public static let chords: [Command: Chord] = [
        .palette: Chord(.character("k")),
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
        .siteMode: Chord(.character("m"), shift: true),
        .spaceSettings: Chord(.character("s"), shift: true),
        .importBookmarks: Chord(.character("i"), shift: true),
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

/// A line typed into the palette or the address bar, as the place it means:
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
