import PadCore
import SwiftUI
import UIKit

/// What a new tab shows: the space's bookmarks as a grid of tiles, one
/// folder at a time, each space's its own. With none yet, the way to bring
/// them over from Chrome or Safari.
struct StartPage: View {
    @ObservedObject var session: Session
    @ObservedObject var window: WindowModel
    let act: (BarAction) -> Void
    /// The folders opened, outermost first.
    @State private var path: [UUID] = []
    @State private var shown = false
    @State private var askingFolder = false
    @State private var folderName = ""
    /// The bookmark or folder being renamed, and the name typed for it.
    @State private var renaming: Bookmark?
    @State private var newName = ""

    var body: some View {
        let space = session.workspace.space(window.spaceID)
        let folders = opened(in: space?.bookmarks ?? [])
        let items = folders.last?.children ?? space?.bookmarks ?? []
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header(space: space, folders: folders)
                if items.isEmpty {
                    empty(space: space)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96, maximum: 112), spacing: 12, alignment: .top)],
                              alignment: .leading, spacing: 18) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            BookmarkTile(item: item, targets: targets(for: item, in: space?.bookmarks ?? []), act: act, open: {
                                if item.isFolder {
                                    withAnimation(.bar) { path.append(item.id) }
                                } else if let url = item.url {
                                    act(.open(url))
                                }
                            }, rename: {
                                newName = item.title
                                renaming = item
                            })
                            // In, one after another: the eye reads them in order.
                            .opacity(shown ? 1 : 0)
                            .offset(y: shown ? 0 : 8)
                            .animation(.bar.delay(min(Double(index) * 0.02, 0.3)), value: shown)
                        }
                    }
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.top, 44)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(Palette.ground)
        .onAppear { shown = true }
        .onDisappear { shown = false }
        .onChange(of: window.spaceID) { _, _ in path = [] }
        .alert("New Folder", isPresented: $askingFolder) {
            TextField("Name", text: $folderName)
            Button("Create") { act(.newFolder(folderName, in: path.last)) }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } }),
               presenting: renaming) { item in
            TextField("Name", text: $newName)
            Button("Rename") { act(.renameBookmark(item.id, newName)) }
            Button("Cancel", role: .cancel) {}
        }
    }

    /// Where a bookmark or a folder can be moved to: the top level, from
    /// inside a folder, and every folder but the one it is in, itself and
    /// its own, each named by its path.
    private func targets(for item: Bookmark, in bookmarks: [Bookmark]) -> [MoveTarget] {
        var banned: Set<UUID> = [item.id]
        func ban(_ items: [Bookmark]) {
            for inside in items {
                banned.insert(inside.id)
                ban(inside.children ?? [])
            }
        }
        ban(item.children ?? [])
        func folders(in items: [Bookmark], prefix: String) -> [MoveTarget] {
            items.filter(\.isFolder).flatMap { folder -> [MoveTarget] in
                guard !banned.contains(folder.id) else { return [] }
                let label = prefix.isEmpty ? folder.label : "\(prefix) › \(folder.label)"
                let own = folder.id == path.last ? [] : [MoveTarget(folder: folder.id, label: label)]
                return own + folders(in: folder.children ?? [], prefix: label)
            }
        }
        let top = path.last == nil ? [] : [MoveTarget(folder: nil, label: "Bookmarks")]
        return top + folders(in: bookmarks, prefix: "")
    }

    /// The opened folders as they are now; a folder that has gone ends the path.
    private func opened(in bookmarks: [Bookmark]) -> [Bookmark] {
        var level = bookmarks
        var found: [Bookmark] = []
        for id in path {
            guard let folder = level.first(where: { $0.id == id && $0.isFolder }) else { break }
            found.append(folder)
            level = folder.children ?? []
        }
        return found
    }

    @ViewBuilder
    private func header(space: Space?, folders: [Bookmark]) -> some View {
        HStack(spacing: 6) {
            if folders.isEmpty {
                Text("Bookmarks")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                if let space {
                    Text(space.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(space.color.ink)
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background(space.color.color, in: Capsule())
                }
            } else {
                Button {
                    withAnimation(.bar) { _ = path.popLast() }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .frame(width: Metrics.target, height: Metrics.target)
                        .contentShape(Rectangle())
                        .contentShape(.hoverEffect, Circle().inset(by: Metrics.ring))
                }
                .buttonStyle(PressScale())
                .hoverEffect(.highlight)
                .accessibilityLabel("Back to \(folders.dropLast().last?.label ?? "Bookmarks")")
                Text(folders.map(\.label).joined(separator: " › "))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer(minLength: 0)
            Button {
                folderName = ""
                askingFolder = true
            } label: {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .frame(width: Metrics.target, height: Metrics.target)
                    .contentShape(Rectangle())
                    .contentShape(.hoverEffect, Circle().inset(by: Metrics.ring))
            }
            .buttonStyle(PressScale())
            .hoverEffect(.highlight)
            .help("New Folder")
            .accessibilityLabel("New Folder")
        }
        // The same height in a folder, where the back button is, as at the
        // top, where it isn't: the tiles don't jump when a folder opens.
        .frame(height: Metrics.target)
    }

    private func empty(space: Space?) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "star.square.on.square")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(space?.color.color ?? Palette.faint)
            Text("No bookmarks in \(space?.name ?? "this space") yet")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.ink)
            Text("Bring them over from Chrome or Safari, or star the page you’re on (\(Shortcuts.chord(for: .bookmark)?.label ?? "")).")
                .font(.system(size: 13))
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
            Button("Import Bookmarks…") { act(.importBookmarks) }
                .buttonStyle(.bordered)
                .padding(.top, 6)
        }
    }
}

