import Foundation

/// A setting that can leave a choice to each site's adapter.
public enum Override: String, Codable, CaseIterable, Sendable {
    case site
    case on
    case off
}

/// Where the address goes.
public enum TabLayout: String, Codable, CaseIterable, Sendable {
    /// One row, as Safari's compact layout: the tab on screen is the address
    /// bar, and every other tab sits beside it.
    case compact
    /// A row of tabs, the address bar under it.
    case separate
}

/// Settings, saved as one JSON value. Every field has a default, and a field
/// missing from what was saved takes its default, so a setting added later
/// doesn't throw away the ones already there.
public struct Preferences: Codable, Equatable, Sendable {
    /// Always, so the page's address and the way back are in view on every
    /// page; Settings can keep it to sign-in pages.
    public var layout: TabLayout = .compact
    public var address: AddressMode = .always
    public var tabBar = true
    /// The wheel bridge for every site, or nil to leave it to each adapter.
    public var wheel: WheelMode?
    /// Tab and the arrow keys taken from the system for the page.
    public var keys: Override = .site
    public var limits = LiveLimits()
    public var diagnostics = false
    public var engine = Destination.standardEngine
    /// Pages' own cursor images, drawn over the hidden system pointer.
    public var pageCursors = true
    /// Request Desktop Site or Request Mobile Site, by site (SiteMode.siteKey).
    public var siteModes: [String: SiteMode] = [:]
    /// Spaces and their bookmarks kept in iCloud (CloudSync.swift); off until turned on.
    public var iCloudSync = false
    /// How far the iPhone's desktop view cursor goes for a finger's move,
    /// times the usual (DesktopView.cursorSpeeds).
    public var cursorSpeed = 1.0
    /// Ads and trackers blocked by WebKit's content blocker, with EasyList
    /// and EasyPrivacy (ContentBlocking.swift); on unless turned off.
    public var blocksContent = true
    /// The sites it is off for, by site (SiteMode.siteKey).
    public var unblockedSites: [String] = []

    public init() {}

    enum CodingKeys: String, CodingKey {
        case layout, address, tabBar, wheel, keys, limits, diagnostics, engine, pageCursors, siteModes, iCloudSync, cursorSpeed
        case blocksContent, unblockedSites
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        layout = (try? c.decodeIfPresent(TabLayout.self, forKey: .layout)) ?? .compact
        address = (try? c.decodeIfPresent(AddressMode.self, forKey: .address)) ?? .always
        tabBar = (try? c.decodeIfPresent(Bool.self, forKey: .tabBar)) ?? true
        wheel = (try? c.decodeIfPresent(WheelMode.self, forKey: .wheel)) ?? nil
        keys = (try? c.decodeIfPresent(Override.self, forKey: .keys)) ?? .site
        limits = (try? c.decodeIfPresent(LiveLimits.self, forKey: .limits)) ?? LiveLimits()
        diagnostics = (try? c.decodeIfPresent(Bool.self, forKey: .diagnostics)) ?? false
        engine = (try? c.decodeIfPresent(String.self, forKey: .engine)) ?? Destination.standardEngine
        pageCursors = (try? c.decodeIfPresent(Bool.self, forKey: .pageCursors)) ?? true
        siteModes = (try? c.decodeIfPresent([String: SiteMode].self, forKey: .siteModes)) ?? [:]
        iCloudSync = (try? c.decodeIfPresent(Bool.self, forKey: .iCloudSync)) ?? false
        let speed = (try? c.decodeIfPresent(Double.self, forKey: .cursorSpeed)) ?? 1
        cursorSpeed = min(max(speed, DesktopView.cursorSpeeds.lowerBound), DesktopView.cursorSpeeds.upperBound)
        blocksContent = (try? c.decodeIfPresent(Bool.self, forKey: .blocksContent)) ?? true
        unblockedSites = (try? c.decodeIfPresent([String].self, forKey: .unblockedSites)) ?? []
    }

    /// Whether a page at `host` has ads and trackers blocked.
    public func blocksContent(onHost host: String?) -> Bool {
        guard blocksContent else { return false }
        guard let site = SiteMode.siteKey(host) else { return true }
        return !unblockedSites.contains(site)
    }

    /// Blocking on or off for the site at `host`, the rest as they were.
    public mutating func setBlocksContent(_ on: Bool, onHost host: String?) {
        guard let site = SiteMode.siteKey(host) else { return }
        unblockedSites.removeAll { $0 == site }
        if !on { unblockedSites.append(site) }
        unblockedSites.sort()
    }

    /// An adapter's bridges with these settings laid over them.
    public func bridges(for adapter: SiteAdapter) -> Bridges {
        var bridges = adapter.bridges
        if let wheel { bridges.wheel = wheel }
        switch keys {
        case .site: break
        case .on: bridges.keys = Set(RelayKey.allCases)
        case .off: bridges.keys = []
        }
        if !pageCursors { bridges.cursors = false }
        return bridges
    }
}
