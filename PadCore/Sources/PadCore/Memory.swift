import Foundation

/// How many tabs keep their page in memory while off screen.
///
/// Every page runs in a WebKit content process of its own, and iPadOS gives
/// each such process a ceiling the app cannot raise: no entitlement reaches
/// WebKit's processes, only the app's own. A large Figma file can use most of
/// that ceiling by itself, and every other live page takes from the memory
/// the system has left before it starts closing processes. So the heaviest
/// pages are kept to one, and the rest freeze: the page is let go and a
/// picture of it stays, and opening the tab again loads it again.
public struct LiveLimits: Codable, Equatable, Sendable {
    /// Heavy tabs kept live, the one on screen included. One: switching from
    /// a design file to Slack and back keeps the file open, and a second file
    /// freezes the first. Tabs on screen are never frozen, so two windows
    /// side by side can show two heavy tabs.
    public var heavy: Int
    /// Light tabs kept live off screen, the most recently shown first.
    public var lightOffScreen: Int

    public init(heavy: Int = 1, lightOffScreen: Int = 2) {
        self.heavy = heavy
        self.lightOffScreen = lightOffScreen
    }
}

/// A tab as the freezer sees it.
public struct TabLoad: Equatable, Sendable {
    public var id: UUID
    public var heavy: Bool
    public var onScreen: Bool
    public var live: Bool
    public var lastShown: Date
    /// Something only a live page can keep going: a call, a recording, a
    /// download, a page that can't be asked whether it holds anything typed.
    public var mustStay: Bool

    public init(id: UUID, heavy: Bool, onScreen: Bool, live: Bool, lastShown: Date, mustStay: Bool = false) {
        self.id = id
        self.heavy = heavy
        self.onScreen = onScreen
        self.live = live
        self.lastShown = lastShown
        self.mustStay = mustStay
    }
}

public enum Freezer {
    /// The live tabs to freeze, the one shown longest ago first. Under memory
    /// pressure that is every live tab off screen that can go.
    public static func plan(_ tabs: [TabLoad], limits: LiveLimits, pressure: Bool) -> [UUID] {
        let candidates = tabs.filter { $0.live && !$0.onScreen && !$0.mustStay }
        if pressure {
            return candidates.sorted { $0.lastShown < $1.lastShown }.map(\.id)
        }
        let heavyShown = tabs.filter { $0.heavy && $0.onScreen }.count
        var heavyRoom = max(0, limits.heavy - heavyShown)
        var lightRoom = max(0, limits.lightOffScreen)
        // Tabs that can't freeze still take their room.
        for tab in tabs where tab.live && !tab.onScreen && tab.mustStay {
            if tab.heavy { heavyRoom = max(0, heavyRoom - 1) } else { lightRoom = max(0, lightRoom - 1) }
        }
        var freeze: [TabLoad] = []
        for tab in candidates.sorted(by: { $0.lastShown > $1.lastShown }) {
            if tab.heavy {
                if heavyRoom > 0 { heavyRoom -= 1 } else { freeze.append(tab) }
            } else {
                if lightRoom > 0 { lightRoom -= 1 } else { freeze.append(tab) }
            }
        }
        return freeze.sorted { $0.lastShown < $1.lastShown }.map(\.id)
    }
}

/// Reloading a page whose process ended, unless it keeps ending.
///
/// When WebKit's content process for a page is closed (out of memory, most
/// often) the page goes blank; the tab on screen reloads by itself. A page
/// that runs out of memory every time it loads would reload forever, so after
/// `limit` endings inside `window` the tab waits for a click instead.
public struct CrashGuard: Equatable, Sendable {
    public var limit: Int
    public var window: TimeInterval
    public private(set) var endings: [Date] = []

    public init(limit: Int = 3, window: TimeInterval = 60) {
        self.limit = limit
        self.window = window
    }

    /// Notes an ending at `time` and says whether to reload by itself.
    public mutating func shouldReload(at time: Date) -> Bool {
        endings = endings.filter { time.timeIntervalSince($0) < window } + [time]
        return endings.count < limit
    }

    public mutating func reset() {
        endings = []
    }
}
