import Foundation

/// The access a person approves, without requiring manifest terminology.
public enum ExtensionAccessDescription {
    public static func capability(_ permission: String) -> String {
        let descriptions = [
            "storage": "Store its settings and data on this Mac",
            "unlimitedStorage": "Store data without the normal storage limit",
            "tabs": "Read the addresses and titles of your tabs",
            "activeTab": "Read and change the page when you use the extension",
            "scripting": "Run scripts on sites you allow",
            "declarativeNetRequest": "Block or redirect network requests on allowed sites",
            "declarativeNetRequestWithHostAccess": "Block or redirect requests on allowed sites",
            "declarativeNetRequestFeedback": "Read which network rules were applied",
            "webRequest": "Observe network requests on allowed sites",
            "webRequestBlocking": "Block network requests on allowed sites",
            "bookmarks": "Read and change your bookmarks",
            "history": "Read and change your browsing history",
            "downloads": "Manage downloaded files",
            "notifications": "Show notifications",
            "clipboardRead": "Read your clipboard",
            "clipboardWrite": "Write to your clipboard",
            "nativeMessaging": "Communicate with a desktop app you allow",
            "sidePanel": "Show a side panel",
            "contextMenus": "Add items to page menus",
            "menus": "Add items to page menus",
            "alarms": "Schedule background tasks",
            "offscreen": "Run an extension page in the background",
            "cookies": "Cookie access is blocked by Safience",
            "identity": "Request sign-in for the extension",
            "tabCapture": "Capture a tab after you allow it",
            "desktopCapture": "Request screen sharing",
            "management": "Read or manage installed extensions",
            "privacy": "Request changes to browser privacy settings",
        ]
        return descriptions[permission] ?? "Request an additional capability (\(permission))"
    }

    public static func site(_ pattern: String) -> String {
        if ["<all_urls>", "*://*/*", "http://*/*", "https://*/*"].contains(pattern) {
            if pattern.hasPrefix("https:") { return "All HTTPS websites" }
            if pattern.hasPrefix("http:") { return "All HTTP websites" }
            return "All websites"
        }
        if pattern.hasPrefix("file:") { return "Local files you open" }
        guard let scheme = pattern.range(of: "://") else { return pattern }
        let rest = pattern[scheme.upperBound...]
        let host = String(rest.prefix { $0 != "/" })
        let path = String(rest.dropFirst(host.count))
        let domain = host.hasPrefix("*.") ? "\(host.dropFirst(2)) and its subdomains" : host
        let transport = pattern.hasPrefix("https:") ? " over HTTPS" : pattern.hasPrefix("http:") ? " over HTTP" : ""
        return (path.isEmpty || path == "/*" ? domain : "\(domain), pages matching \(path)") + transport
    }

    public static func lines(for grants: [String]) -> [String] {
        Array(Set(grants.map { $0.hasPrefix("site:") ? site(String($0.dropFirst(5))) : capability($0) })).sorted()
    }
}

/// A zero update count is meaningful only alongside every extension's outcome.
public struct ExtensionUpdateReport: Sendable {
    public enum Status: Sendable { case completed, busy, disabled, notDue, empty }
    public enum Outcome: String, Sendable { case current, updated, failed, declined, deferred }
    public struct Entry: Sendable {
        public let id: String
        public let name: String
        public let outcome: Outcome
        public let detail: String?
        public init(id: String, name: String, outcome: Outcome, detail: String? = nil) {
            self.id = id; self.name = name; self.outcome = outcome; self.detail = detail
        }
    }
    public var status: Status
    public var entries: [Entry]
    public init(status: Status = .completed, entries: [Entry] = []) { self.status = status; self.entries = entries }
    public var fullyChecked: Bool { status == .completed && !entries.isEmpty && entries.allSatisfy { [.current, .updated].contains($0.outcome) } }
    public var summary: String {
        switch status {
        case .busy: return "An update check is already running."
        case .disabled: return "Automatic update checks are off."
        case .notDue: return "The next automatic check is not due yet."
        case .empty: return "No Chrome Web Store extensions to check."
        case .completed: break
        }
        guard !entries.isEmpty else { return "The store did not return an update result. Try again." }
        let updated = entries.filter { $0.outcome == .updated }.count
        if fullyChecked { return updated == 0 ? "All checked extensions are up to date." : "Updated \(updated) \(updated == 1 ? "extension" : "extensions")." }
        let counts = [Outcome.updated, .current, .failed, .declined, .deferred].compactMap { outcome -> String? in
            let count = entries.filter { $0.outcome == outcome }.count
            return count == 0 ? nil : "\(count) \(outcome.rawValue)"
        }
        return counts.joined(separator: ", ") + ". Check Again retries failures and declined versions."
    }
}
