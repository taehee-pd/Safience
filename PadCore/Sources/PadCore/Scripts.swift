import Foundation

/// What goes into a page at document start, put together for one site.
///
/// The app swaps a tab's scripts before each page it loads (Page.swift),
/// because an adapter belongs to a site and a tab goes from site to site.
/// On a hands-off host it installs none at all.
public enum Scripts {
    /// The bridge, bridge.js, as shipped.
    public static let bridge = load("bridge", "js")
    /// The app's own stylesheet, base.css.
    public static let style = load("base", "css")

    /// The settings bridge.js starts with, as JSON.
    struct Settings: Encodable {
        var adapter: String
        var css: String
        var handsOff: [String]
        var wheel: String
        var keys: [String]
        var cursor: Bool
    }

    /// For the app's own content world: the bridge, told which site it is on
    /// and what to add to the page, then the adapter's own script.
    public static func ours(for adapter: SiteAdapter, bridges: Bridges) -> String {
        let settings = Settings(
            adapter: adapter.id,
            css: [style, adapter.css].filter { !$0.isEmpty }.joined(separator: "\n"),
            handsOff: HandsOff.hosts,
            wheel: bridges.wheel.rawValue,
            keys: bridges.keys.map(\.rawValue).sorted(),
            cursor: bridges.cursors
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = (try? encoder.encode(settings)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
        var parts = ["window.__safienceConfig = \(json);", bridge]
        if !adapter.script.isEmpty { parts.append(isolated(adapter.script)) }
        return parts.joined(separator: "\n")
    }

    /// For the page's own world, or nil when the adapter has nothing there.
    public static func page(for adapter: SiteAdapter) -> String? {
        adapter.pageScript.isEmpty ? nil : isolated(adapter.pageScript)
    }

    /// A script that can fail without taking anything else down with it.
    static func isolated(_ script: String) -> String {
        "try {\n\(script)\n} catch (_) {}"
    }

    static func load(_ name: String, _ type: String) -> String {
        guard let file = Bundle.module.url(forResource: name, withExtension: type, subdirectory: "Scripts"),
              let text = try? String(contentsOf: file, encoding: .utf8)
        else { return "" }
        return text
    }
}
