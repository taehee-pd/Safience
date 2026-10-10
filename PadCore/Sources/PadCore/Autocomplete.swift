import Foundation

/// A row under the address being typed: where it came from, the words it
/// offers, and what choosing it does.
public struct Suggestion: Identifiable, Equatable, Sendable {
    /// Where a row came from, as the row names it.
    public enum Source: Equatable, Sendable {
        case tab
        case pinnedTab
        case bookmark
        case command
        /// The search engine's suggestions, by the engine's name.
        case engine(String)

        public var label: String {
            switch self {
            case .tab: return "Open Tab"
            case .pinnedTab: return "Pinned Tab"
            case .bookmark: return "Bookmark"
            case .command: return "Command"
            case .engine(let name): return name
            }
        }
    }

    /// What choosing the row does.
    public enum Action: Equatable, Sendable {
        /// Goes to the tab, wherever it is.
        case tab(UUID)
        case open(URL)
        case command(Command)
        /// The words, as if typed and sent: an address when they are one, a
        /// search otherwise (Destination).
        case go(String)
    }

    public var id: String
    public var source: Source
    public var action: Action
    /// What the row reads as: the letters typed, and the rest completed.
    public var phrase: String
    /// Where in `phrase` the typed letters are, counted in characters; the
    /// rest is what the row completes.
    public var typed: [Range<Int>]
    /// A second line: the address of a page found by its title, the title
    /// of one found by its address, a command's keys.
    public var detail: String
    /// The page the row goes to, for its icon.
    public var url: URL?

    public init(id: String, source: Source, action: Action, phrase: String, typed: [Range<Int>],
                detail: String = "", url: URL? = nil) {
        self.id = id
        self.source = source
        self.action = action
        self.phrase = phrase
        self.typed = typed
        self.detail = detail
        self.url = url
    }
}

/// What the address bar offers while an address is typed: the space's tabs,
/// pinned tabs and bookmarks, the browser's commands, and the search engine's
/// suggestions.
///
/// Stricter than the palette's matching (PaletteSearch): the letters typed
/// have to start a word, as in Safari's and Chrome's address bars, so "fig"
/// finds figma.com and "Figma: Flows" but never "Configure".
public enum Autocomplete {
    /// Something on the device the address bar can offer.
    public struct Candidate: Sendable {
        public var id: String
        public var source: Suggestion.Source
        public var action: Suggestion.Action
        public var title: String
        public var url: URL?
        /// Other words it is found by: a command's.
        public var keywords: [String]
        /// The second line when there is no address to show: a command's keys.
        public var detail: String
        /// When a tab was last on screen: the more recent, the higher.
        public var shown: Date?

        public init(id: String, source: Suggestion.Source, action: Suggestion.Action, title: String, url: URL? = nil,
                    keywords: [String] = [], detail: String = "", shown: Date? = nil) {
            self.id = id
            self.source = source
            self.action = action
            self.title = title
            self.url = url
            self.keywords = keywords
            self.detail = detail
            self.shown = shown
        }
    }

    /// The device's rows, at most.
    public static let localLimit = 6
    /// Of those, commands, at most: the address bar is for going places.
    static let commandLimit = 2
    /// The engine's rows, at most.
    public static let engineLimit = 4

    // MARK: Matching

    /// How the typed letters sit in a text, best last.
    enum Fit: Int, Comparable {
        /// In a command's other words, not its title.
        case keyword = 1
        /// Every typed word starts a word, in any order.
        case words
        /// All of it, as typed, starts a word.
        case word
        /// All of it, as typed, starts the text.
        case start

        static func < (a: Fit, b: Fit) -> Bool {
            a.rawValue < b.rawValue
        }
    }

    /// Where `query` is in `text`, by characters, or nil when it isn't there
    /// at the start of a word.
    static func match(_ query: String, in text: String) -> (fit: Fit, typed: [Range<Int>])? {
        let needle = Array(query.trimmingCharacters(in: .whitespaces).lowercased())
        let hay = Array(text.lowercased())
        guard !needle.isEmpty, needle.count <= hay.count else { return nil }
        if hay.starts(with: needle) { return (.start, [0..<needle.count]) }
        if let at = hay.indices.first(where: { startsWord(hay, $0) && hay[$0...].starts(with: needle) }) {
            return (.word, [at..<at + needle.count])
        }
        let words = needle.split(whereSeparator: \.isWhitespace)
        guard words.count > 1 else { return nil }
        var found: [Range<Int>] = []
        for word in words {
            let at = hay.indices.first { index in
                startsWord(hay, index) && hay[index...].starts(with: word)
                    && !found.contains { $0.overlaps(index..<index + word.count) }
            }
            guard let at else { return nil }
            found.append(at..<at + word.count)
        }
        return (.words, found.sorted { $0.lowerBound < $1.lowerBound })
    }

    /// A word starts here: at the start, or after anything but a letter or a
    /// digit (a space, a dash, the dot or the slash of an address).
    private static func startsWord(_ letters: [Character], _ at: Int) -> Bool {
        at == 0 || !(letters[at - 1].isLetter || letters[at - 1].isNumber)
    }

    // MARK: The device's rows

