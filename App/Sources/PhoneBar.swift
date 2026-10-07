import PadCore
import SwiftUI
import UIKit

/// The bars on a phone-width window (an iPhone, the iPhone Duo folded, a
/// narrow iPad window), at the bottom where a thumb reaches, as Safari has
/// them: back and forward, the address, and the tabs above; the space, a
/// new tab and the page's menu below.
struct PhoneBar: View {
    @ObservedObject var session: Session
    @ObservedObject var window: WindowModel
    let act: (BarAction) -> Void

    /// Two rows of 44.
    static let height: CGFloat = 2 * Metrics.bar + 4

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                HistoryButtons(window: window, act: act)
                AddressCapsule(window: window, editable: window.phone, act: act)
                TabsButton(count: session.workspace.space(window.spaceID)?.tabs.count ?? 0) { act(.showTabs) }
            }
            .frame(height: Metrics.bar)
            HStack(spacing: 2) {
                SpaceButton(session: session, window: window, act: act)
                Spacer(minLength: 0)
                BarButton(symbol: "plus", label: "New Tab") { act(.command(.newTab)) }
                PageMenu(session: session, window: window, act: act)
            }
            .frame(height: Metrics.bar)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Loading shows along the top edge here, next to the page.
        .overlay(alignment: .top) { LoadingLine(window: window) }
        .ignoresSafeArea(.keyboard)
    }
}

/// How many tabs the space has, in a square, as Safari's tabs button is.
private struct TabsButton: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Palette.ink, lineWidth: 1.8)
                    .frame(width: 20, height: 20)
                Text(count > 99 ? "∞" : "\(count)")
                    .font(.system(size: 11, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
            }
            .frame(width: Metrics.control, height: Metrics.control)
            .liquidGlass(in: Circle(), otherwise: .clear)
            .frame(width: Metrics.target, height: Metrics.target)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScale())
        .accessibilityLabel("Tabs, \(count)")
    }
}

/// The page's own commands, which the iPad has on its tabs' menus and on ⌃⌥.
private struct PageMenu: View {
    @ObservedObject var session: Session
    @ObservedObject var window: WindowModel
    let act: (BarAction) -> Void

    var body: some View {
        let tab = window.tabID.flatMap { session.workspace.tab($0) }
        Menu {
            if window.url != nil {
                Button("Share Page…", systemImage: "square.and.arrow.up") { act(.command(.share)) }
                Button(window.bookmarked ? "Remove Bookmark" : "Bookmark This Page",
                       systemImage: window.bookmarked ? "star.slash" : "star") { act(.toggleBookmark) }
                Button(window.mobileSite ? "Request Desktop Site" : "Request Mobile Site",
                       systemImage: window.mobileSite ? "desktopcomputer" : "iphone") { act(.command(.siteMode)) }
            }
            if let tab {
                if tab.isPinned {
                    Button("Unpin Tab", systemImage: "pin.slash") { act(.unpin(tab.id)) }
                } else if tab.url != nil {
                    Button("Pin Tab", systemImage: "pin") { act(.pin(tab.id)) }
                }
            }
            Section {
                Button("Command Palette", systemImage: "command") { act(.command(.palette)) }
                Button("Settings", systemImage: "gearshape") { act(.command(.settings)) }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .frame(width: Metrics.control, height: Metrics.control)
                .liquidGlass(in: Circle(), otherwise: .clear)
                .frame(width: Metrics.target, height: Metrics.target)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("More")
    }
}

/// The space's tabs as a grid, from the phone bar's Tabs button: the pinned
/// ones first as icons, then every tab as a card; a tap goes to it.
struct TabOverview: View {
    @ObservedObject var session: Session
    @ObservedObject var window: WindowModel
    /// Done in place: closing a tab.
    let act: (BarAction) -> Void
    /// Done with the overview: going to a tab, a new tab, or nothing.
    let done: (BarAction?) -> Void

    var body: some View {
        let space = session.workspace.space(window.spaceID)
        let tabs = space?.tabs ?? []
        let pinned = tabs.filter(\.isPinned)
        let others = tabs.filter { !$0.isPinned }
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if !pinned.isEmpty {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 12)], spacing: 12) {
                            ForEach(pinned) { tab in
                                Button { done(.select(tab.id)) } label: {
                                    SiteIconView(url: tab.pinned ?? tab.url, size: 28)
                                        .frame(width: 56, height: 56)
                                        .background(tab.id == window.tabID ? Palette.hover : Palette.wash,
                                                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                }
                                .buttonStyle(PressScale())
                                .accessibilityLabel("\(tab.label), pinned")
                            }
                        }
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                        ForEach(others) { tab in
                            TabCard(tab: tab, current: tab.id == window.tabID, color: space?.color.color ?? Palette.ink,
                                    open: { done(.select(tab.id)) }, close: { act(.close(tab.id)) })
                        }
                    }
                }
                .padding(16)
            }
            .background(Palette.ground)
            .navigationTitle(space?.name ?? "Tabs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("New Tab", systemImage: "plus") { done(.command(.newTab)) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { done(nil) }
                }
            }
            .animation(.bar, value: tabs.map(\.id))
        }
    }
}

/// A tab in the overview: its site's icon, what it is called and where it
/// is, and a close button; the tab on screen ringed in the space's colour.
private struct TabCard: View {
    let tab: TabRecord
    let current: Bool
    let color: Color
    let open: () -> Void
    let close: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    SiteIconView(url: tab.url, size: 24)
                    Spacer(minLength: 0)
                }
                Text(tab.label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(tab.url.map(Destination.pretty) ?? "New Tab")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            .background(Palette.wash, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                if current {
                    RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(color, lineWidth: 2.5)
                }
            }
        }
        .buttonStyle(PressScale())
        .overlay(alignment: .topTrailing) {
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Palette.muted)
                    .frame(width: 24, height: 24)
                    .background(Palette.hover, in: Circle())
                    .frame(width: Metrics.target, height: Metrics.target)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressScale())
            .accessibilityLabel("Close \(tab.label)")
        }
        .accessibilityAddTraits(current ? [.isSelected] : [])
    }
}
