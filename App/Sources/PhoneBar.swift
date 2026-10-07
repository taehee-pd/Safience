import PadCore
import SwiftUI
import UIKit

/// The bars on a phone-width window (an iPhone, the iPhone Duo folded, a
/// narrow iPad window), at the bottom where a thumb reaches, as Safari and
/// Comet have them: the address across the width with the page's menu beside
/// it, and under it one row of tools packed around the space, drawn plain so
/// the address and the space stand out. While an address is typed only the
/// address shows, over the keyboard, with Cancel. A swipe up on the bar
/// shows the space's tabs (Browser.swipedBar).
struct PhoneBar: View {
    @ObservedObject var session: Session
    @ObservedObject var window: WindowModel
    let act: (BarAction) -> Void

    /// The address over a row of tools, each 44 points, with room between
    /// so the two rows read apart.
    static let height: CGFloat = 6 + 44 + rowGap + 44
    private static let rowGap: CGFloat = 10
    /// The address alone, over the keyboard.
    static let typingHeight: CGFloat = 6 + 44 + 6

    var body: some View {
        let typing = window.editingAddress
        VStack(spacing: Self.rowGap) {
            HStack(spacing: 8) {
                AddressCapsule(window: window, editable: window.phone, act: act)
                if typing {
                    Button("Cancel") { act(.cancelAddress) }
                        .font(.system(size: 16))
                        .foregroundStyle(Palette.ink)
                        .padding(.horizontal, 4)
                        .frame(height: 44)
                        .contentShape(Rectangle())
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    PageMenu(session: session, window: window, act: act)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 12)
            if !typing {
                PhoneTools(session: session, window: window, act: act)
                    .frame(height: 44)
                    .transition(.opacity)
            }
        }
        .padding(.top, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.barScale, .thumb)
        // Loading shows along the top edge here, next to the page.
        .overlay(alignment: .top) { LoadingLine(window: window) }
        .animation(.bar, value: typing)
        .ignoresSafeArea(.keyboard)
    }
}

/// The phone bar's row of tools around the space in the middle: back and
/// forward on one side, a new tab and the tabs on the other, the gaps
/// between them shared out evenly across the width. Two tools a side, so
/// the space sits at the centre whatever its name.
private struct PhoneTools: View {
    @ObservedObject var session: Session
    @ObservedObject var window: WindowModel
    let act: (BarAction) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ToolIcon(symbol: "chevron.left", label: "Back", enabled: window.canGoBack) { act(.back) }
            Spacer(minLength: 4)
            ToolIcon(symbol: "chevron.right", label: "Forward", enabled: window.canGoForward) { act(.forward) }
            Spacer(minLength: 4)
            // As wide as its name, up to a point.
            SpaceButton(session: session, window: window, act: act)
                .fixedSize()
            Spacer(minLength: 4)
            ToolIcon(symbol: "plus", label: "New Tab") { act(.command(.newTab)) }
            Spacer(minLength: 4)
            TabsButton(tabs: session.workspace.space(window.spaceID)?.tabs ?? [], current: window.tabID, act: act)
        }
        .padding(.horizontal, 12)
    }
}

/// A tool on the phone bar: a symbol alone, 44 points of it answering a touch.
private struct ToolIcon: View {
    let symbol: String
    let label: String
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                // Dimmed by opacity, not a solid grey: the page shows through the
                // bar, and a light grey vanishes over a light one.
                .foregroundStyle(enabled ? Palette.ink : Palette.ink.opacity(0.3))
                // A chevron's point sits off its box; nudged toward the way it points.
                .offset(x: symbol == "chevron.left" ? -0.5 : symbol == "chevron.right" ? 0.5 : 0)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScale())
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}

/// How many tabs the space has, in a square, as Safari's tabs button is.
/// A tap shows them; a long press has Safari's menu: a new tab, closing
/// this one, closing them all.
private struct TabsButton: View {
    let tabs: [TabRecord]
    let current: UUID?
    let act: (BarAction) -> Void

    var body: some View {
        let ordinary = tabs.filter { !$0.isPinned }
        Menu {
            Button("New Tab", systemImage: "plus.square.on.square") { act(.command(.newTab)) }
            if let current, ordinary.contains(where: { $0.id == current }) {
                Button("Close This Tab", systemImage: "xmark", role: .destructive) { act(.close(current)) }
            }
            if ordinary.count > 1 {
                Button("Close All \(ordinary.count) Tabs", systemImage: "xmark.square.fill", role: .destructive) {
                    act(.closeTabs(ordinary.map(\.id)))
                }
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                    .strokeBorder(Palette.ink, lineWidth: 1.8)
                    .frame(width: 22, height: 22)
                Text(tabs.count > 99 ? "∞" : "\(tabs.count)")
                    .font(.system(size: 12, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        } primaryAction: {
            act(.showTabs)
        }
        .accessibilityLabel("Tabs, \(tabs.count)")
        .accessibilityHint("Or swipe up on the bar")
    }
}

/// The page's own commands, which the iPad has on its tabs' menus and on ⌃⌥:
/// a round glass button beside the address, as high as it.
private struct PageMenu: View {
    @ObservedObject var session: Session
    @ObservedObject var window: WindowModel
    let act: (BarAction) -> Void

    var body: some View {
        let tab = window.tabID.flatMap { session.workspace.tab($0) }
        Menu {
            PageItems(window: window, act: act)
            if window.canDesktopView || window.desktopView {
                // The page at an iPad's size, with a cursor the finger moves as on a trackpad.
                Button(window.desktopView ? "Leave Desktop View" : "Desktop View",
                       systemImage: window.desktopView ? "iphone" : "cursorarrow.rays") { act(.desktopView) }
            }
            if let tab {
                if tab.isPinned {
                    Button("Unpin Tab", systemImage: "pin.slash") { act(.unpin(tab.id)) }
                } else if tab.url != nil {
                    Button("Pin Tab", systemImage: "pin") { act(.pin(tab.id)) }
                }
            }
            Section { AppItems(act: act) }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .frame(width: 44, height: 44)
                .liquidGlass(in: Circle(), otherwise: Palette.wash)
                .contentShape(Circle())
        }
        .accessibilityLabel("More")
    }
}