    /// The candidates `query` finds, best first, at most `localLimit`, one
    /// row a page: an open tab before a bookmark of the same page.
    public static func local(_ candidates: [Candidate], query: String) -> [Suggestion] {
        let typed = query.trimmingCharacters(in: .whitespaces)
        guard !typed.isEmpty else { return [] }
        let found = candidates.enumerated().compactMap { order, candidate in
            suggestion(for: candidate, query: typed).map { (row: $0.row, fit: $0.fit, candidate: candidate, order: order) }
        }
        let ranked = found.sorted { a, b in
            if a.fit != b.fit { return a.fit > b.fit }
            if weight(a.candidate.source) != weight(b.candidate.source) {
                return weight(a.candidate.source) > weight(b.candidate.source)
            }
            let shownA = a.candidate.shown ?? .distantPast
            let shownB = b.candidate.shown ?? .distantPast
            if shownA != shownB { return shownA > shownB }
            if a.row.phrase.count != b.row.phrase.count { return a.row.phrase.count < b.row.phrase.count }
            return a.order < b.order
        }
        var rows: [Suggestion] = []
        var pages: Set<String> = []
        var commands = 0
        for item in ranked where rows.count < localLimit {
            if let url = item.candidate.url, !pages.insert(Bookmarks.key(url)).inserted { continue }
            if item.candidate.source == .command {
                guard commands < commandLimit else { continue }
                commands += 1
            }
            rows.append(item.row)
        }
        return rows
    }

    /// The candidate's row for `query`, or nil when it doesn't fit. A page
    /// is offered by its address when the typed letters start it (the
    /// address is what the field completes), by its title otherwise.
    static func suggestion(for candidate: Candidate, query: String) -> (row: Suggestion, fit: Fit)? {
        // A command for every letter would crowd out the pages.
        if candidate.source == .command, query.count < 2 { return nil }
        var best: (fit: Fit, phrase: String, typed: [Range<Int>])?
        var address = ""
        if let url = candidate.url {
            address = Address.pretty(url)
            let full = url.absoluteString
            let bare = full.range(of: "://").map { String(full[$0.upperBound...]) } ?? full
            for text in [address, bare, full] {
                if let found = match(query, in: text), found.fit == .start {
                    best = (fit: Fit.start, phrase: text, typed: found.typed)
                    break
                }
            }
        }
        if let found = match(query, in: candidate.title), best.map({ found.fit > $0.fit }) ?? true {
            best = (fit: found.fit, phrase: candidate.title, typed: found.typed)
        }
        if best == nil, candidate.keywords.contains(where: { match(query, in: $0) != nil }) {
            best = (fit: Fit.keyword, phrase: candidate.title, typed: [])
        }
        guard let best else { return nil }
        // The line under says what the phrase doesn't.
        let other = best.phrase == candidate.title ? (candidate.url == nil ? candidate.detail : address) : candidate.title
        let row = Suggestion(id: candidate.id, source: candidate.source, action: candidate.action, phrase: best.phrase,
                             typed: best.typed, detail: other == best.phrase ? "" : other, url: candidate.url)
        return (row, best.fit)
    }

    /// Tabs first, as the page is already open; then bookmarks; then commands.
    private static func weight(_ source: Suggestion.Source) -> Int {
        switch source {
        case .tab, .pinnedTab: return 2
        case .bookmark: return 1
        case .command, .engine: return 0
        }
    }

    // MARK: The engine's rows

    /// The engine's words for `query` as rows, at most `engineLimit`, less
    /// the words as typed, which Return already sends.
    public static func engine(_ words: [String], query: String, engine name: String) -> [Suggestion] {
        let typed = query.trimmingCharacters(in: .whitespaces)
        var seen: Set<String> = [typed.lowercased()]
        var rows: [Suggestion] = []
        for word in words where rows.count < engineLimit {
            let phrase = word.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !phrase.isEmpty, seen.insert(phrase.lowercased()).inserted else { continue }
            rows.append(Suggestion(id: "engine-\(phrase)", source: .engine(name), action: .go(phrase), phrase: phrase,
                                   typed: match(typed, in: phrase)?.typed ?? []))
        }
        return rows
    }

    /// The rows as they show: the device's best first when the typed letters
    /// start it, a page more likely meant than any search; then the engine's;
    /// then the rest of the device's. A command is never first: words typed
    /// into an address bar are rarely a command's name.
    public static func rows(local: [Suggestion], engine: [Suggestion]) -> [Suggestion] {
        guard let top = local.firstIndex(where: { $0.source != .command && $0.typed.first?.lowerBound == 0 }) else {
            return engine + local
        }
        var rest = local
        let first = rest.remove(at: top)
        return [first] + engine + rest
    }

    // MARK: Asking the engine

    /// Where the engine's suggestions for `typed` come from; nil when it
    /// offers none, or when `typed` is an address: an address typed goes
    /// nowhere but where it is sent.
    public static func suggestionsURL(for typed: String, engine: String) -> URL? {
        let text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 100, Address.url(from: text) == nil,
              let template = (Engine(rawValue: engine) ?? Engine.standard).suggestions
        else { return nil }
        return Engine.url(for: text, template: template)
    }

    /// The engine's name, as its rows say where they came from.
    public static func engineName(_ engine: String) -> String {
        (Engine(rawValue: engine) ?? Engine.standard).title
    }

    /// The words in an engine's answer, OpenSearch's JSON:
    /// [typed, [suggestion, …], …]. Nothing for anything else.
    public static func parse(_ data: Data) -> [String] {
        guard let answer = try? JSONSerialization.jsonObject(with: data) as? [Any], answer.count > 1,
              let words = answer[1] as? [Any]
        else { return [] }
        return words.compactMap { $0 as? String }
    }
}
