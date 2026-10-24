import Foundation

/// Count actual destructive closures, excluding duplicate, missing and pinned tabs.
public struct TabClosePlan: Equatable, Sendable {
    public let ids: [UUID]
    public let ordinary: [UUID]
    public let pinned: [UUID]

    public init(workspace: Workspace, requested: [UUID]) {
        let wanted = Set(requested)
        let tabs = workspace.spaces.flatMap(\.tabs).filter { wanted.contains($0.id) }
        ids = tabs.map(\.id)
        ordinary = tabs.filter { !$0.isPinned }.map(\.id)
        pinned = tabs.filter(\.isPinned).map(\.id)
    }

    public var needsConfirmation: Bool { ordinary.count > 1 }
    public var title: String { String(format: BrowserText.localized("Close %@?"), BrowserText.tabCount(ordinary.count)) }
    public var actionTitle: String { String(format: BrowserText.localized("Close %@"), BrowserText.tabCount(ordinary.count)) }
    public var message: String {
        BrowserText.localized("Unsaved page changes in these tabs will be lost. Reopen Closed Tab restores saved addresses, not unsaved page changes. Pinned tabs stay available.")
    }
}

public enum SpaceRemovalScope: Equatable, Sendable {
    case deviceOnly, iCloudUnchanged, currentAccount
}

public enum SpaceRemovalCopy {
    public static func message(tabs: Int, device: String, scope: SpaceRemovalScope, extensionData: Bool) -> String {
        let count = BrowserText.tabCount(tabs)
        let local = "This closes \(count) and discards unsaved page changes. This space's bookmarks, pinned tabs, history, sign-ins, cookies and site data are removed from this \(device)."
        let extra = extensionData ? " Its extension data is removed too." : ""
        switch scope {
        case .deviceOnly: return local + extra
        case .iCloudUnchanged: return local + extra + " iCloud copies are unchanged and may return when sync resumes."
        case .currentAccount:
            return local + extra + " The space, bookmarks and pinned tabs are also removed from devices syncing with this Apple Account. Those devices close this space's tabs and remove its local data too."
        }
    }
}
