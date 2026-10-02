import PadCore
import SwiftUI
import UIKit

/// Everything a bar, the palette, the start page or the empty space can ask
/// a window to do.
enum BarAction {
    case select(UUID)
    case close(UUID)
    case command(Command)
    case switchSpace(UUID)
    case spaceInNewWindow(UUID)
    case spaceSettings(UUID)
    case removeSpace(UUID)
    case moveTab(UUID, UUID)
    case tabInNewWindow(UUID)
    case pin(UUID)
    case unpin(UUID)
    case backToPinned(UUID)
    case editAddress
    case cancelAddress
    case go(String)
    case open(URL)
    case openInNewTab(URL)
    case back
    case forward
    case reload
    case stop
    case toggleBookmark
    case removeBookmark(UUID)
    case importBookmarks
    case dismissBanner
}

/// The row along the top.
///
/// Compact, as Safari's compact layout: the space, back and forward, the
/// pinned tabs as icons and the other tabs sharing the row, the one on
/// screen saying where it is; a click on that types a new address
/// (TabStrip). Or separate: the same row without back and forward, the
/// address bar under it (AddressBar).
///
/// Only the tab on screen is in Liquid Glass; every other tab is flat, so
/// the eye finds it at once.
struct TopBar: View {
    @ObservedObject var session: Session
    @ObservedObject var window: WindowModel
    let act: (BarAction) -> Void

    private var compact: Bool {
        session.preferences.layout == .compact
    }

    var body: some View {
        HStack(spacing: 2) {
            SpaceButton(session: session, window: window, act: act)
                .padding(.trailing, 4)
            if compact {
                HistoryButtons(window: window, act: act)
            }
            TabStrip(session: session, window: window, compact: compact, act: act)
            BarButton(symbol: "plus", label: "New Tab") { act(.command(.newTab)) }
            BarButton(symbol: "command", label: "Command Palette") { act(.command(.palette)) }
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) { LoadingLine(window: window) }
        .ignoresSafeArea(.keyboard)
    }
}

/// The strip's own coordinate space, where the tab on screen says where it is.
private let stripSpace = "TabStrip"

/// The tabs, sharing the row as Safari's do: each as wide as the others,
/// down to a width where their names still read, past which the row scrolls.
///
/// In the compact layout the address field grows out of the tab on screen
/// the way Safari's does (recorded in the iPad simulator): what the tab
/// says gives way to the address, selected, while the field widens over the
/// row; Return, Escape or a click on the page takes it back into the tab
/// along the same path. The tabs stay where they are underneath, so nothing
/// in the row moves, and the field is the tab's own glass, carried further.
struct TabStrip: View {
    @ObservedObject var session: Session
    @ObservedObject var window: WindowModel
    let compact: Bool
    let act: (BarAction) -> Void

    /// Where each tab was in the strip while it was on screen: the field
    /// starts from the tab on screen's place and goes back there. A tab not
    /// laid out yet (a new tab) has none, and the field is simply the row.
    @State private var origins: [UUID: CGRect] = [:]
    /// The field is drawn: while an address is typed, and on its way back.
    @State private var drawn = false
    /// The field covers the row; false while it is the tab's size.
    @State private var wide = false
    /// The field shows the address being typed; false while it still shows
    /// what the tab says.
    @State private var typing = false

