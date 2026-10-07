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
    /// A folder, named, inside another (nil: at the top level).
    case newFolder(String, in: UUID?)
    case renameBookmark(UUID, String)
    /// Into a folder, or nil for the top level.
    case moveBookmark(UUID, into: UUID?)
    case importBookmarks
    case dismissBanner
    /// A tab beside the one on screen; a new one; apart again; sides swapped.
    case splitWith(UUID)
    case splitWithNewTab
    case separate(UUID)
    case swapSides(UUID)
    /// The space's tabs as a grid, from the phone bar.
    case showTabs
    /// The iPhone's desktop view, in or out (DesktopPad).
    case desktopView
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

    /// The tab on screen can have another beside it: an ordinary tab.
    private var canSplit: Bool {
        window.tabID.flatMap { session.workspace.tab($0) }.map { !$0.isPinned } ?? false
    }

    var body: some View {
        HStack(spacing: 2) {
            SpaceButton(session: session, window: window, act: act)
                .padding(.trailing, 4)
            if compact {
                HistoryButtons(window: window, act: act)
            }
            TabStripHost(session: session, model: window, compact: compact, act: act)
            BarButton(symbol: "plus", label: "New Tab") { act(.command(.newTab)) }
                .contextMenu {
                    if canSplit {
                        Button("New Tab in Split View", systemImage: "rectangle.split.2x1") { act(.splitWithNewTab) }
                    }
                }
            BarButton(symbol: "command", label: "Command Palette") { act(.command(.palette)) }
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) { LoadingLine(window: window) }
        .ignoresSafeArea(.keyboard)
    }
}

// MARK: The space

/// The space's own button, filled with its colour, so a window says which
/// space it is in at a glance; its menu goes to the others.
struct SpaceButton: View {
    @ObservedObject var session: Session
    @ObservedObject var window: WindowModel
    let act: (BarAction) -> Void
    @Environment(\.barScale) private var scale

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
            // On the phone bar, among icons for a thumb: a little larger, and
            // a long name gives way before the icons do.
            let thumb = scale == .thumb
            HStack(spacing: thumb ? 6 : 5) {
                Image(systemName: space?.symbol ?? "square.grid.2x2")
                    .font(.system(size: thumb ? 14 : 12, weight: .semibold))
                let name = Text(space?.name ?? "")
                    .font(.system(size: thumb ? 15 : 13, weight: .semibold))
                    .lineLimit(1)
                if thumb { name.frame(maxWidth: 100) } else { name }
                Image(systemName: "chevron.down")
                    .font(.system(size: thumb ? 9 : 8, weight: .bold))
                    .opacity(0.75)
                    // The chevron's weight sits low; up a point, it lines up with the text.
                    .offset(y: 0.5)
            }
            .foregroundStyle(color.ink)
            .padding(.horizontal, thumb ? 14 : 12)
            .frame(height: thumb ? 36 : Metrics.control)
            .liquidGlass(tint: color.color, in: Capsule(), otherwise: color.color)
            .frame(height: thumb ? 44 : Metrics.target)
            .contentShape(Rectangle())
            .contentShape(.hoverEffect, Capsule().inset(by: Metrics.ring))
            .animation(.bar, value: color)
        }
        .accessibilityLabel("Space: \(space?.name ?? "")")
    }
}

// MARK: Tabs

/// Where things sit in a tab and in the address field, so that what the tab
/// says and the address being typed start at the same place, and one fades
/// into the other without moving: a 28-point slot for the icon or the close
/// button, 2 points in, and the words 4 points after it.
enum TabFace {
    static let lead: CGFloat = 2
    static let slot: CGFloat = 28
    static let gap: CGFloat = 4
}

/// The page's own commands on the menu of the tab on screen, as the phone's
/// page menu (…) has them: sharing the page and bookmarking it.
struct PageItems: View {
    @ObservedObject var window: WindowModel
    let act: (BarAction) -> Void

    var body: some View {
        if window.url != nil {
            Button("Share Page…", systemImage: "square.and.arrow.up") { act(.command(.share)) }
            Button(window.bookmarked ? "Remove Bookmark" : "Bookmark This Page",
                   systemImage: window.bookmarked ? "star.slash" : "star") { act(.toggleBookmark) }
        }
    }
}

/// The way to everything else, at the end of the tab on screen's menu, as
/// at the end of the phone's page menu.
struct AppItems: View {
    let act: (BarAction) -> Void

    var body: some View {
        Button("Command Palette", systemImage: "command") { act(.command(.palette)) }
        Button("Settings", systemImage: "gearshape") { act(.command(.settings)) }
    }
}

// MARK: The address

/// The address as it reads when nobody is typing; a tap types a new one.
private struct AddressSummary: View {
    @ObservedObject var window: WindowModel
    /// What the page is called rather than where it is, as Settings › The
    /// tab you are on shows has it; never on a sign-in page (showsAddress).
    var titled = false
    let act: (BarAction) -> Void
    @Environment(\.barScale) private var scale

