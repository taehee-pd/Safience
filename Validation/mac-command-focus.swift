import AppKit
import SwiftUI
import Darwin

/// Compiled with the actual CommandField and its coordinator by the shell wrapper.
/// A real AppKit event loop lets initial queued work finish before attachment.
@main
struct CommandFocusAcceptance {
    @MainActor static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let probe = CommandFocusProbe()
        probe.next()
        NSApplication.shared.run()
    }
}

@MainActor
private final class CommandFocusProbe {
    private let cases: [(name: String, selectsAll: Bool, staysActive: Bool)] = [
        ("Delayed attachment focuses address", false, true),
        ("Existing address is selected", true, true),
        ("Closed overlay cannot reclaim focus", false, false),
    ]
    private var index = 0
    private var failures = 0
    private var windows: [NSWindow] = []

    func next() {
        guard index < cases.count else {
            print("Command focus: \(cases.count - failures)/\(cases.count) native cases passed")
            fflush(stdout)
            exit(failures == 0 ? 0 : 1)
        }
        let item = cases[index]
        index += 1
        let gate = FocusGate()
        var cancelled = false
        let host = NSHostingView(rootView: CommandField(text: .constant("fixture"), placeholder: "Address",
                                                       selectsAll: item.selectsAll, isActive: { gate.active }) { key in
            if case .cancel = key { cancelled = true }
        })
        host.frame = NSRect(x: 0, y: 0, width: 500, height: 100)
        host.layoutSubtreeIfNeeded()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [self] in
            let madeBeforeWindow = field(in: host) != nil
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 100),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            windows.append(window)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            gate.active = item.staysActive
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [self] in
                let text = field(in: host)
                let focused = text != nil && (window.firstResponder === text || window.firstResponder === text?.currentEditor())
                var passed = madeBeforeWindow && focused == item.staysActive
                if item.staysActive, let text, let editor = text.currentEditor() as? NSTextView {
                    let wanted = item.selectsAll ? NSRange(location: 0, length: 7) : NSRange(location: 7, length: 0)
                    passed = passed && editor.selectedRange == wanted
                    _ = text.delegate?.control?(text, textView: editor,
                                               doCommandBy: #selector(NSResponder.cancelOperation(_:)))
                    passed = passed && cancelled
                }
                print("\(passed ? "PASS" : "FAIL") \(item.name)")
                fflush(stdout)
                if !passed { failures += 1 }
                next()
            }
        }
    }

    private func field(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField { return field }
        return view.subviews.compactMap { field(in: $0) }.first
    }
}

@MainActor
private final class FocusGate { var active = true }
