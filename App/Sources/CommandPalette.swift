import PadCore
import SwiftUI
import UIKit

/// The command palette (⌃⌥K): every tab of every space, every space, every
/// command, and whatever is typed as an address or a search. The quickest
/// way around, and the only one with the tab bar hidden.
@MainActor
final class PaletteModel: ObservableObject {
    @Published var query = "" {
        didSet { selection = 0 }
    }
    @Published var selection = 0
    private let window: WindowModel
    let choose: (PaletteEntry?) -> Void
    let cancel: () -> Void

    init(window: WindowModel, choose: @escaping (PaletteEntry?) -> Void, cancel: @escaping () -> Void) {
        self.window = window
        self.choose = choose
        self.cancel = cancel
    }

    /// What the rows show for the query: a typed address or search first,
    /// then the best matches.
    var results: [PaletteEntry] {
        let session = Session.shared
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var typed: [PaletteEntry] = []
        if !trimmed.isEmpty, let url = Destination.url(for: trimmed, engine: session.preferences.engine) {
            let isSearch = url == Destination.search(trimmed, engine: session.preferences.engine)
            typed.append(PaletteEntry(
                id: "typed",
                kind: isSearch ? .search(url) : .open(url),
                title: isSearch ? "Search for “\(trimmed)”" : "Open \(Destination.pretty(url))",
                detail: isSearch ? (url.host() ?? "") : "Address"
            ))
        }
        return typed + PaletteSearch.rank(entries(session), query: trimmed, limit: 40)
    }

    private func entries(_ session: Session) -> [PaletteEntry] {
        let workspace = session.workspace
        var list: [PaletteEntry] = []
        // This window's space first, the most recently seen tabs first.
        let spaces = workspace.spaces.filter { $0.id == window.spaceID } + workspace.spaces.filter { $0.id != window.spaceID }
        for space in spaces {
            for tab in space.tabs.sorted(by: { $0.shown > $1.shown }) where tab.id != window.tabID {
                let host = tab.url.map(Destination.pretty) ?? ""
                list.append(PaletteEntry(
                    id: "tab-\(tab.id)",
                    kind: .tab(tab.id, space: space.id),
                    title: tab.label,
                    detail: workspace.spaces.count > 1 ? "\(space.name) · \(host)" : host,
                    keywords: [host]
                ))
            }
        }
        // This space's bookmarks, folders and all.
        for bookmark in workspace.space(window.spaceID)?.bookmarks.flatMap(\.links) ?? [] {
            guard let url = bookmark.url else { continue }
            let host = Destination.pretty(url)
            list.append(PaletteEntry(
                id: "bookmark-\(bookmark.id)",
                kind: .open(url),
                title: bookmark.label,
                detail: "Bookmark · \(host)",
                keywords: [host, "bookmark"]
            ))
        }
        for space in workspace.spaces where space.id != window.spaceID {
            list.append(PaletteEntry(
                id: "space-\(space.id)",
                kind: .space(space.id),
                title: space.name,
                detail: "Space · \(space.tabs.count) \(space.tabs.count == 1 ? "tab" : "tabs")",
                keywords: ["space"]
            ))
        }
        for command in Command.allCases where command != .palette {
            list.append(PaletteEntry(
                id: "command-\(command.rawValue)",
                kind: .command(command),
                title: command.title,
                detail: Shortcuts.chord(for: command)?.label ?? "",
                keywords: command.keywords
            ))
        }
        return list
    }

    func move(_ by: Int) {
        let count = results.count
        guard count > 0 else { return }
        selection = (selection + by + count) % count
    }

    func submit() {
        let rows = results
        choose(rows.indices.contains(selection) ? rows[selection] : nil)
    }
}

/// The palette's window: its keys come first, so ↑ and ↓ move through the
/// rows instead of the text cursor, and Escape puts it away.
final class PaletteController: UIHostingController<PaletteView> {
    let model: PaletteModel

    init(window: WindowModel, choose: @escaping (PaletteEntry?) -> Void, cancel: @escaping () -> Void) {
        let model = PaletteModel(window: window, choose: choose, cancel: cancel)
        self.model = model
        super.init(rootView: PaletteView(model: model))
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
        view.backgroundColor = .clear
    }

    @MainActor required dynamic init?(coder: NSCoder) {
        nil
    }

    override var keyCommands: [UIKeyCommand]? {
        let keys: [(String, Selector)] = [
            (UIKeyCommand.inputUpArrow, #selector(up)),
            (UIKeyCommand.inputDownArrow, #selector(down)),
            (UIKeyCommand.inputEscape, #selector(escape)),
        ]
        return keys.map { input, action in
            let command = UIKeyCommand(input: input, modifierFlags: [], action: action)
            command.wantsPriorityOverSystemBehavior = true
            return command
        }
    }

    @objc private func up() { model.move(-1) }
    @objc private func down() { model.move(1) }
    @objc private func escape() { model.cancel() }
}

struct PaletteView: View {
    @ObservedObject var model: PaletteModel
    @State private var focused = false

    var body: some View {
        let rows = model.results
        ZStack(alignment: .top) {
            // A light touch only: the page stays in view behind the
            // palette, as with Raycast, and a tap on it puts the palette away.
            Color.black.opacity(0.06)
                .ignoresSafeArea()
                .onTapGesture { model.cancel() }
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Color.primary.opacity(0.5))
                    TypingField(text: $model.query, placeholder: "Tabs, spaces, commands, or an address", fontSize: 17,
                                focused: $focused) { _ in model.submit() }
                }
                .padding(.horizontal, 16)
                .frame(height: 52)
                Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
                ScrollViewReader { scroller in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(rows.enumerated()), id: \.element.id) { index, entry in
                                PaletteRow(entry: entry, selected: index == model.selection)
                                    .id(entry.id)
                                    .onTapGesture {
                                        model.selection = index
                                        model.submit()
                                    }
                            }
                        }
                        .padding(6)
                    }
                    .frame(maxHeight: 420)
                    .onChange(of: model.selection) { _, index in
                        if rows.indices.contains(index) { scroller.scrollTo(rows[index].id) }
                    }
                }
            }
            .frame(maxWidth: 620)
            // See-through and blurred, like Raycast: the system's material,
            // which turns solid by itself under Reduce Transparency. What is
            // drawn on it is the label colour at an opacity, not the
            // system's vibrant .secondary: inside the scrolling list that
            // drew nothing at all (iPadOS 27).
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.22), radius: 40, y: 16)
            .padding(.top, 80)
            .padding(.horizontal, 24)
        }
        .onAppear { focused = true }
    }
}

struct PaletteRow: View {
    let entry: PaletteEntry
    let selected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .frame(width: 20)
                .foregroundStyle(Color.primary.opacity(0.5))
            Text(entry.title)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer(minLength: 12)
            Text(entry.detail)
                .foregroundStyle(Color.primary.opacity(0.5))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.system(size: 14))
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(selected ? Color.primary.opacity(0.1) : Color.clear,
                    in: RoundedRectangle(cornerRadius: Metrics.corner))
        .contentShape(Rectangle())
    }

    private var symbol: String {
        switch entry.kind {
        case .tab: return "rectangle.on.rectangle"
        case .space: return "square.stack"
        case .command: return "command"
        case .open: return "arrow.up.right.square"
        case .search: return "magnifyingglass"
        }
    }
}
