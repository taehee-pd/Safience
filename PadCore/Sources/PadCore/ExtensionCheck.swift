import Foundation

/// What an extension's errors say, kept to what can be told safely.
///
/// On macOS 27 WebKit hands the app an extension's uncaught errors, failed
/// promises and `console.error` calls, with the file and line. Most are
/// the extension's own business, `console.error` least of all (an extension
/// logs a success with it as easily as a failure), so only an error whose
/// words name an API Safience can't answer is a problem: JavaScriptCore's
/// own wording for reaching something that isn't there. The error's words
/// themselves are never kept: they can hold an address, or whose account it
/// is. Only the kind, the API and where.
public enum ExtensionError {
    public enum Kind: Hashable, Sendable {
        /// Something that isn't there was read: `x.sidePanel.open` with no
        /// sidePanel.
        case missing
        /// Something that isn't a function was called.
        case notAFunction
        /// WebKit refused a call's arguments: "Invalid call to tabs.query()".
        case wrongArguments
    }

    public struct Problem: Equatable, Hashable, Sendable {
        public var kind: Kind
        /// The API, without whatever stood for `chrome`: "sidePanel" or
        /// "sidePanel.open".
        public var api: String

        public init(kind: Kind, api: String) {
            self.kind = kind
            self.api = api
        }
    }

    /// The problem an error's message tells of, when it is about an API:
    /// one of `missing`, what nothing on this Mac answers ("sidePanel",
    /// "tabs.discard"), or any reached through `chrome.` or `browser.`. An
    /// error about the extension's own things, `state.tabs.length`, isn't one,
    /// though `tabs` is an API's name too.
    public static func problem(in message: String, missing: Set<String>) -> Problem? {
        // Only a Chrome API's path is ever kept: a message can name anything,
        // an address or an account included ("Invalid call to alice@…(").
        guard let found = parsed(message, missing: missing), isAPIPath(found.api) else { return nil }
        return found
    }

    /// Chrome's namespaces (developer.chrome.com/docs/extensions/reference/api),
    /// Safari's `menus`, and the objects themselves.
    static let chromeNamespaces: Set<String> = [
        "chrome", "browser", "accessibilityFeatures", "action", "alarms", "audio", "bookmarks", "browserAction",
        "browsingData", "certificateProvider", "commands", "contentSettings", "contextMenus", "cookies", "debugger",
        "declarativeContent", "declarativeNetRequest", "desktopCapture", "devtools", "dns", "documentScan", "dom",
        "downloads", "enterprise", "events", "extension", "extensionTypes", "fileBrowserHandler", "fileSystemProvider",
        "fontSettings", "gcm", "history", "i18n", "identity", "idle", "input", "instanceID", "loginState", "management",
        "menus", "notifications", "offscreen", "omnibox", "pageAction", "pageCapture", "permissions", "platformKeys",
        "power", "printerProvider", "printing", "printingMetrics", "privacy", "processes", "proxy", "readingList",
        "runtime", "scripting", "search", "sessions", "sidePanel", "storage", "system", "systemLog", "tabCapture",
        "tabGroups", "tabs", "topSites", "tts", "ttsEngine", "types", "userScripts", "vpnProvider", "wallpaper",
        "webAuthenticationProxy", "webNavigation", "webRequest", "windows",
    ]