    var body: some View {
        GeometryReader { box in
            let row = TabRow(tabs: session.workspace.space(window.spaceID)?.tabs ?? [], current: window.tabID,
                             compact: compact, addressRequired: window.addressRequired, width: box.size.width)
            let bounds = CGRect(origin: .zero, size: box.size)
            let start = Self.start(row.current.flatMap { origins[$0.id] }, in: bounds)
            let field = wide ? bounds : start
            let shown = compact && drawn
            ZStack(alignment: .topLeading) {
                tabs(row)
                    .mask {
                        // The tabs under the field are hidden, not seen through its glass.
                        Rectangle()
                            .overlay {
                                if shown {
                                    Capsule()
                                        .frame(width: field.width, height: Metrics.control)
                                        .position(x: field.midX, y: bounds.midY)
                                        .blendMode(.destinationOut)
                                }
                            }
                            .compositingGroup()
                    }
                if shown {
                    AddressField(window: window, typing: typing, act: act)
                        .frame(width: field.width, height: Metrics.control)
                        .position(x: field.midX, y: bounds.midY)
                        // On its way back it is only a picture: a click goes to the tabs.
                        .allowsHitTesting(window.editingAddress)
                    if let current = row.current {
                        // What the tab says, on the field and laid out across it, until
                        // the address takes its place: its words over the address being
                        // typed, its buttons at the field's end, so one fades into the
                        // other in place however far the field has got.
                        let tabWidth = row.width(of: current)
                        CurrentTabFace(window: window, tab: current, width: tabWidth.map { _ in field.width },
                                       buttons: CurrentTabFace.roomy(tabWidth), act: act)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                            .opacity(typing ? 0 : 1)
                            .position(x: tabWidth == nil ? field.minX + Metrics.target / 2 : field.midX, y: bounds.midY)
                    }
                }
            }
            .coordinateSpace(.named(stripSpace))
        }
        .onAppear { settle() }
        .onChange(of: compact) { _, _ in settle() }
        .onChange(of: window.editingAddress) { _, editing in
            if editing { open() } else { close() }
        }
    }

    private var otherSpaces: [Space] {
        session.workspace.spaces.filter { $0.id != window.spaceID }
    }

    private func tabs(_ row: TabRow) -> some View {
        ScrollViewReader { scroller in
            ScrollView(.horizontal) {
                GlassGroup(spacing: 4) {
                    HStack(spacing: 2) {
                        ForEach(row.pinned) { tab in chip(tab, in: row) }
                        if !row.pinned.isEmpty && !row.others.isEmpty {
                            Capsule()
                                .fill(Palette.hairline)
                                .frame(width: 1, height: 18)
                                .padding(.horizontal, 5)
                        }
                        ForEach(row.others) { tab in chip(tab, in: row) }
                    }
                    .frame(height: Metrics.bar)
                    // A pinned tab on screen opening up to say where it is, or closing.
                    .animation(.bar, value: row.openPinned)
                }
            }
            .scrollIndicators(.hidden)
            .onChange(of: window.tabID) { _, tab in
                if let tab { withAnimation(.bar) { scroller.scrollTo(tab, anchor: .center) } }
            }
        }
    }

    @ViewBuilder
    private func chip(_ tab: TabRecord, in row: TabRow) -> some View {
        let selected = tab.id == window.tabID
        if compact && selected {
            CurrentTab(window: window, tab: tab, width: row.width(of: tab), otherSpaces: otherSpaces, act: act)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(stripSpace)) } action: { origins[tab.id] = $0 }
                .id(tab.id)
        } else if tab.isPinned {
            PinnedChip(tab: tab, selected: selected, otherSpaces: otherSpaces, act: act)
                .id(tab.id)
        } else {
            TabChip(tab: tab, selected: selected, width: row.each, otherSpaces: otherSpaces, act: act)
                .id(tab.id)
        }
    }

    /// The field as the address starts to be typed: drawn exactly over the
    /// tab, the same glass in the same place, so nothing seems to change
    /// until it moves. A turn later, once it is there, the tab's words give
    /// way to the address, quickly, and the field widens over the row.
    private func open() {
        guard compact else { return }
        if !drawn {
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) {
                wide = false
                typing = false
                drawn = true
            }
        }
        DispatchQueue.main.async {
            guard window.editingAddress else { return }
            withAnimation(.easeOut(duration: 0.12)) { typing = true }
            withAnimation(.bar.delay(0.06)) { wide = true }
        }
    }

    /// Back the way it came: the field narrows to the tab, the tab's words
    /// come back as it arrives, and once it has, the tab itself shows again.
    private func close() {
        guard drawn else { return }
        // Still at the tab, not yet moving: nothing to go back along.
        guard wide else {
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) {
                typing = false
                drawn = false
            }
            return
        }
        withAnimation(.easeInOut(duration: 0.15).delay(0.1)) { typing = false }
        withAnimation(.bar, completionCriteria: .removed) {
            wide = false
        } completion: {
            guard !window.editingAddress, !wide else { return }
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) { drawn = false }
        }
    }

    /// As things are, without moving: a window opened, or the layout changed, mid-typing.
    private func settle() {
        let editing = compact && window.editingAddress
        drawn = editing
        wide = editing
        typing = editing
    }

    /// The tab's place, kept inside the strip for a tab half scrolled out of it.
    private static func start(_ tab: CGRect?, in bounds: CGRect) -> CGRect {
        guard let tab, tab.width > 0 else { return bounds }
        let minX = min(max(tab.minX, bounds.minX), bounds.maxX - Metrics.target)
        let maxX = max(min(tab.maxX, bounds.maxX), minX + Metrics.target)
        return CGRect(x: minX, y: bounds.minY, width: maxX - minX, height: bounds.height)
    }
}

