import Foundation

/// One row of the command palette.
public struct PaletteEntry: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case tab(UUID, space: UUID)
        case space(UUID)
        case command(Command)
        case open(URL)
        case search(URL)
    }

    public var id: String
    public var kind: Kind
    public var title: String
    public var detail: String
    /// Searched as well as the title, with less weight.
    public var keywords: [String]

    public init(id: String, kind: Kind, title: String, detail: String = "", keywords: [String] = []) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.keywords = keywords
    }
}

/// The palette's matching: the typed letters in order, anywhere in a title,
/// scored so that the start of a word and letters that run together count
/// most. "ffl" finds "Figma: Flows"; "nt" finds New Tab before "Intent".
public enum PaletteSearch {
    /// Nil when the letters of `query` don't all appear in order in `text`.
    public static func score(_ query: String, in text: String) -> Int? {
        let needle = Array(query.lowercased().filter { !$0.isWhitespace })
        guard !needle.isEmpty else { return 0 }
        let hay = Array(text.lowercased())
        var score = 0
        var at = 0
        var previous = -2
        for letter in needle {
            guard let found = hay[at...].firstIndex(of: letter) else { return nil }
            let wordStart = found == 0 || !(hay[found - 1].isLetter || hay[found - 1].isNumber)
            score += 1
            if wordStart { score += 8 }
            if found == previous + 1 { score += 5 }
            if found == 0 { score += 3 }
            previous = found
            at = found + 1
        }
        // A shorter title holding the same letters is the closer match.
        return score * 100 - hay.count
    }

    /// Matching entries, best first, at most `limit` of them. With nothing
    /// typed, the entries in the order given.
    public static func rank(_ entries: [PaletteEntry], query: String, limit: Int = 50) -> [PaletteEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Array(entries.prefix(limit)) }
        let scored: [(PaletteEntry, Int, Int)] = entries.enumerated().compactMap { index, entry in
            let title = score(trimmed, in: entry.title)
            let other = ([entry.detail] + entry.keywords).compactMap { score(trimmed, in: $0) }.max().map { $0 / 2 }
            guard let best = [title, other].compactMap({ $0 }).max() else { return nil }
            return (entry, best, index)
        }
        return scored
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.2 < $1.2 }
            .prefix(limit)
            .map(\.0)
    }
}
