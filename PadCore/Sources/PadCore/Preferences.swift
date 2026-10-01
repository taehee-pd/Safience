import Foundation

/// A setting that can leave a choice to each site's adapter.
public enum Override: String, Codable, CaseIterable, Sendable {
    case site
    case on
    case off
}

/// Settings, saved as one JSON value. Every field has a default, and a field
/// missing from what was saved takes its default, so a setting added later
/// doesn't throw away the ones already there.
public struct Preferences: Codable, Equatable, Sendable {
    public var address: AddressMode = .automatic
    public var tabBar = true
    /// The wheel bridge for every site, or nil to leave it to each adapter.
    public var wheel: WheelMode?
    /// Tab and the arrow keys taken from the system for the page.
    public var keys: Override = .site
    public var limits = LiveLimits()
    public var diagnostics = false
    public var engine = Destination.standardEngine

    public init() {}

    enum CodingKeys: String, CodingKey {
        case address, tabBar, wheel, keys, limits, diagnostics, engine
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        address = (try? c.decodeIfPresent(AddressMode.self, forKey: .address)) ?? .automatic
        tabBar = (try? c.decodeIfPresent(Bool.self, forKey: .tabBar)) ?? true
        wheel = (try? c.decodeIfPresent(WheelMode.self, forKey: .wheel)) ?? nil
        keys = (try? c.decodeIfPresent(Override.self, forKey: .keys)) ?? .site
        limits = (try? c.decodeIfPresent(LiveLimits.self, forKey: .limits)) ?? LiveLimits()
        diagnostics = (try? c.decodeIfPresent(Bool.self, forKey: .diagnostics)) ?? false
        engine = (try? c.decodeIfPresent(String.self, forKey: .engine)) ?? Destination.standardEngine
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
        return bridges
    }
}