/// A bookmark or a folder as a tile: the site's icon, or a folder, on a
/// rounded square whose corner follows the icon's by the padding between.
/// A folder a bookmark can be moved to, or the top level for nil.
private struct MoveTarget: Identifiable {
    let folder: UUID?
    let label: String

    var id: String {
        folder?.uuidString ?? "top"
    }
}

private struct BookmarkTile: View {
    let item: Bookmark
    let targets: [MoveTarget]
    let act: (BarAction) -> Void
    let open: () -> Void
    let rename: () -> Void
    @State private var hovering = false

    private let tile: CGFloat = 72
    private let icon: CGFloat = 40

    var body: some View {
        Button(action: open) {
            VStack(spacing: 8) {
                ZStack {
                    // The icon's corner (0.225 of its side) plus the 16 points around it.
                    RoundedRectangle(cornerRadius: icon * 0.225 + (tile - icon) / 2, style: .continuous)
                        .fill(hovering ? Palette.hover : Palette.wash)
                    if item.isFolder {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(Palette.muted)
                            .accessibilityHidden(true)
                    } else {
                        SiteIconView(url: item.url, size: icon)
                    }
                }
                .frame(width: tile, height: tile)
                Text(item.label)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 96, alignment: .top)
            }
            .frame(width: 96)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScale())
        .onHover { hovering = $0 }
        .animation(.bar, value: hovering)
        .help(item.url.map(Destination.pretty) ?? item.label)
        .contextMenu {
            if let url = item.url {
                Button("Open in New Tab", systemImage: "plus.square.on.square") { act(.openInNewTab(url)) }
                Button("Copy Address", systemImage: "doc.on.doc") { UIPasteboard.general.url = url }
            }
            Button("Rename…", systemImage: "pencil") { rename() }
            if !targets.isEmpty {
                Menu("Move to…", systemImage: "folder") {
                    ForEach(targets) { target in
                        Button(target.label, systemImage: target.folder == nil ? "star.square.on.square" : "folder") {
                            act(.moveBookmark(item.id, into: target.folder))
                        }
                    }
                }
            }
            Button(item.isFolder ? "Delete Folder" : "Delete Bookmark", systemImage: "trash", role: .destructive) {
                act(.removeBookmark(item.id))
            }
        }
        .accessibilityLabel(item.isFolder ? "\(item.label), folder" : item.label)
    }
}
