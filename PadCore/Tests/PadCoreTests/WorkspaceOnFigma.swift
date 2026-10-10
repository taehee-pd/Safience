import Foundation
@testable import PadCore

extension Workspace {
    /// Where most tests begin: one space with one tab that is somewhere, so it
    /// can be pinned, recorded and closed. The first launch itself opens a
    /// new tab (Workspace.starting).
    static func onFigma(now: Date = Date()) -> Workspace {
        let tab = TabRecord(url: URL(string: "https://www.figma.com/files"), title: "Figma", shown: now)
        return Workspace(spaces: [Space(name: "Work", symbol: "briefcase", tabs: [tab], selected: tab.id)])
    }
}
