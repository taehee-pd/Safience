import PadCore
import SwiftUI

/// A space's own settings: its name, its colour and its icon, each applied
/// as it is chosen. From the space's menu (Space Settings…, ⌃⌥⇧S) as a
/// sheet, and from Settings › Spaces.
struct SpaceEditor: View {
    @ObservedObject var session: Session
    let spaceID: UUID
    /// Given when shown as a sheet of its own.
    var done: (() -> Void)?
    @State private var name = ""
    @State private var confirming = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let space = session.workspace.space(spaceID)
        Form {
            if let space {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: space.symbol)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(space.color.ink)
                            .frame(width: 40, height: 40)
                            .background(space.color.color, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .animation(.bar, value: space.color)
                        TextField("Name", text: $name)
                            .font(.system(size: 17, weight: .medium))
                            .submitLabel(.done)
                            .onSubmit(save)
                    }
                    .padding(.vertical, 2)
                }

                Section("Colour") {
                    ColourRow(selected: space.color) { colour in
                        session.change { $0.setColor(spaceID, to: colour) }
                    }
                }

                Section("Icon") {
                    IconGrid(selected: space.symbol, colour: space.color) { symbol in
                        session.change { $0.setSymbol(spaceID, to: symbol) }
                    }
                }

                if session.workspace.spaces.count > 1 {
                    Section {
                        Button("Remove Space…", role: .destructive) { confirming = true }
                    } footer: {
                        Text("Its tabs close, and its sign-ins and its bookmarks are erased.")
                    }
                }
            }
        }
        .navigationTitle(space?.name ?? "Space")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let done {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        save()
                        done()
                    }
                }
            }
        }
        .onAppear { name = space?.name ?? "" }
        .onChange(of: name) { _, _ in save() }
        .confirmationDialog("Remove \(space?.name ?? "this space")?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Remove Space", role: .destructive) {
                Session.shared.removeSpace(spaceID)
                if let done { done() } else { dismiss() }
            }
        } message: {
            Text("Its \(space?.tabs.count ?? 0) tabs close, and its sign-ins and bookmarks are erased from this \(Device.name).")
        }
    }

    private func save() {
        session.change { $0.renameSpace(spaceID, to: name) }
    }
}

/// The colours to choose from, each a dot; the chosen one ringed in its own
/// colour, the ring's gap the same all round.
private struct ColourRow: View {
    let selected: SpaceColor
    let choose: (SpaceColor) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(SpaceColor.allCases, id: \.self) { colour in
                Button {
                    choose(colour)
                } label: {
                    ZStack {
                        Circle()
                            .strokeBorder(colour.color, lineWidth: 2)
                            .frame(width: 36, height: 36)
                            .opacity(colour == selected ? 1 : 0)
                            .scaleEffect(colour == selected ? 1 : 0.8)
                        Circle()
                            .fill(colour.color)
                            .frame(width: 26, height: 26)
                    }
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
                    .animation(.bar, value: selected)
                }
                .buttonStyle(PressScale())
                .accessibilityLabel(colour.name)
                .accessibilityAddTraits(colour == selected ? .isSelected : [])
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Every icon a space can wear, as the icons themselves, in a grid: the
/// chosen one filled with the space's colour.
private struct IconGrid: View {
    let selected: String
    let colour: SpaceColor
    let choose: (String) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44, maximum: 52), spacing: 8)], spacing: 8) {
            ForEach(Workspace.symbols, id: \.self) { symbol in
                let chosen = symbol == selected
                Button {
                    choose(symbol)
                } label: {
                    Image(systemName: symbol)
                        .font(.system(size: 17, weight: chosen ? .semibold : .regular))
                        .foregroundStyle(chosen ? colour.ink : Palette.ink)
                        .frame(width: 44, height: 44)
                        .background(chosen ? colour.color : Palette.wash,
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .contentShape(Rectangle())
                        .animation(.bar, value: chosen)
                }
                .buttonStyle(PressScale())
                .accessibilityLabel(symbol.replacingOccurrences(of: ".", with: " "))
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
        .padding(.vertical, 6)
    }
}

/// Settings › Spaces: every space, in the order ⌃⌥↑ and ⌃⌥↓ step through,
/// to reorder (Edit) and to open.
struct SpaceList: View {
    @ObservedObject var session: Session

    var body: some View {
        List {
            Section {
                ForEach(session.workspace.spaces) { space in
                    NavigationLink {
                        SpaceEditor(session: session, spaceID: space.id)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: space.symbol)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(space.color.ink)
                                .frame(width: 28, height: 28)
                                .background(space.color.color, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            Text(space.name)
                            Spacer()
                            Text("\(space.tabs.count) \(space.tabs.count == 1 ? "tab" : "tabs")")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
                .onMove { offsets, destination in
                    session.change { $0.moveSpaces(from: offsets, to: destination) }
                }
            } footer: {
                Text("Edit, then drag a space by its handle to change the order. Each space has its own tabs, sign-ins and bookmarks.")
            }
        }
        .navigationTitle("Spaces")
        .toolbar { EditButton() }
    }
}
