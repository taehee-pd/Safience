import AppKit
import PadCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
extension Session {
    /// File selection and every result stay attached to the window that asked.
    func chooseBookmarksFile(into space: UUID, in owner: NSWindow) {
        guard owner.isVisible, canUseWorkspace, owner.attachedSheet == nil else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.html, .zip]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Import Bookmarks"
        panel.message = "Choose an HTML bookmarks export from Chrome, Firefox or Safari, or a Safari ZIP export that includes Bookmarks."
        panel.beginSheetModal(for: owner) { [weak self, weak owner] response in
            guard response == .OK, let file = panel.url, let self, let owner, owner.isVisible else { return }
            let scoped = file.startAccessingSecurityScopedResource()
            self.importBookmarks(from: file, into: space) { [weak self, weak owner] result in
                if scoped { file.stopAccessingSecurityScopedResource() }
                guard let self, let owner, owner.isVisible else { return }
                self.showBookmarkImport(result, into: space, in: owner)
            }
        }
    }

    private func showBookmarkImport(_ result: BookmarkImportOutcome, into space: UUID, in owner: NSWindow) {
        guard owner.isVisible, owner.attachedSheet == nil else { return }
        let alert = NSAlert()
        alert.messageText = result.title
        alert.informativeText = result.message
        if let parsed = result.parsed {
            let spaces = workspace.spaces
            let choices = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 300, height: 28))
            choices.addItems(withTitles: spaces.map(\.name))
            choices.setAccessibilityLabel("Import bookmarks into space")
            alert.accessoryView = choices
            alert.addButton(withTitle: "Import into Selected Space")
            alert.addButton(withTitle: "Cancel")
            alert.buttons.first?.isEnabled = !spaces.isEmpty
            alert.beginSheetModal(for: owner) { [weak self, weak owner] response in
                guard response == .alertFirstButtonReturn, let self, let owner, owner.isVisible,
                      spaces.indices.contains(choices.indexOfSelectedItem) else { return }
                let destination = spaces[choices.indexOfSelectedItem].id
                self.importBookmarks(parsed, into: destination) { [weak self, weak owner] next in
                    guard let self, let owner else { return }
                    self.showBookmarkImport(next, into: destination, in: owner)
                }
            }
        } else if result.needsSave {
            alert.addButton(withTitle: "Retry Saving")
            alert.addButton(withTitle: "Keep Open")
            alert.beginSheetModal(for: owner) { [weak self, weak owner] response in
                guard response == .alertFirstButtonReturn, let self, let owner else { return }
                self.retryBookmarkImport(result) { [weak self, weak owner] next in
                    guard let self, let owner else { return }
                    self.showBookmarkImport(next, into: space, in: owner)
                }
            }
        } else if result.canChooseFile {
            alert.addButton(withTitle: "Choose Another File…")
            alert.addButton(withTitle: "Cancel")
            alert.beginSheetModal(for: owner) { [weak self, weak owner] response in
                guard response == .alertFirstButtonReturn, let self, let owner else { return }
                self.chooseBookmarksFile(into: space, in: owner)
            }
        } else {
            alert.addButton(withTitle: "Done")
            if result.isComplete { alert.addButton(withTitle: "Import Another File…") }
            alert.beginSheetModal(for: owner) { [weak self, weak owner] response in
                guard response == .alertSecondButtonReturn, let self, let owner else { return }
                self.chooseBookmarksFile(into: space, in: owner)
            }
        }
    }
}

/// Settings has its own window and never borrows the last browser's window.
struct BookmarkImportWindowReader: NSViewRepresentable {
    let found: (NSWindow?) -> Void
    func makeNSView(context: Context) -> Reader { Reader(found: found) }
    func updateNSView(_ view: Reader, context: Context) { view.found = found }

    final class Reader: NSView {
        var found: (NSWindow?) -> Void
        init(found: @escaping (NSWindow?) -> Void) { self.found = found; super.init(frame: .zero) }
        required init?(coder: NSCoder) { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            let owner = window
            DispatchQueue.main.async { [weak self] in self?.found(owner) }
        }
    }
}
