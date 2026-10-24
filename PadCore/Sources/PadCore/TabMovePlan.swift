import Foundation

/// An explicit choice across independent sign-in stores. The address and owners
/// are captured so a delayed dialog cannot move a replaced or navigated tab.
public struct TabMovePlan: Sendable {
    public enum Choice: Equatable, Sendable { case move, copy, cancel }
    public let tab: UUID
    public let source: UUID
    public let destination: UUID
    public let before: UUID?
    private let record: TabRecord
    private let sourceName: String
    private let destinationName: String

    public init?(workspace: Workspace, tab: UUID, destination: UUID, before: UUID? = nil) {
        guard let source = workspace.spaceID(of: tab), source != destination,
              let from = workspace.space(source), let to = workspace.space(destination),
              let record = workspace.tab(tab), before == nil || to.tabs.contains(where: { $0.id == before }) else { return nil }
        self.tab = tab; self.source = source; self.destination = destination; self.before = before
        self.record = record; sourceName = from.name; destinationName = to.name
    }

    public var title: String {
        String.localizedStringWithFormat(BrowserText.localized("Move Tab to “%@”?"), destinationName)
    }
    public var message: String {
        String.localizedStringWithFormat(BrowserText.localized("Moving this tab reloads it using the sign-ins and site data in “%@”. Unsaved changes and the current page state will be lost.\n\nOpen a Copy keeps the original tab and its unsaved work in “%@” and opens only its address in the destination."), destinationName, sourceName)
    }
    public func isValid(in workspace: Workspace) -> Bool {
        guard workspace.spaceID(of: tab) == source, workspace.space(destination) != nil,
              let current = workspace.tab(tab), current.url == record.url, current.pinned == record.pinned else { return false }
        if let before { return workspace.spaceID(of: before) == destination }
        return true
    }
    /// A copy receives a new tab ID and no shared pinned identity or browsing state.
    public func apply(_ choice: Choice, to workspace: inout Workspace) -> UUID? {
        guard isValid(in: workspace) else { return nil }
        switch choice {
        case .cancel: return nil
        case .move: return workspace.moveTab(tab, to: destination) ? tab : nil
        case .copy:
            guard let copy = workspace.openTab(record.url ?? record.pinned, in: destination) else { return nil }
            workspace.record(copy, url: record.url ?? record.pinned, title: record.title)
            return copy
        }
    }
}
