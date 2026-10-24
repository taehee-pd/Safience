import AppKit
import SwiftUI

/// Replace system Close so Command-W has one owner in a browser window.
struct BrowserCloseCommands: Commands {
    @FocusedObject private var focusedWindow: WindowModel?

    private var browser: WindowModel? {
        focusedWindow ?? Session.shared.allWindows.first { $0.window === NSApp.keyWindow }
    }

    var body: some Commands {
        CommandGroup(replacing: .saveItem) {
            if let browser {
                Button(browser.title(for: .closeTab)) { browser.closeTab() }
                    .keyboardShortcut("w")
                    .disabled(browser.tabID == nil)
                Button("Close Window") { browser.window?.performClose(nil) }
                    .keyboardShortcut("w", modifiers: [.command, .shift])
            } else {
                // Auxiliary windows retain their standard Close command.
                Button("Close Window") { NSApp.keyWindow?.performClose(nil) }
                    .keyboardShortcut("w")
            }
        }
    }
}