/// The row's tabs, and how wide each is.
private struct TabRow {
    let pinned: [TabRecord]
    let others: [TabRecord]
    let current: TabRecord?
    /// A tab's width; a pinned tab is its icon.
    let each: CGFloat
    /// The pinned tab on screen must say where it is (a sign-in page), so
    /// it opens up to a tab's width. Otherwise it stays an icon, so going to
    /// it moves nothing in the row: you pinned it, you know where it is, and
    /// a click on it shows the address.
    let openPinned: Bool

    /// The narrowest a tab gets: its name still reads.
    private static let narrowest: CGFloat = 120

    init(tabs: [TabRecord], current id: UUID?, compact: Bool, addressRequired: Bool, width: CGFloat) {
        pinned = tabs.filter(\.isPinned)
        others = tabs.filter { !$0.isPinned }
        current = tabs.first { $0.id == id }
        openPinned = compact && addressRequired && current?.isPinned == true
        let icons = pinned.count - (openPinned ? 1 : 0)
        let shares = others.count + (openPinned ? 1 : 0)
        let divided = !pinned.isEmpty && !others.isEmpty
        // The row's 2-point gaps fall between its pieces: the icons, the
        // divider (1 point and 5 either side) and the tabs.
        let pieces = icons + shares + (divided ? 1 : 0)
        let room = width - CGFloat(icons) * Metrics.target - (divided ? 11 : 0) - CGFloat(max(pieces - 1, 0)) * 2
        let even = shares == 0 ? 0 : (room / CGFloat(shares)).rounded(.down)
        // Compact tabs fill the row, as Safari's do; separate ones stop where a name has room.
        each = compact ? max(even, Self.narrowest) : min(max(even, Self.narrowest), 280)
    }

    /// Nil for a pinned tab's icon alone.
    func width(of tab: TabRecord) -> CGFloat? {
        tab.isPinned && !(openPinned && tab.id == current?.id) ? nil : each
    }
}

// MARK: The space

/// The space's own button, filled with its colour, so a window says which
/// space it is in at a glance; its menu goes to the others.
struct SpaceButton: View {
    @ObservedObject var session: Session
    @ObservedObject var window: WindowModel
    let act: (BarAction) -> Void

    var body: some View {
        let space = session.workspace.space(window.spaceID)
        let color = space?.color ?? .blue
        Menu {
            Section {
                ForEach(session.workspace.spaces) { other in
                    Button {
                        act(.switchSpace(other.id))
                    } label: {
                        if other.id == window.spaceID {
                            Label(other.name, systemImage: "checkmark")
                        } else {
                            Label(other.name, systemImage: other.symbol)
                        }
                    }
                }
            }
            Section {
                Button("New Space…", systemImage: "plus") { act(.command(.newSpace)) }
                Button("Space Settings…", systemImage: "slider.horizontal.3") { act(.spaceSettings(window.spaceID)) }
                Button("Open in New Window", systemImage: "macwindow.badge.plus") { act(.spaceInNewWindow(window.spaceID)) }
                if session.workspace.spaces.count > 1 {
                    Button("Remove Space…", systemImage: "trash", role: .destructive) { act(.removeSpace(window.spaceID)) }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: space?.symbol ?? "square.grid.2x2")
                    .font(.system(size: 12, weight: .semibold))
                Text(space?.name ?? "")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .opacity(0.75)
                    // The chevron's weight sits low; up a point, it lines up with the text.
                    .offset(y: 0.5)
            }
            .foregroundStyle(color.ink)
            .padding(.horizontal, 12)
            .frame(height: Metrics.control)
            .liquidGlass(tint: color.color, in: Capsule(), otherwise: color.color)
            .frame(height: Metrics.target)
            .contentShape(Rectangle())
            .animation(.bar, value: color)
        }
        .accessibilityLabel("Space: \(space?.name ?? "")")
    }
}

