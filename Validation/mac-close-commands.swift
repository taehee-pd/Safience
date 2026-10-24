import AppKit
import SwiftUI
import Darwin

// The wrapper appends the production close command and closeTab method.
// Session is a synthetic in-memory collaborator; no browser or data store starts.
@main
struct CloseCommandsAcceptance: App {
    @StateObject private var model = WindowModel()

    var body: some Scene {
        WindowGroup {
            FixtureField()
                .frame(width: 360, height: 100)
                .focusedSceneObject(model)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        CloseCommandProbe(model: model).run()
                    }
                }
        }
        .commands { BrowserCloseCommands() }
    }
}

enum Command { case closeTab }

extension Animation {
    static var bar: Animation { .linear(duration: 0) }
}

@MainActor
final class Session {
    static let shared = Session()
    var tabs: [UUID] = [UUID(), UUID()]
    var allWindows: [WindowModel] = []
    var closed: [UUID] = []
    func closeTab(_ id: UUID) {
        guard tabs.contains(id) else { return }
        tabs.removeAll { $0 == id }
        closed.append(id)
        allWindows.forEach { $0.tabID = tabs.first }
    }
}

@MainActor
final class WindowModel: ObservableObject {
    weak var window: NSWindow?
    @Published var tabID: UUID? = Session.shared.tabs.first
    func title(for command: Command) -> String { "Close Tab" }
    func focusPage() {}
}

private struct FixtureField: NSViewRepresentable {
    func makeNSView(context: Context) -> NSTextField { NSTextField(string: "Synthetic text") }
    func updateNSView(_ view: NSTextField, context: Context) {}
}

@MainActor
private final class CloseCommandProbe {
    let model: WindowModel
    private var failures = 0
    init(model: WindowModel) { self.model = model }

    func run() {
        Task { await execute() }
    }

    private func execute() async {
        guard let window = NSApp.windows.first(where: { $0.contentView != nil }),
              let field = window.contentView.flatMap(findField), let menu = NSApp.mainMenu else {
            print("FAIL native fixture has no window, field or menu"); exit(1)
        }
        model.window = window
        Session.shared.allWindows = [model]
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        await settle()
        let unmodified = items(in: menu).filter {
            $0.keyEquivalent == "w" && $0.keyEquivalentModifierMask.intersection(.deviceIndependentFlagsMask) == .command
        }
        check(unmodified.count == 1, "Exactly one Command-W menu route")
        check(unmodified.first?.title == "Close Tab", "Command-W belongs to Close Tab")
        let ids = Session.shared.tabs
        performCloseKey(in: menu, window: window)
        await settle()
        check(Session.shared.closed == [ids[0]] && Session.shared.tabs == [ids[1]] && window.isVisible,
              "Command-W closes one tab and keeps its window")
        window.makeFirstResponder(field)
        check(field.currentEditor() != nil, "Text field editor owns keyboard focus")
        performCloseKey(in: menu, window: window)
        await settle()
        check(Session.shared.tabs.isEmpty && Session.shared.closed == ids && window.isVisible,
              "Command-W from a text field closes the last tab and keeps its window")
        performCloseKey(in: menu, window: window)
        await settle()
        check(Session.shared.closed == ids && window.isVisible,
              "Command-W with no tab leaves the window open")
        model.closeTab()
        check(Session.shared.closed == ids && window.isVisible,
              "Direct Close Tab with no selection leaves the window open")
        let explicitClose = items(in: menu).filter {
            $0.keyEquivalent == "w" && $0.keyEquivalentModifierMask.intersection(.deviceIndependentFlagsMask) == [.command, .shift]
        }
        check(explicitClose.count == 1 && explicitClose.first?.title == "Close Window",
              "Shift-Command-W remains the explicit Close Window command")
        print("Close commands: \(8 - failures)/8 native checks passed")
        fflush(stdout)
        exit(failures == 0 ? 0 : 1)
    }

    private func settle() async {
        try? await Task.sleep(for: .milliseconds(200))
    }

    private func performCloseKey(in menu: NSMenu, window: NSWindow) {
        menu.update()
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                                    timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                    characters: "w", charactersIgnoringModifiers: "w", isARepeat: false, keyCode: 13)!
        _ = menu.performKeyEquivalent(with: event)
    }

    private func check(_ passed: Bool, _ label: String) {
        print("\(passed ? "PASS" : "FAIL") \(label)")
        if !passed { failures += 1 }
    }

    private func items(in menu: NSMenu) -> [NSMenuItem] {
        menu.items.flatMap { [$0] + ($0.submenu.map(items) ?? []) }
    }

    private func findField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField { return field }
        return view.subviews.compactMap { findField(in: $0) }.first
    }
}