    var body: some View {
        HStack(spacing: 0) {
            // A page's title carries no warning, as the iPad's tab doesn't:
            // the address does, and every sign-in page shows its address.
            SecurityIcon(window: window, warns: !(titled && !window.title.isEmpty))
                .frame(width: TabFace.slot, height: scale.control)
                .padding(.leading, scale.lead)
            Group {
                if titled, window.url != nil, !window.title.isEmpty {
                    Text(window.title)
                        .fontWeight(.medium)
                        .foregroundStyle(Palette.ink)
                } else {
                    AddressLine(url: window.url)
                }
            }
            .font(.system(size: scale.text))
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
    var warns = true
    @Environment(\.barScale) private var scale

    var body: some View {
        if warns && window.insecure {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: scale.icon * 0.75))
                .foregroundStyle(Palette.unsafe)
                .frame(width: scale.icon, height: scale.icon)
                .accessibilityLabel("Not secure")
        } else if window.url != nil {
            SiteIconView(url: window.url, size: scale.icon)
        } else {
            Image(systemName: "magnifyingglass")
                .font(.system(size: scale.icon * 0.75, weight: .medium))
                .foregroundStyle(Palette.muted)
                .frame(width: scale.icon, height: scale.icon)
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
    @Environment(\.barScale) private var scale

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
            .font(.system(size: scale.text, weight: .medium))
            // A star's centre of weight sits below its middle.
            .offset(y: -0.5)
            .frame(width: scale.button, height: scale.control)
            .contentShape(Rectangle())
            .contentShape(.hoverEffect, RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous).inset(by: 3))
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
    @Environment(\.barScale) private var scale

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
            .font(.system(size: scale.text - 1, weight: .semibold))
            .foregroundStyle(Palette.ink)
            .frame(width: scale.button, height: scale.control)
            .contentShape(Rectangle())
            .contentShape(.hoverEffect, RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous).inset(by: 3))
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
    @State private var focused = false
    @Environment(\.barScale) private var scale

    var body: some View {
        HStack(spacing: 0) {
            SecurityIcon(window: window)
                .frame(width: TabFace.slot, height: scale.control)
                .padding(.leading, scale.lead)
            TypingField(text: $text, placeholder: "Address or search", fontSize: scale.text, focused: $focused,
                        selectsAll: true) { typed in act(.go(typed)) }
                .padding(.leading, TabFace.gap)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: scale.text + 1))
                        .foregroundStyle(Palette.faint)
                        .frame(width: scale.button, height: scale.control)
                        .contentShape(Rectangle())
                        .contentShape(.hoverEffect, RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous).inset(by: 3))
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

    /// The tab's address, all of it selected (TypingField.selectsAll), with the keys.
    private func begin() {
        text = window.url.map(Destination.editable) ?? ""
        focused = true
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
                .contentShape(.hoverEffect, Circle().inset(by: Metrics.ring))
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
                // The pointer's highlight takes the circle's shape, not the box's.
                .contentShape(.hoverEffect, Circle().inset(by: Metrics.ring))
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
    @ObservedObject var session: Session
    @ObservedObject var window: WindowModel
    let act: (BarAction) -> Void

    var body: some View {
        HStack(spacing: 4) {
            HistoryButtons(window: window, act: act)
            // Only in its own layout: hidden in the others, an editor here
            // would take the keys from the field that shows and close it.
            AddressCapsule(window: window, editable: session.preferences.layout == .separate && !window.phone, act: act)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.bar, value: window.editingAddress)
        .ignoresSafeArea(.keyboard)
    }
}

/// The address in one piece of glass: where the page is, its key badge on a
/// sign-in page, the star and reload; a tap types a new address, and the
/// address and the address being typed fade into each other on it, in place.
/// The separate layout's address bar, and the phone bar's.
struct AddressCapsule: View {
    @ObservedObject var window: WindowModel
    /// This capsule is the one typed in; otherwise another field is.
    let editable: Bool
    let act: (BarAction) -> Void
    @Environment(\.barScale) private var scale

    var body: some View {
        ZStack {
            if window.editingAddress && editable {
                AddressEditor(window: window, act: act)
                    .id(window.tabID)
                    .transition(.opacity)
            } else {
                HStack(spacing: 2) {
                    // On a phone, the bar's address follows the setting the iPad's tab does.
                    AddressSummary(window: window, titled: window.phone && !window.showsAddress, act: act)
                    if window.signIn { SignInBadge() }
                    if window.url != nil { BookmarkStar(window: window, act: act) }
                    ReloadButton(window: window, act: act)
                }
                .padding(.trailing, 2)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: scale.control)
        .liquidGlass(reacting: false, in: Capsule(), otherwise: Palette.wash)
        .frame(height: scale.target)
        .animation(.bar, value: window.editingAddress)
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