// MARK: Tabs

/// A pinned tab: the site's icon alone, flat unless it is on screen. It
/// keeps its place and its address; closing it takes it back there.
struct PinnedChip: View {
    let tab: TabRecord
    let selected: Bool
    let otherSpaces: [Space]
    let act: (BarAction) -> Void
    @State private var hovering = false

    var body: some View {
        SiteIconView(url: tab.pinned ?? tab.url, size: 18)
            .frame(width: Metrics.target, height: Metrics.control)
            .modifier(TabSurface(selected: selected, hovering: hovering))
            .frame(height: Metrics.target)
            .contentShape(Rectangle())
            .onTapGesture { act(.select(tab.id)) }
            .onHover { hovering = $0 }
            .help(tab.label)
            .contextMenu {
                Button("Back to Pinned Page", systemImage: "arrow.uturn.backward") { act(.backToPinned(tab.id)) }
                Button("Unpin Tab", systemImage: "pin.slash") { act(.unpin(tab.id)) }
                Button("Close Tab", systemImage: "xmark") { act(.close(tab.id)) }
                Button("Open in New Window", systemImage: "macwindow.badge.plus") { act(.tabInNewWindow(tab.id)) }
                MoveToSpace(tab: tab, otherSpaces: otherSpaces, act: act)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(tab.label), pinned")
            .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}

/// One tab in the row: its icon and its name. On the tab on screen and the
/// one under the pointer, a close button takes the icon's place, as in
/// Safari, so the name never moves.
struct TabChip: View {
    let tab: TabRecord
    let selected: Bool
    var width: CGFloat?
    let otherSpaces: [Space]
    let act: (BarAction) -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                if selected || hovering {
                    CloseTabButton { act(.close(tab.id)) }
                        .iconSwap()
                } else {
                    SiteIconView(url: tab.url, size: 16)
                        .iconSwap()
                }
            }
            .frame(width: TabFace.slot, height: Metrics.control)
            .padding(.leading, TabFace.lead)
            Text(tab.label)
                .font(.system(size: 13, weight: selected ? .medium : .regular))
                .lineLimit(1)
                .foregroundStyle(selected ? Palette.ink : Palette.muted)
                .padding(.leading, TabFace.gap)
            Spacer(minLength: 0)
        }
        .padding(.trailing, 10)
        .frame(width: width, height: Metrics.control)
        .frame(maxWidth: width == nil ? 220 : nil, alignment: .leading)
        .modifier(TabSurface(selected: selected, hovering: hovering))
        .frame(height: Metrics.target)
        .contentShape(Rectangle())
        .onTapGesture { act(.select(tab.id)) }
        .onHover { hovering = $0 }
        .animation(.bar, value: hovering)
        .contextMenu {
            Button("Pin Tab", systemImage: "pin") { act(.pin(tab.id)) }
                .disabled(tab.url == nil)
            Button("Close Tab", systemImage: "xmark") { act(.close(tab.id)) }
            Button("Open in New Window", systemImage: "macwindow.badge.plus") { act(.tabInNewWindow(tab.id)) }
            MoveToSpace(tab: tab, otherSpaces: otherSpaces, act: act)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}

/// Where things sit in a tab and in the address field, so that what the tab
/// says and the address being typed start at the same place, and one fades
/// into the other without moving: a 28-point slot for the icon or the close
/// button, 2 points in, and the words 4 points after it.
enum TabFace {
    static let lead: CGFloat = 2
    static let slot: CGFloat = 28
    static let gap: CGFloat = 4
}

private struct CloseTabButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Palette.muted)
                .frame(width: TabFace.slot, height: Metrics.control)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScale())
        .hoverEffect(.highlight)
        .accessibilityLabel("Close Tab")
    }
}

/// The tab on screen, in the compact layout, in the glass. A click on what
/// it says, or anywhere on it but its buttons, types a new address: the
/// field grows out of it (TabStrip).
private struct CurrentTab: View {
    @ObservedObject var window: WindowModel
    let tab: TabRecord
    let width: CGFloat?
    let otherSpaces: [Space]
    let act: (BarAction) -> Void

