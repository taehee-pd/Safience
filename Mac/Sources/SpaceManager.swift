import AppKit
import PadCore
import SwiftUI

/// What the Space Settings popover shows: every space, or one space's own settings.
enum SpacesPanel: Equatable {
    case list
    case edit(UUID)
}

/// Space Settings, from the sidebar's foot: the spaces in the order ⌃1 to
/// ⌃9 go to them, to drag into another order; a new one; and each one's
/// name, colour and icon, and its removal, one click in.
struct SpaceManager: View {
    @ObservedObject var model: WindowModel
    @ObservedObject private var session = Session.shared

    var body: some View {
        Group {
            switch model.spacesPanel {
            case .edit(let id) where session.workspace.space(id) != nil:
                editor(id)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            default:
                list
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .frame(width: 320)
        .animation(.bar, value: model.spacesPanel)
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Spaces")
                    .font(.headline)
                Spacer()
                PlainIcon("plus", help: "New Space") { model.newSpace() }
            }
            .padding(.leading, 16)
            .padding(.trailing, 10)
            .padding(.vertical, 10)
            List {
                ForEach(session.workspace.spaces) { space in
                    SpaceRow(space: space, current: space.id == model.spaceID) {
                        model.spacesPanel = .edit(space.id)
                    }
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 1, leading: 6, bottom: 1, trailing: 6))
                }
                .onMove { offsets, destination in
                    session.change { $0.moveSpaces(from: offsets, to: destination) }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .frame(height: min(CGFloat(session.workspace.spaces.count) * 38 + 8, 300))
            Text("⌃1 to ⌃9 go to the spaces in this order.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 14)
        }
    }

    private func editor(_ id: UUID) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 2) {
                Button {
                    model.spacesPanel = .list
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Spaces")
                    }
                    .padding(.horizontal, 8)
                    .frame(height: Metrics.control)
                }
                .buttonStyle(RowButtonStyle())
                .fixedSize()
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
            SpaceEditor(spaceID: id) { model.spacesPanel = .list }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            if session.workspace.spaces.count > 1 {
                Divider()
                    .padding(.top, 16)
                Button(role: .destructive) {
                    confirmRemoval(id)
                } label: {
                    Label("Remove Space…", systemImage: "trash")
                        .foregroundStyle(.red)
                        .padding(.horizontal, 10)
                        .frame(height: Metrics.control)
                }
                .buttonStyle(RowButtonStyle())
                .padding(6)
            } else {
                Spacer().frame(height: 16)
            }
        }
    }

    private func confirmRemoval(_ id: UUID) {
        guard let space = session.workspace.space(id), let window = model.window else { return }
        NSAlert.removal(of: space).beginSheetModal(for: window) { answer in
            guard answer == .alertFirstButtonReturn else { return }
            Session.shared.removeSpace(id)
            model.spacesPanel = .list
        }
    }
}

extension NSAlert {
    /// Asks before a space is removed, saying what goes with it. Its first
    /// button, Remove Space, is the destructive answer.
    static func removal(of space: Space) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = "Remove \(space.name)?"
        alert.informativeText = Sync.shared.spaceRemovalDescription(space)
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Remove Space")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        return alert
    }
}

/// A space in the list: a handle to drag it by, its icon on its colour,
/// its name, how many tabs it has, and the way in to its settings. A click
/// anywhere but the handle opens them; the handle, or the row, drags.
private struct SpaceRow: View {
    let space: Space
    let current: Bool
    let open: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            DragHandle()
            Image(systemName: space.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(space.color.ink)
                .frame(width: 24, height: 24)
                .background(space.color.color, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            Text(space.name)
                .fontWeight(current ? .semibold : .regular)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text("\(space.tabs.count)")
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.leading, 4)
        .padding(.trailing, 10)
        .frame(height: 36)
        .background(Highlight(hovering: hovering, shape: RoundedRectangle(cornerRadius: 8, style: .continuous)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: open)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(space.name), \(space.tabs.count) tabs")
        .accessibilityHint("Opens its settings. Drag to change the order.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Open Settings", open)
    }
}

/// The grip a row is dragged by, as the system draws one.
struct DragHandle: View {
    var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.tertiary)
            .frame(width: 18, height: 24)
            .contentShape(Rectangle())
            .pointerStyle(.grabIdle)
            .accessibilityHidden(true)
    }
}

/// A space's own settings: its name, its colour and its icon, each applied
/// as it is chosen. In Space Settings and in Settings › Spaces.
struct SpaceEditor: View {
    let spaceID: UUID
    let done: () -> Void
    @ObservedObject private var session = Session.shared
    @State private var name = ""

    var body: some View {
        let space = session.workspace.space(spaceID)
        VStack(alignment: .leading, spacing: 14) {
            if let space {
                HStack(spacing: 10) {
                    Image(systemName: space.symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(space.color.ink)
                        .frame(width: 34, height: 34)
                        .background(space.color.color, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    TextField("Name", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 14))
                        .onSubmit(done)
                }
                Text("Colour").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                SpaceColours(space: space)
                Text("Icon").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                SpaceSymbols(space: space)
            }
        }
        .onAppear { name = space?.name ?? "" }
        .onChange(of: name) { _, now in session.change { $0.renameSpace(spaceID, to: now) } }
    }
}

/// A space's colours to choose from, each applied as it is chosen; the
/// space's own ringed. In Space Settings and in Settings › Spaces.
struct SpaceColours: View {
    let space: Space

    var body: some View {
        HStack(spacing: 4) {
            ForEach(SpaceColor.allCases, id: \.self) { colour in
                Button {
                    Session.shared.change { $0.setColor(space.id, to: colour) }
                } label: {
                    Circle()
                        .fill(colour.color)
                        .frame(width: 18, height: 18)
                        .padding(3)
                        .overlay(Circle().strokeBorder(colour.color, lineWidth: 2).opacity(colour == space.color ? 1 : 0))
                        .contentShape(Circle())
                }
                .buttonStyle(TilePress())
                .help(colour.name)
                .accessibilityLabel(colour.name)
                .accessibilityAddTraits(colour == space.color ? .isSelected : [])
            }
        }
    }
}

/// The icons a space can wear, eight to a row, each applied as it is chosen.
struct SpaceSymbols: View {
    let space: Space

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 5), count: 8), spacing: 5) {
            ForEach(Workspace.symbols, id: \.self) { symbol in
                SymbolChoice(symbol: symbol, chosen: symbol == space.symbol, colour: space.color) {
                    Session.shared.change { $0.setSymbol(space.id, to: symbol) }
                }
            }
        }
        .fixedSize()
    }
}

/// One icon a space can wear: filled with the space's colour when chosen,
/// highlighted under the pointer otherwise.
private struct SymbolChoice: View {
    let symbol: String
    let chosen: Bool
    let colour: SpaceColor
    let choose: () -> Void
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        Button(action: choose) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: chosen ? .semibold : .regular))
                .foregroundStyle(chosen ? colour.ink : Color.primary)
                .frame(width: 30, height: 30)
                .background {
                    if chosen {
                        shape.fill(colour.color)
                    } else {
                        shape.fill(Palette.wash).overlay(Highlight(hovering: hovering, shape: shape))
                    }
                }
                .contentShape(shape)
        }
        .buttonStyle(TilePress())
        .onHover { hovering = $0 }
        .accessibilityLabel(symbol.replacingOccurrences(of: ".", with: " "))
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}