    /// Whether `path` is a Chrome API's: one of its namespaces, then at most
    /// two plain names ("tabs", "tabs.query", "system.display.getInfo").
    public static func isAPIPath(_ path: String) -> Bool {
        let parts = path.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count), chromeNamespaces.contains(String(parts[0])) else { return false }
        return parts.allSatisfy { part in
            guard let first = part.first, first.isLetter || first == "_" || first == "$" else { return false }
            return part.count <= 64 && part.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "$") }
        }
    }

    static func parsed(_ message: String, missing: Set<String>) -> Problem? {
        // A member path only: an expression with a call or an index in it
        // ("chrome.storage.local.get(\"alice@…\").finally") names no API by
        // its parts, and its arguments can hold anything.
        let plain = { (expression: String) in
            expression.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "$" || $0 == "." || $0 == " " }
        }
        if let expression = between(message, "is not an object (evaluating '", "'") {
            guard plain(expression) else { return nil }
            // undefined is not an object (evaluating 'e.sidePanel.open'):
            // what was undefined is all but the last member.
            let parts = expression.split(separator: ".").map(String.init)
            guard parts.count >= 2 else { return nil }
            return api(in: Array(parts.dropLast()), missing).map { Problem(kind: .missing, api: $0) }
        }
        if let expression = between(message, "", " is not a function") {
            let last = expression.components(separatedBy: CharacterSet(charactersIn: " ")).last ?? ""
            guard plain(last) else { return nil }
            let parts = expression.components(separatedBy: CharacterSet(charactersIn: " ")).last?
                .split(separator: ".").map(String.init) ?? []
            return api(in: parts, missing).map { Problem(kind: .notAFunction, api: $0) }
        }
        if let expression = between(message, "Can't find variable: ", nil) {
            let name = String(expression.prefix { !$0.isWhitespace })
            return ["chrome", "browser"].contains(name) ? Problem(kind: .missing, api: name) : nil
        }
        if let call = between(message, "Invalid call to ", "(") {
            // WebKit's own words, about its own API: always one.
            let parts = call.split(separator: ".").map(String.init)
            return parts.isEmpty ? nil : Problem(kind: .wrongArguments, api: parts.prefix(2).joined(separator: "."))
        }
        return nil
    }

    /// Where an error happened, from the end WebKit gives its message:
    /// "… (background.js:12:5)". The file is the extension's own path.
    public static func place(in message: String) -> (file: String, line: Int)? {
        guard message.hasSuffix(")"), let open = message.lastIndex(of: "(") else { return nil }
        let inside = message[message.index(after: open)..<message.index(before: message.endIndex)]
        let parts = inside.split(separator: ":")
        guard parts.count >= 3, let line = Int(parts[parts.count - 2]), Int(parts[parts.count - 1]) != nil else { return nil }
        let file = parts.dropLast(2).joined(separator: ":")
        // Keep the path inside the extension, not the address it is served at.
        let path = file.range(of: "://").map { String(file[$0.upperBound...].drop { $0 != "/" }.dropFirst()) } ?? file
        return (path, line)
    }

    /// The API in a chain: `chrome.sidePanel.open` and a minified
    /// `e.sidePanel.open` are both "sidePanel.open" when sidePanel is
    /// missing; `chrome.tabs.discard` is "tabs.discard" whatever the list
    /// says, since `chrome.` makes it the API's.
    static func api(in parts: [String], _ missing: Set<String>) -> String? {
        for index in parts.indices {
            let path = parts[index...].prefix(2).joined(separator: ".")
            let afterChrome = index > 0 && ["chrome", "browser"].contains(parts[index - 1])
            if afterChrome || missing.contains(path) { return path }
            if missing.contains(parts[index]) { return parts[index] }
        }
        return nil
    }

    static func between(_ text: String, _ before: String, _ after: String?) -> String? {
        let start: String.Index
        if before.isEmpty {
            start = text.startIndex
        } else {
            guard let found = text.range(of: before) else { return nil }
            start = found.upperBound
        }
        guard let after else { return String(text[start...]) }
        guard let end = text[start...].range(of: after) else { return nil }
        return String(text[start..<end.lowerBound])
    }
}

/// What the checks after install saw, and what they let Safience say.
///
/// Seen and suspected stay apart: reading the code gives notes, never a
/// status, and only an extension tried by hand for a release is said to
/// work, since only there were its features used.
public struct ExtensionEvidence: Equatable, Sendable {
    public enum Start: Equatable, Sendable {
        case checking
        case started
        /// It didn't start, and starting it again didn't help.
        case failed
        /// Too slow to say, after starting it again.
        case timedOut
    }

    public enum Probe: Equatable, Sendable {
        /// The extension has nothing of the kind: no popup, no scripts for
        /// every site.
        case notApplicable
        case checking
        case passed
        case failed
        /// It has one, but it can't be tried here: scripts for one site
        /// only, which a test page would only fail.
        case skipped
        case timedOut
    }

    public var start: Start = .checking
    public var testPage: Probe = .notApplicable
    public var popup: Probe = .notApplicable
    public var optionsPage: Probe = .notApplicable
    /// Errors of a known kind, seen at start or in use.
    public var problems: Set<ExtensionError.Problem> = []
    /// The desktop app it talks to, when a call to it failed: "Bitwarden".
    public var unreachableApp: String?
    /// From reading the code: APIs used with no test first, that nothing
    /// on this Mac answers.
    public var mayNotWork: [String] = []
    /// It asked for `cookies`, which no extension gets (hands-off).
    public var cookiesKeptBack = false
    /// Its entry in the list of extensions tried by hand for this release.
    public var tried: Tried?

    public struct Tried: Equatable, Sendable {
        public var release: String
        public var works: Bool
        /// What was tried, in words: "blocking on 20 sites".
        public var what: String

        public init(release: String, works: Bool, what: String) {
            self.release = release
            self.works = works
            self.what = what
        }
    }

    public init() {}
}

/// The line under an extension's name.
public struct ExtensionVerdict: Equatable, Sendable {
    public enum Status: Hashable, Sendable {
        case checking
        case startedFine
        case someFeaturesDontWork
        case couldntStart
        case notCheckedYet
        case triedWorks
        case triedDoesntWork
    }

    public var status: Status
    public var title: String
    public var lines: [String]