    var body: some View {
        CurrentTabFace(window: window, tab: tab, width: width, buttons: CurrentTabFace.roomy(width), act: act)
            .liquidGlass(reacting: false, in: Capsule(), otherwise: Palette.wash)
            .frame(height: Metrics.target)
            .contentShape(Rectangle())
            .onTapGesture { act(.editAddress) }
            .contextMenu {
                if tab.isPinned {
                    Button("Back to Pinned Page", systemImage: "arrow.uturn.backward") { act(.backToPinned(tab.id)) }
                    Button("Unpin Tab", systemImage: "pin.slash") { act(.unpin(tab.id)) }
                } else {
                    Button("Pin Tab", systemImage: "pin") { act(.pin(tab.id)) }
                        .disabled(tab.url == nil)
                }
                Button("Close Tab", systemImage: "xmark") { act(.close(tab.id)) }
                Button("Open in New Window", systemImage: "macwindow.badge.plus") { act(.tabInNewWindow(tab.id)) }
                MoveToSpace(tab: tab, otherSpaces: otherSpaces, act: act)
            }
    }
}

/// What the tab on screen shows in the compact layout: a close button where
/// the other tabs have their icon, as in Safari (a pinned tab, which has no
/// close, keeps its icon); where it is, with the name that matters in bold,
/// or what it is called (Settings › the tab on screen shows; every sign-in
/// page shows where it is: AddressVisibility); and the key badge, the star
/// and reload while there is room for them. Drawn on the tab, and on the
/// field while the field still has the tab's place.
struct CurrentTabFace: View {
    @ObservedObject var window: WindowModel
    let tab: TabRecord
    /// Nil for a pinned tab's icon alone.
    let width: CGFloat?
    /// The key badge, the star and reload: on a tab with room for them.
    let buttons: Bool
    let act: (BarAction) -> Void

    /// Room for the buttons as well as a name that reads.
    static func roomy(_ width: CGFloat?) -> Bool {
        (width ?? 0) >= 200
    }

    var body: some View {
        if let width {
            HStack(spacing: 0) {
                Group {
                    if tab.isPinned {
                        SiteIconView(url: window.url ?? tab.url, size: 16)
                    } else {
                        CloseTabButton { act(.close(tab.id)) }
                    }
                }
                .frame(width: TabFace.slot, height: Metrics.control)
                .padding(.leading, TabFace.lead)
                label
                    .padding(.leading, TabFace.gap)
                Spacer(minLength: 4)
                if buttons && window.url != nil {
                    if window.signIn {
                        SignInBadge()
                    }
                    BookmarkStar(window: window, act: act)
                    ReloadButton(window: window, act: act)
                }
            }
            .padding(.trailing, buttons && window.url != nil ? 2 : 10)
            .frame(width: width, height: Metrics.control)
        } else {
            SiteIconView(url: window.url ?? tab.pinned ?? tab.url, size: 18)
                .frame(width: Metrics.target, height: Metrics.control)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(tab.label), pinned")
                .accessibilityHint("Type a new address or a search")
                .accessibilityAddTraits([.isSelected, .isButton])
                .accessibilityAction { act(.editAddress) }
        }
    }

    private var label: some View {
        HStack(spacing: 5) {
            if window.showsAddress && window.insecure {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.unsafe)
                    .accessibilityLabel("Not secure")
            }
            if window.showsAddress {
                // The end of the host is who you are talking to: it is what stays.
                AddressLine(url: window.url, hostOnly: true)
                    .truncationMode(.head)
            } else {
                Text(tab.label)
                    .fontWeight(.medium)
                    .foregroundStyle(Palette.ink)
            }
        }
        .font(.system(size: 13))
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityHint("Type a new address or a search")
        .accessibilityAddTraits([.isSelected, .isButton])
        .accessibilityAction { act(.editAddress) }
    }

    private var spoken: String {
        let address = window.url.map { "Address, \(Destination.pretty($0))" } ?? "Address"
        return window.insecure ? address + ", not secure" : address
    }
}

private struct MoveToSpace: View {
    let tab: TabRecord
    let otherSpaces: [Space]
    let act: (BarAction) -> Void

