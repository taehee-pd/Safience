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
            TabsButton(count: session.workspace.space(window.spaceID)?.tabs.count ?? 0) { act(.showTabs) }
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
private struct TabsButton: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                    .strokeBorder(Palette.ink, lineWidth: 1.8)
                    .frame(width: 22, height: 22)
                Text(count > 99 ? "∞" : "\(count)")
                    .font(.system(size: 12, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScale())
        .accessibilityLabel("Tabs, \(count)")
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

/// The space's tabs as a grid, from the phone bar's Tabs button or a swipe
/// up on it, as Safari and Comet show theirs: each tab as a picture of its
/// page with its name under it, the pinned ones first as icons; a tap goes
/// to it. New Tab and Done are at the bottom, where the thumb already is.
struct TabOverview: View {
    @ObservedObject var session: Session
    @ObservedObject var window: WindowModel
    /// Done in place: closing a tab.
    let act: (BarAction) -> Void
    /// Done with the overview: going to a tab, a new tab, or nothing.
    let done: (BarAction?) -> Void
    @StateObject private var previews = TabPreviews()
    @ObservedObject private var sync = Sync.shared

    var body: some View {
        let space = session.workspace.space(window.spaceID)
        let tabs = space?.tabs ?? []
        let pinned = tabs.filter(\.isPinned)
        let others = tabs.filter { !$0.isPinned }
        let color = space?.color.color ?? Palette.ink
        NavigationStack {
            ScrollViewReader { scroller in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if !pinned.isEmpty {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 60), spacing: 10)], spacing: 10) {
                                ForEach(pinned) { tab in
                                    PinnedTile(tab: tab, current: tab.id == window.tabID, color: color) { done(.select(tab.id)) }
                                        .id(tab.id)
                                }
                            }
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 18) {
                            ForEach(others) { tab in
                                TabCard(tab: tab, image: previews.images[tab.id], current: tab.id == window.tabID, color: color,
                                        open: { done(.select(tab.id)) }, close: { act(.close(tab.id)) })
                                    .id(tab.id)
                                    // As each card comes into view, so a space of many tabs never holds every picture.
                                    .onAppear { previews.load(tab, width: Pages.previewWidth) }
                                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                            }
                        }
                        // The space's tabs on other devices, to pick up from (Sync).
                        ForEach(sync.elsewhere.filter { $0.space == space?.cloudID?.uuidString }, id: \.id) { device in
                            ElsewhereList(device: device) { url in done(.openInNewTab(url)) }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .animation(.bar, value: tabs.map(\.id))
                }
                .onAppear {
                    if let current = window.tabID { scroller.scrollTo(current, anchor: .center) }
                }
            }
            .background(Palette.ground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Which space these are, in its colour: the one thing on the sheet that is.
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        Image(systemName: space?.symbol ?? "square.grid.2x2")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(color)
                        Text(space?.name ?? "Tabs")
                            .font(.headline)
                            .foregroundStyle(Palette.ink)
                    }
                    .accessibilityElement(children: .combine)
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button("New Tab", systemImage: "plus") { done(.command(.newTab)) }
                    Spacer()
                    Button("Done") { done(nil) }
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

/// Another device's open tabs in this space: its name over a list, a tap
/// opening one here in a new tab.
private struct ElsewhereList: View {
    let device: SyncDeviceTabs
    let open: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("\(device.browser) · \(device.deviceName)", systemImage: device.browser == "Safience" ? "iphone" : "laptopcomputer")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.muted)
                .padding(.horizontal, 4)
            VStack(spacing: 0) {
                ForEach(Array(device.tabs.enumerated()), id: \.offset) { index, tab in
                    if let url = URL(string: tab.url) {
                        Button { open(url) } label: {
                            HStack(spacing: 10) {
                                SiteIconView(url: url, size: 20)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(tab.title.isEmpty ? Destination.pretty(url) : tab.title)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(Palette.ink)
                                        .lineLimit(1)
                                    Text(Destination.pretty(url))
                                        .font(.system(size: 12))
                                        .foregroundStyle(Palette.muted)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                Spacer(minLength: 0)
                                if tab.pinned {
                                    Image(systemName: "pin.fill").font(.system(size: 10)).foregroundStyle(Palette.muted)
                                }
                            }
                            .padding(.horizontal, 12)
                            .frame(minHeight: 48)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressScale())
                        if index < device.tabs.count - 1 {
                            Rectangle().fill(Palette.hairline).frame(height: 1).padding(.leading, 42)
                        }
                    }
                }
            }
            .background(Palette.wash, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(.top, 6)
    }
}

