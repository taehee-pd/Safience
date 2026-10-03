import PadCore
import UIKit

/// The app's menus, which are mostly an absence.
///
/// Every menu iPadOS puts in an app by itself (File, Edit, Format, View,
/// Window, Help, and the app menu's own items; the menu bar of iPadOS 26
/// shows them all) comes with shortcuts on ⌘: ⌘F, ⌘W, ⌘N, ⌘Z, ⌘B. A menu's
/// shortcut answers before the page hears the key, so Figma's ⌘Z, a page's
/// own ⌘F, a document's ⌘B would never reach the page. They are all taken
/// out, whichever of them this iPadOS has, and the browser's own commands
/// go in their place on ⌃⌥, which pages leave alone.
@MainActor
enum Menus {
    static func build(_ builder: UIMenuBuilder) {
        guard builder.system == .main else { return }
        for child in builder.menu(for: .root)?.children ?? [] {
            guard let menu = child as? UIMenu, menu.identifier != .application else { continue }
            builder.remove(menu: menu.identifier)
        }
        builder.replaceChildren(ofMenu: .application) { _ in [] }

        builder.insertSibling(menu("Go", [.palette, .address, .back, .forward, .reload, .stop]), afterMenu: .application)
        builder.insertSibling(tabsMenu(), afterMenu: Identifier.go)
        builder.insertSibling(menu("Spaces", [.nextSpace, .previousSpace, .newSpace, .spaceSettings, .importBookmarks,
                                              .newWindow, .closeWindow]),
                              afterMenu: Identifier.tabs)
        builder.insertSibling(menu("Window", [.tabBar, .diagnostics, .focusPage, .settings]), afterMenu: Identifier.spaces)
    }

    enum Identifier {
        static let go = UIMenu.Identifier("Safience.Go")
        static let tabs = UIMenu.Identifier("Safience.Tabs")
        static let spaces = UIMenu.Identifier("Safience.Spaces")
        static let window = UIMenu.Identifier("Safience.Window")

        static func named(_ title: String) -> UIMenu.Identifier {
            switch title {
            case "Go": return go
            case "Tabs": return tabs
            case "Spaces": return spaces
            default: return window
            }
        }
    }

    private static func menu(_ title: String, _ commands: [Command]) -> UIMenu {
        UIMenu(title: title, identifier: Identifier.named(title), children: commands.compactMap(keyCommand))
    }

    private static func tabsMenu() -> UIMenu {
        let main = [Command.newTab, .closeTab, .reopenTab, .pinTab, .splitTab, .bookmark, .nextTab, .previousTab]
            .compactMap(keyCommand)
        let numbers = Shortcuts.tabNumbers.enumerated().map { index, chord -> UIKeyCommand in
            let title = index == 8 ? "Last Tab" : "Tab \(index + 1)"
            return UIKeyCommand(title: title, action: #selector(Browser.browserTab(_:)), input: input(chord.key),
                                modifierFlags: flags(chord), propertyList: index + 1)
        }
        return UIMenu(title: "Tabs", identifier: Identifier.tabs, children: main + [
            UIMenu(title: "", options: .displayInline, children: numbers),
        ])
    }

    private static func keyCommand(_ command: Command) -> UIKeyCommand? {
        guard let chord = Shortcuts.chord(for: command) else { return nil }
        return UIKeyCommand(title: command.title, action: #selector(Browser.browserCommand(_:)),
                            input: input(chord.key), modifierFlags: flags(chord), propertyList: command.rawValue)
    }

    private static func flags(_ chord: Chord) -> UIKeyModifierFlags {
        chord.shift ? [.control, .alternate, .shift] : [.control, .alternate]
    }

    private static func input(_ key: Key) -> String {
        switch key {
        case .character(let c): return c
        case .left: return UIKeyCommand.inputLeftArrow
        case .right: return UIKeyCommand.inputRightArrow
        case .up: return UIKeyCommand.inputUpArrow
        case .down: return UIKeyCommand.inputDownArrow
        case .escape: return UIKeyCommand.inputEscape
        case .tab: return "\t"
        }
    }
}