    var body: some View {
        if !otherSpaces.isEmpty {
            Menu("Move to Space", systemImage: "arrow.right.square") {
                ForEach(otherSpaces) { space in
                    Button(space.name, systemImage: space.symbol) { act(.moveTab(tab.id, space.id)) }
                }
            }
        }
    }
}

/// The tab on screen in the system's glass; every other tab flat, with a
/// faint fill under the pointer. Before iPadOS 26, a flat fill for both.
private struct TabSurface: ViewModifier {
    let selected: Bool
    let hovering: Bool

    func body(content: Content) -> some View {
        if selected {
            content.liquidGlass(reacting: false, in: Capsule(), otherwise: Palette.wash)
        } else {
            content.background(hovering ? Palette.hover : Color.clear, in: Capsule())
        }
    }
}

// MARK: The address

/// The address as it reads when nobody is typing; a tap types a new one.
private struct AddressSummary: View {
    @ObservedObject var window: WindowModel
    let act: (BarAction) -> Void

    var body: some View {
        HStack(spacing: 0) {
            SecurityIcon(window: window)
                .frame(width: TabFace.slot, height: Metrics.control)
                .padding(.leading, TabFace.lead)
            AddressLine(url: window.url)
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.leading, TabFace.gap)
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { act(.editAddress) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(window.url.map { "Address, \(Destination.pretty($0))" } ?? "Address")
        .accessibilityHint("Type a new address or a search")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { act(.editAddress) }
    }
}

/// The site's icon, or a warning when the page or something on it came
/// over a connection anyone on the way can read.
private struct SecurityIcon: View {
    @ObservedObject var window: WindowModel

    var body: some View {
        if window.insecure {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(Palette.unsafe)
                .frame(width: 16, height: 16)
                .accessibilityLabel("Not secure")
        } else if window.url != nil {
            SiteIconView(url: window.url, size: 16)
        } else {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.muted)
                .frame(width: 16, height: 16)
        }
    }
}

/// "accounts." muted, "google.com" in bold, "/v3/signin" muted: the part of
/// the host that says who you are talking to stands out.
struct AddressLine: View {
    let url: URL?
    /// The host alone, as a tab says where it is.
    var hostOnly = false

    var body: some View {
        text
    }

    private var text: Text {
        guard let url, let host = url.host() else {
            return Text("Address or search").foregroundStyle(Palette.muted)
        }
        let bare = host.lowercased().hasPrefix("www.") ? String(host.dropFirst(4)) : host
        let full = Destination.pretty(url)
        let pretty = hostOnly && full.hasPrefix(bare) ? bare : full
        let name = Destination.registrable(bare)
        guard pretty.hasPrefix(bare), bare.hasSuffix(name) else {
            return Text(pretty).foregroundStyle(Palette.ink)
        }
        let sub = String(bare.dropLast(name.count))
        let rest = String(pretty.dropFirst(bare.count))
        return Text(sub).foregroundStyle(Palette.muted)
            + Text(name).foregroundStyle(Palette.ink).fontWeight(.semibold)
            + Text(rest).foregroundStyle(Palette.muted)
    }
}

private struct SignInBadge: View {
    var body: some View {
        Image(systemName: "key.fill")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Palette.muted)
            .frame(width: 24, height: 22)
            .background(Palette.wash, in: Capsule())
            .help("Sign-in page")
            .accessibilityLabel("Sign-in page")
            .transition(.opacity)
    }
}

/// The star: this page among the space's bookmarks, or not; a tap adds or
/// takes it away.
private struct BookmarkStar: View {
    @ObservedObject var window: WindowModel
    let act: (BarAction) -> Void

    var body: some View {
        Button {
            act(.toggleBookmark)
        } label: {
            ZStack {
                if window.bookmarked {
                    Image(systemName: "star.fill")
                        .foregroundStyle(Palette.ink)
                        .iconSwap()
                } else {
                    Image(systemName: "star")
                        .foregroundStyle(Palette.muted)
                        .iconSwap()
                }
            }
            .font(.system(size: 13, weight: .medium))
            // A star's centre of weight sits below its middle.
            .offset(y: -0.5)
            .frame(width: 30, height: Metrics.control)
            .contentShape(Rectangle())
            .animation(.bar, value: window.bookmarked)
        }
        .buttonStyle(PressScale())
        .hoverEffect(.highlight)
        .accessibilityLabel(window.bookmarked ? "Remove Bookmark" : "Bookmark This Page")
    }
}