    public init(_ evidence: ExtensionEvidence) {
        var lines: [String] = []
        let failedProbes = [
            (evidence.testPage, "Its scripts didn't run on a test page."),
            (evidence.popup, "Its popup didn't open."),
            (evidence.optionsPage, "Its settings page didn't open."),
        ].filter { $0.0 == .failed }.map(\.1)
        let features = evidence.problems.map { Self.words(for: $0.api) }.sorted()

        switch evidence.start {
        case .checking:
            status = .checking
        case .failed, .timedOut:
            status = .couldntStart
            lines.append("Safience tried starting it again.")
        case .started:
            let probes = [evidence.testPage, evidence.popup, evidence.optionsPage]
            if !features.isEmpty || !failedProbes.isEmpty || evidence.unreachableApp != nil {
                status = .someFeaturesDontWork
                lines += features.map { "Can't \($0)." } + failedProbes
                if let app = evidence.unreachableApp { lines.append("Can't reach the \(app) app.") }
            } else if probes.contains(.checking) {
                status = .checking
            } else if let tried = evidence.tried {
                status = tried.works ? .triedWorks : .triedDoesntWork
                lines.append("Tried by Safience on version \(tried.release): \(tried.what).")
            } else {
                let passed = [(evidence.testPage, "a test page"), (evidence.popup, "its popup"), (evidence.optionsPage, "its settings page")]
                    .filter { $0.0 == .passed }.map(\.1)
                let untried = probes.contains(.skipped) || probes.contains(.timedOut)
                if untried, passed.isEmpty {
                    status = .notCheckedYet
                } else {
                    status = .startedFine
                    lines.append("Checked: " + Self.list(["starting up"] + passed) + ". Its features haven't all been tried.")
                }
            }
        }
        if status != .checking {
            // What was seen not to work isn't said again as what may not.
            let seen = Set(evidence.problems.map { Self.words(for: $0.api) })
            lines += evidence.mayNotWork.map { Self.words(for: $0) }.filter { !seen.contains($0) }.map { "May not work: \($0)." }
            if evidence.cookiesKeptBack { lines.append("Can't read cookies: kept from Google's sign-in.") }
        }
        title = Self.titles[status] ?? ""
        self.lines = lines
    }

    static let titles: [Status: String] = [
        .checking: "Checking…",
        .startedFine: "Started Fine",
        .someFeaturesDontWork: "Some Features Don't Work",
        .couldntStart: "Couldn't Start",
        .notCheckedYet: "Not Checked Yet",
        .triedWorks: "Works",
        .triedDoesntWork: "Doesn't Work",
    ]

    /// What an API is for, in words that finish "Can't …" and
    /// "May not work: …". An API not in the list is named as it is.
    static let features: [String: String] = [
        "sidePanel": "open its side panel",
        "offscreen": "work out of sight",
        "tabCapture": "record a tab",
        "pageCapture": "save a page",
        "desktopCapture": "share the screen",
        "debugger": "inspect pages",
        "identity": "sign in",
        "identity.getAuthToken": "sign in with your Google account",
        "notifications": "show notifications",
        "bookmarks": "read your bookmarks",
        "history": "read your history",
        "downloads": "manage downloads",
        "tabGroups": "group tabs",
        "topSites": "list your most visited sites",
        "sessions": "reopen closed tabs",
        "tts": "read aloud",
        "ttsEngine": "add a voice",
        "gcm": "receive messages",
        "instanceID": "receive messages",
        "proxy": "change the proxy",
        "privacy": "change privacy settings",
        "management": "manage other extensions",
        "fontSettings": "change fonts",
        "contentSettings": "change site settings",
        "readingList": "use the reading list",
        "webRequestBlocking": "block requests the old way",
    ]

    static func words(for api: String) -> String {
        features[api] ?? features[api.split(separator: ".").first.map(String.init) ?? api] ?? "use \(api)"
    }

    static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        default: return items.dropLast().joined(separator: ", ") + " and " + items[items.count - 1]
        }
    }
}

/// A failed start applies only to the runtime that actually tried it.
/// Legacy version-only markers cannot establish failure on a newer engine.
public struct ExtensionCheckEnvironment: Equatable, Sendable {
    public var system: String
    public var application: String
    public var shim: String

    public init(system: String, application: String, shim: String) {
        self.system = system
        self.application = application
        self.shim = shim
    }

    public func stamp(for version: String) -> String {
        [version, system, application, shim].joined(separator: "|")
    }

    public func currentFailures(_ failures: [String: String], installed: [String: String]) -> [String: String] {
        failures.filter { id, held in installed[id].map { held == stamp(for: $0) } ?? false }
    }
}

/// WebKit's error array retains and consolidates old errors. Its historical
/// failure can request one restart, but only that restart's own failed
/// completion establishes repeated failure. Deferred attempts prove nothing.
public struct ExtensionWorkerRecovery: Sendable {
    public enum Action: Equatable, Sendable { case ignore, restart, incompatible }
    public private(set) var attempt: UUID?
    private var sawHistoricalFailure = false
    private var restarting = false
    private var completed = false

    public init() {}

    public mutating func beganAttempt(restarting: Bool) -> UUID {
        let token = UUID()
        attempt = token
        self.restarting = restarting
        completed = false
        return token
    }

    public mutating func noticedHistoricalFailure() -> Action {
        guard !sawHistoricalFailure else { return .ignore }
        sawHistoricalFailure = true
        return restarting ? .ignore : .restart
    }

    public mutating func finished(_ token: UUID, failed: Bool) -> Action {
        guard token == attempt, !completed else { return .ignore }
        completed = true
        guard failed else { return .ignore }
        return restarting ? .incompatible : noticedHistoricalFailure()
    }
}