/// Pictures of a space's tabs for the overview, asked for once each, as their cards show.
@MainActor
private final class TabPreviews: ObservableObject {
    @Published private(set) var images: [UUID: UIImage] = [:]
    private var asked: Set<UUID> = []

    func load(_ tab: TabRecord, width: CGFloat) {
        guard tab.url != nil, !asked.contains(tab.id) else { return }
        asked.insert(tab.id)
        let id = tab.id
        Session.shared.pages.preview(for: id, width: width) { [weak self] image in
            guard let image else { return }
            self?.images[id] = image
        }
    }
}

/// A pinned tab in the overview: its site's icon on a tile.
private struct PinnedTile: View {
    let tab: TabRecord
    let current: Bool
    let color: Color
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            SiteIconView(url: tab.pinned ?? tab.url, size: 28)
                .frame(width: 56, height: 56)
                .background(Palette.wash, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(4)
                .overlay {
                    if current {
                        RoundedRectangle(cornerRadius: 16 + 4, style: .continuous).strokeBorder(color, lineWidth: 2.5)
                    }
                }
        }
        .buttonStyle(PressScale())
        .accessibilityLabel("\(tab.label), pinned")
        .accessibilityAddTraits(current ? [.isSelected] : [])
    }
}

/// A tab in the overview: a picture of its page (or its site's icon, before
/// there is one), its name under it, and a close button on the picture; the
/// tab on screen ringed in the space's colour, the ring's corners following
/// the picture's.
private struct TabCard: View {
    let tab: TabRecord
    let image: UIImage?
    let current: Bool
    let color: Color
    let open: () -> Void
    let close: () -> Void
    @Environment(\.colorScheme) private var scheme

        private static let radius: CGFloat = 18
    /// Between the picture and the ring around the tab on screen.
    private static let gap: CGFloat = 4

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 6) {
                picture
                HStack(spacing: 6) {
                    SiteIconView(url: tab.url, size: 16)
                    Text(tab.label)
                        .font(.system(size: 13, weight: current ? .semibold : .medium))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                }
                .padding(.horizontal, Self.gap + 2)
            }
        }
        .buttonStyle(PressScale())
        .overlay(alignment: .topTrailing) {
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 26, height: 26)
                    .liquidGlass(in: Circle(), otherwise: Palette.wash)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressScale())
            .padding(Self.gap)
            .accessibilityLabel("Close \(tab.label)")
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(current ? [.isSelected] : [])
    }

    private var picture: some View {
        let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
        return Color.clear
            .aspectRatio(0.78, contentMode: .fit)
            // The top of the page, where what it is shows.
            .overlay(alignment: .top) {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        Palette.wash
                        SiteIconView(url: tab.url, size: 36)
                    }
                }
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(scheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1), lineWidth: 1))
            .shadow(color: .black.opacity(scheme == .dark ? 0.3 : 0.08), radius: 10, y: 3)
            .padding(Self.gap)
            .overlay {
                if current {
                    RoundedRectangle(cornerRadius: Self.radius + Self.gap, style: .continuous)
                        .strokeBorder(color, lineWidth: 2.5)
                }
            }
            .accessibilityHidden(true)
    }
}
