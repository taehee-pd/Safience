import PadCore
import SwiftUI
import WebKit

/// A small panel over the page (⌃⌥D) for checking the bridges on a real
/// iPad: what the page is told it runs in, what the trackpad and the keys
/// send it, whether WebKit sends wheel events of its own, and which tabs
/// are live. Nothing in it leaves the iPad.
struct DiagnosticsView: View {
    let page: () -> Page?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Diagnostics.lines(for: page()), id: \.self) { line in
                    Text(line)
                }
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(Palette.ink)
            .padding(10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Metrics.corner))
            .overlay(RoundedRectangle(cornerRadius: Metrics.corner).stroke(Palette.hairline))
        }
    }
}

@MainActor
enum Diagnostics {
    static func lines(for page: Page?) -> [String] {
        let pages = Session.shared.pages
        let tabs = "tabs live \(pages.live.count) · frozen or unopened \(max(0, pages.frozenCount))"
        guard let page else { return ["no page", tabs] }
        let view = page.view
        let scroll = view.scrollView
        let stats = page.stats
        let bridges = page.bridges
        let expected = Identity.macUserAgent(applicationName: Identity.applicationName(for: ProcessInfo.processInfo.operatingSystemVersion))
        let agent: String
        if page.isHandsOff {
            agent = "user agent: not read here (hands-off page)"
        } else if let seen = stats.userAgent {
            agent = seen == expected ? "user agent: Mac Safari, as sent" : "user agent: \(seen)"
        } else {
            agent = "user agent: not reported yet"
        }
        let mode = view.configuration.defaultWebpagePreferences.preferredContentMode == .desktop ? "desktop" : "mobile"
        return [
            "\(page.adapter.name)\(page.isHandsOff ? " · hands-off, nothing injected" : "") · \(mode) pages · \(page.isHeavy ? "heavy" : "light")",
            "zoom \(String(format: "%.2f", Double(scroll.zoomScale))) · WebKit scrolling \(scroll.isScrollEnabled ? "on" : "off") · its pinch \(scroll.pinchGestureRecognizer?.isEnabled == true ? "on" : "off")",
            agent,
            "pinch \(stats.pinchSteps) · ⌘ zoom \(stats.commandZoomSteps) · bridged \(stats.bridgedWheels) · stood aside \(stats.standAside)",
            "WebKit wheel events seen by the page \(stats.webKitWheels) · last: \(stats.lastOutcome.isEmpty ? "none" : stats.lastOutcome)",
            "wheel bridge \(bridges.wheel.rawValue) · keys to page: \(bridges.keys.isEmpty ? "none" : bridges.keys.map(\.rawValue).sorted().joined(separator: ", ")) · relayed \(stats.relayedKeys) · typing: \(page.editing ? "yes" : "no")",
            "\(tabs) · process ends \(stats.processEnds)",
            "cursor: \(bridges.cursors ? page.pointer?.cursorSummary ?? "the system's" : "the system's (pages' cursors off)")",
        ]
    }
}