private struct ReloadButton: View {
    @ObservedObject var window: WindowModel
    let act: (BarAction) -> Void

    var body: some View {
        Button {
            act(window.loading ? .stop : .reload)
        } label: {
            ZStack {
                if window.loading {
                    Image(systemName: "xmark").iconSwap()
                } else {
                    Image(systemName: "arrow.clockwise").iconSwap()
                }
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Palette.ink)
            .frame(width: 30, height: Metrics.control)
            .contentShape(Rectangle())
            .animation(.bar, value: window.loading)
        }
        .buttonStyle(PressScale())
        .hoverEffect(.highlight)
        .accessibilityLabel(window.loading ? "Stop" : "Reload")
    }
}

/// The address being typed. It opens with the address selected, so typing
/// replaces it, as Safari's does; Return goes, Escape or a click on the page
/// leaves it as it was. Its icon and its words sit where a tab's do
/// (TabFace), so the tab's words fade into the address in place. It has no
/// glass of its own: it is drawn on the field's, or the address bar's.
struct AddressEditor: View {
    @ObservedObject var window: WindowModel
    let act: (BarAction) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 0) {
            SecurityIcon(window: window)
                .frame(width: TabFace.slot, height: Metrics.control)
                .padding(.leading, TabFace.lead)
            TextField("Address or search", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .keyboardType(.webSearch)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .focused($focused)
                .onSubmit { act(.go(text)) }
                .padding(.leading, TabFace.gap)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.faint)
                        .frame(width: 30, height: Metrics.control)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressScale())
                .hoverEffect(.highlight)
                .accessibilityLabel("Clear")
                .iconSwap()
            }
        }
        .padding(.trailing, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.bar, value: text.isEmpty)
        // Drawn before it is typed in, in the compact layout, so it starts
        // when typing does as well as when it appears.
        .onAppear { if window.editingAddress { begin() } }
        .onChange(of: window.editingAddress) { _, now in if now { begin() } }
        .onChange(of: focused) { _, now in
            if !now && window.editingAddress { act(.cancelAddress) }
        }
    }

    /// The tab's address, all of it selected, with the keys.
    private func begin() {
        text = window.url.map(Destination.editable) ?? ""
        focused = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            UIApplication.shared.sendAction(#selector(UIResponder.selectAll(_:)), to: nil, from: nil, for: nil)
        }
    }
}

/// The compact layout's address field, over the row: the tab on screen's
/// glass, carried out over the other tabs while an address is typed.
private struct AddressField: View {
    @ObservedObject var window: WindowModel
    /// The address shows; until then, the tab's own words do (TabStrip).
    let typing: Bool
    let act: (BarAction) -> Void

    var body: some View {
        // Made again for each tab, so it starts from that tab's address.
        AddressEditor(window: window, act: act)
            .id(window.tabID)
            // Not quite 0 before it shows: SwiftUI takes a view at 0 for gone,
            // and the field must take the keys from the start.
            .opacity(typing ? 1 : 0.01)
            .liquidGlass(reacting: false, in: Capsule(), otherwise: Palette.wash)
            // All of it answers, so a click on its empty parts never reaches the tabs under it.
            .contentShape(Capsule())
    }
}

/// Back and forward, in one piece of glass, as Safari has them.
struct HistoryButtons: View {
    @ObservedObject var window: WindowModel
    let act: (BarAction) -> Void

    var body: some View {
        HStack(spacing: 0) {
            button("chevron.left", "Back", enabled: window.canGoBack) { act(.back) }
            button("chevron.right", "Forward", enabled: window.canGoForward) { act(.forward) }
        }
        .background {
            Color.clear
                .liquidGlass(reacting: false, in: Capsule(), otherwise: .clear)
                .frame(height: Metrics.control)
        }
        .padding(.trailing, 4)
    }

    private func button(_ symbol: String, _ label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(enabled ? Palette.ink : Palette.faint)
                // A chevron's point sits off its box; nudged toward the way it points.
                .offset(x: symbol == "chevron.left" ? -0.5 : 0.5)
                .frame(width: Metrics.target, height: Metrics.target)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScale())
        .disabled(!enabled)
        .hoverEffect(.highlight)
        .accessibilityLabel(label)
    }
}

