import PadCore
import SwiftUI

/// Everything a bar, the palette or the empty space can ask a window to do.
enum BarAction {
    case select(UUID)
    case close(UUID)
    case command(Command)
    case switchSpace(UUID)
    case spaceInNewWindow(UUID)
    case renameSpace(UUID)
    case removeSpace(UUID)
    case setSymbol(UUID, String)
    case moveTab(UUID, UUID)
    case tabInNewWindow(UUID)
    case editAddress
    case cancelAddress
    case go(String)
    case open(URL)
    case back
    case forward
    case reload
    case stop
    case dismissBanner
}

/// The row along the top: the space, its tabs, a new tab and the palette.
struct TopBar: View {
    @ObservedObject var session: Session
    @ObservedObject var window: WindowModel
    let act: (BarAction) -> Void

    private var space: Space? {
        session.workspace.space(window.spaceID)
    }

    var body: some View {
        HStack(spacing: 6) {
            spaceMenu
            ScrollViewReader { scroller in
                ScrollView(.horizontal) {
                    HStack(spacing: 2) {
                        ForEach(space?.tabs ?? []) { tab in
                            TabChip(tab: tab, selected: tab.id == window.tabID, otherSpaces: otherSpaces, act: act)
                                .id(tab.id)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .onChange(of: window.tabID) { _, tab in
                    if let tab { withAnimation { scroller.scrollTo(tab) } }
                }
            }
            Spacer(minLength: 0)
            barButton("plus", "New Tab") { act(.command(.newTab)) }
            barButton("command", "Command Palette") { act(.command(.palette)) }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.ground)
        .overlay(alignment: .bottom) { LoadingLine(window: window) }
        .ignoresSafeArea(.keyboard)
    }

    private var otherSpaces: [Space] {
        session.workspace.spaces.filter { $0.id != window.spaceID }
    }

    private var spaceMenu: some View {
        Menu {
            Section {
                ForEach(session.workspace.spaces) { other in
                    Button {
                        act(.switchSpace(other.id))
                    } label: {
                        Label(other.name, systemImage: other.symbol)
                    }
                }
            }
            Section {
                Button("New Space…") { act(.command(.newSpace)) }
                Button("Open in New Window") { act(.spaceInNewWindow(window.spaceID)) }
                Button("Rename…") { act(.renameSpace(window.spaceID)) }
                Menu("Icon") {
                    ForEach(Workspace.symbols, id: \.self) { symbol in
                        Button {
                            act(.setSymbol(window.spaceID, symbol))
                        } label: {
                            Label(symbol, systemImage: symbol)
                        }
                    }
                }
                if session.workspace.spaces.count > 1 {
                    Button("Remove Space…", role: .destructive) { act(.removeSpace(window.spaceID)) }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: space?.symbol ?? "square.grid.2x2")
                Text(space?.name ?? "")
                    .fontWeight(.medium)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Palette.muted)
            }
            .font(.system(size: 13))
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(Palette.wash, in: RoundedRectangle(cornerRadius: Metrics.corner))
        }
    }

    private func barButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .foregroundStyle(Palette.muted)
                .frame(width: 30, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityLabel(label)
    }
}

/// One tab in the row: its name, and a close button on the one you are on
/// or the one under the pointer.
struct TabChip: View {
    let tab: TabRecord
    let selected: Bool
    let otherSpaces: [Space]
    let act: (BarAction) -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 4) {
            Text(tab.label)
                .font(.system(size: 13))
                .lineLimit(1)
                .frame(maxWidth: 180, alignment: .leading)
                .foregroundStyle(selected ? Palette.ink : Palette.muted)
            if selected || hovering {
                Button {
                    act(.close(tab.id))
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Palette.muted)
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close Tab")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(selected ? Palette.wash : (hovering ? Palette.hover : Color.clear),
                    in: RoundedRectangle(cornerRadius: Metrics.corner))
        .contentShape(RoundedRectangle(cornerRadius: Metrics.corner))
        .onTapGesture { act(.select(tab.id)) }
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Close Tab") { act(.close(tab.id)) }
            Button("Open in New Window") { act(.tabInNewWindow(tab.id)) }
            if !otherSpaces.isEmpty {
                Menu("Move to Space") {
                    ForEach(otherSpaces) { space in
                        Button(space.name) { act(.moveTab(tab.id, space.id)) }
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
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

/// The address: who you are talking to, in full, with the name that matters
/// in bold. Shown on sign-in pages whatever Settings says, so the host asking
/// for a password is never hidden (AddressVisibility).
struct AddressBar: View {
    @ObservedObject var window: WindowModel
    let act: (BarAction) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 4) {
            navigation("chevron.left", "Back", enabled: window.canGoBack) { act(.back) }
            navigation("chevron.right", "Forward", enabled: window.canGoForward) { act(.forward) }
            navigation(window.loading ? "xmark" : "arrow.clockwise", window.loading ? "Stop" : "Reload", enabled: true) {
                act(window.loading ? .stop : .reload)
            }
            field
            if window.signIn && !window.editingAddress {
                Label("Sign-in page", systemImage: "key")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.muted)
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(Palette.wash, in: Capsule())
                    .fixedSize()
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.ground)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.hairline).frame(height: 1)
        }
        .ignoresSafeArea(.keyboard)
        .onChange(of: focused) { _, now in
            if !now && window.editingAddress { act(.cancelAddress) }
        }
    }

    @ViewBuilder
    private var field: some View {
        if window.editingAddress {
            TextField("Address or search", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .keyboardType(.webSearch)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .focused($focused)
                .onSubmit { act(.go(text)) }
                // The field exists only while editing, so it takes the
                // address and the focus as it appears.
                .onAppear {
                    text = window.url.map(Destination.editable) ?? ""
                    focused = true
                }
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(Palette.wash, in: RoundedRectangle(cornerRadius: Metrics.corner))
        } else {
            Button {
                act(.editAddress)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: window.secure ? "lock.fill" : "exclamationmark.triangle")
                        .font(.system(size: 11))
                        .foregroundStyle(window.secure ? Palette.safe : Palette.unsafe)
                        .opacity(window.url == nil ? 0 : 1)
                    address
                        .font(.system(size: 13))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(Palette.wash, in: RoundedRectangle(cornerRadius: Metrics.corner))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// "accounts." muted, "google.com" in bold, "/v3/signin" muted: the
    /// part of the host that says who you are talking to stands out.
    private var address: Text {
        guard let url = window.url, let host = url.host() else {
            return Text("Address or search").foregroundStyle(Palette.muted)
        }
        let pretty = Destination.pretty(url)
        let bare = host.lowercased().hasPrefix("www.") ? String(host.dropFirst(4)) : host
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

    private func navigation(_ symbol: String, _ label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(enabled ? Palette.ink : Palette.faint)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .hoverEffect(.highlight)
        .accessibilityLabel(label)
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
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.muted)
                .accessibilityLabel("Dismiss")
            }
            .font(.system(size: 13))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
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
                .foregroundStyle(Palette.faint)
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
