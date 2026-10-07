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
/// go in their place on ⌃⌥, which pages leave alone. Two of iPadOS's stay,
/// without their ⌘ keys: the Window menu, which iPadOS shows in any case,
/// and the app menu's item that opens Safience's page in the Settings app.
@MainActor
enum Menus {
    static func build(_ builder: UIMenuBuilder) {
        guard builder.system == .main else { return }
        for child in builder.menu(for: .root)?.children ?? [] {
            // The app menu and the Window menu stay. iPadOS shows a Window
            // menu of its own whatever the app does (tiling, the open
            // windows), so the window's commands join it, not a second one.
            guard let menu = child as? UIMenu, menu.identifier != .application, menu.identifier != .window else { continue }
            builder.remove(menu: menu.identifier)
        }

        // The app menu: Safience's settings, where an app's settings go, and
        // iPadOS's own item, which opens Safience's page in the Settings app
        // (permissions, the default browser). iPadOS names that one
        // "Safience Settings…" too; it is named for where it goes instead.
        builder.replaceChildren(ofMenu: .application) { children in
            let system = children.compactMap { $0 as? UIMenu }.filter { $0.identifier == .preferences }
                .flatMap(\.children).map(withoutCommandKeys)
            for case let command as UICommand in system { command.title = "iPadOS Settings…" }
            let own = [keyCommand(.settings, title: "Settings…")].compactMap { $0 }
            return [UIMenu(title: "", identifier: Identifier.settings, options: .displayInline, children: own + system)]
        }

        builder.insertSibling(menu("Go", [.palette, .address, .back, .forward, .reload, .stop, .share, .siteMode]), afterMenu: .application)
        builder.insertSibling(tabsMenu(), afterMenu: Identifier.go)
        builder.insertSibling(menu("Spaces", [.nextSpace, .previousSpace, .newSpace, .spaceSettings, .importBookmarks,
                                              .newWindow, .closeWindow]),
                              afterMenu: Identifier.tabs)

        let window = [Command.tabBar, .diagnostics, .focusPage].compactMap { keyCommand($0) }
        if let system = builder.menu(for: .window) {
            // Its own items keep their place, without ⌘ keys; the window's commands go first.
            builder.replace(menu: .window, with: system.replacingChildren(
                [UIMenu(title: "", identifier: Identifier.window, options: .displayInline, children: window)]
                    + system.children.map(withoutCommandKeys)
            ))
        } else {
            builder.insertSibling(UIMenu(title: "Window", identifier: Identifier.window, children: window),
                                  afterMenu: Identifier.spaces)
        }
    }

    /// A system item as it was, without its ⌘ shortcut: a shortcut on ⌘ answers
    /// before the page hears the key. The item still does what it did.
    private static func withoutCommandKeys(_ element: UIMenuElement) -> UIMenuElement {
        if let menu = element as? UIMenu {
            return menu.replacingChildren(menu.children.map(withoutCommandKeys))
        }
        guard let key = element as? UIKeyCommand, key.modifierFlags.contains(.command), let action = key.action else {
            return element
        }
        return UICommand(title: key.title, image: key.image, action: action, propertyList: key.propertyList,
                         alternates: key.alternates, discoverabilityTitle: key.discoverabilityTitle,
                         attributes: key.attributes, state: key.state)
    }

    enum Identifier {
        static let go = UIMenu.Identifier("Safience.Go")
        static let tabs = UIMenu.Identifier("Safience.Tabs")
        static let spaces = UIMenu.Identifier("Safience.Spaces")
        static let window = UIMenu.Identifier("Safience.Window")
        static let settings = UIMenu.Identifier("Safience.Settings")

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
        UIMenu(title: title, identifier: Identifier.named(title), children: commands.compactMap { keyCommand($0) })
    }

    private static func tabsMenu() -> UIMenu {
        let main = [Command.newTab, .closeTab, .reopenTab, .pinTab, .splitTab, .bookmark, .nextTab, .previousTab]
            .compactMap { keyCommand($0) }
        let numbers = Shortcuts.tabNumbers.enumerated().map { index, chord -> UIKeyCommand in
            let title = index == 8 ? "Last Tab" : "Tab \(index + 1)"
            return UIKeyCommand(title: title, action: #selector(Browser.browserTab(_:)), input: input(chord.key),
                                modifierFlags: flags(chord), propertyList: index + 1)
        }
        return UIMenu(title: "Tabs", identifier: Identifier.tabs, children: main + [
            UIMenu(title: "", options: .displayInline, children: numbers),
        ])
    }

    private static func keyCommand(_ command: Command, title: String? = nil) -> UIKeyCommand? {
        guard let chord = Shortcuts.chord(for: command) else { return nil }
        return UIKeyCommand(title: title ?? command.title, action: #selector(Browser.browserCommand(_:)),
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