/// A round glass button on a bar: 32 points drawn, 40 that answer.
struct BarButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Palette.ink)
                .frame(width: Metrics.control, height: Metrics.control)
                .liquidGlass(in: Circle(), otherwise: .clear)
                .frame(width: Metrics.target, height: Metrics.target)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScale())
        .hoverEffect(.highlight)
        .accessibilityLabel(label)
    }
}

/// A hairline at the bottom of a bar that fills while the page loads.
struct LoadingLine: View {
    @ObservedObject var window: WindowModel

    var body: some View {
        GeometryReader { box in
            Rectangle()
                .fill(Palette.faint)
                .frame(width: window.loading ? box.size.width * max(0.08, window.progress) : 0, height: 2)
                .animation(.easeOut(duration: 0.2), value: window.progress)
        }
        .frame(height: 2)
        .opacity(window.loading ? 1 : 0)
    }
}

/// The address bar of the separate layout: back, forward and reload, and
/// the address, under the row of tabs. Shown on sign-in pages whatever
/// Settings says, so the host asking for a password is never hidden
/// (AddressVisibility).
struct AddressBar: View {
    @ObservedObject var window: WindowModel
    let act: (BarAction) -> Void

    var body: some View {
        HStack(spacing: 4) {
            HistoryButtons(window: window, act: act)
            // One piece of glass: the address and the address being typed
            // fade into each other on it, in place.
            ZStack {
                if window.editingAddress {
                    AddressEditor(window: window, act: act)
                        .id(window.tabID)
                        .transition(.opacity)
                } else {
                    HStack(spacing: 2) {
                        AddressSummary(window: window, act: act)
                        if window.signIn { SignInBadge() }
                        if window.url != nil { BookmarkStar(window: window, act: act) }
                        ReloadButton(window: window, act: act)
                    }
                    .padding(.trailing, 2)
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: Metrics.control)
            .liquidGlass(reacting: false, in: Capsule(), otherwise: Palette.wash)
            .frame(height: Metrics.target)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.bar, value: window.editingAddress)
        .ignoresSafeArea(.keyboard)
    }
}

/// A line under the address bar: Google refusing to sign in, a page that
/// ran out of memory again and again, a page that didn't load.
struct BannerBar: View {
    @ObservedObject var window: WindowModel
    let act: (BarAction) -> Void

    var body: some View {
        if let banner = window.banner {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: banner == .googleRefused ? "person.badge.key" : "exclamationmark.triangle")
                    .foregroundStyle(Palette.unsafe)
                Text(message(banner))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                switch banner {
                case .googleRefused:
                    Button("Go Back") { act(.back) }
                case .exhausted, .failed:
                    Button("Reload") { act(.reload) }
                }
                Button {
                    act(.dismissBanner)
                } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.muted)
                .accessibilityLabel("Dismiss")
            }
            .font(.system(size: 13))
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.wash)
        }
    }

    private func message(_ banner: Banner) -> String {
        switch banner {
        case .googleRefused:
            return SignIn.fallback
        case .exhausted:
            return "This page stopped because it ran out of memory, more than once. Close a heavy tab, then reload."
        case .failed(let reason):
            return reason
        }
    }
}

/// A space with no tab in this window.
struct EmptySpace: View {
    @ObservedObject var session: Session
    @ObservedObject var window: WindowModel
    let act: (BarAction) -> Void

    var body: some View {
        let space = session.workspace.space(window.spaceID)
        VStack(spacing: 14) {
            Image(systemName: space?.symbol ?? "square.grid.2x2")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(space?.color.color ?? Palette.faint)
            Text(space.map { "Nothing open in \($0.name)" } ?? "Nothing open")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Palette.muted)
            HStack(spacing: 10) {
                Button("New Tab  \(Shortcuts.chord(for: .newTab)?.label ?? "")") { act(.command(.newTab)) }
                Button("Command Palette  \(Shortcuts.chord(for: .palette)?.label ?? "")") { act(.command(.palette)) }
            }
            .buttonStyle(.bordered)
            .font(.system(size: 13))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
