import PadCore
import SwiftUI
import UIKit

/// What the address bar offers as an address is typed: the space's tabs,
/// pinned tabs and bookmarks, the browser's commands, and the search
/// engine's suggestions (Autocomplete), each row saying which it is. ↑ and ↓
/// choose a row and Return takes it; with none chosen, Return sends what was
/// typed, as before.
@MainActor
final class Suggestions: ObservableObject {
    @Published private(set) var rows: [Suggestion] = []
    /// The row ↑ and ↓ have chosen; nil for the text as typed.
    @Published private(set) var selection: Int?
    /// What the field held as typing began: the page's address, not a query.
    private var start = ""
    private var query = ""
    private var local: [Suggestion] = []
    /// The engine's words, and the text they answered.
    private var answer: (query: String, words: [String]) = ("", [])
    private var asking: Task<Void, Never>?

    var selected: Suggestion? {
        selection.flatMap { rows.indices.contains($0) ? rows[$0] : nil }
    }

    /// Typing starts, in a field holding the page's address.
    func begin(at url: URL?) {
        end()
        start = url.map(Destination.editable) ?? ""
    }

    /// What the field holds now, the letters still being composed included.
    func typed(_ text: String, in window: WindowModel) {
        // The field says what it holds once more as Return sends it; by
        // then typing is over.
        guard window.editingAddress, text != query else { return }
        query = text
        selection = nil
        guard text != start, !text.trimmingCharacters(in: .whitespaces).isEmpty else {
            asking?.cancel()
            local = []
            answer = ("", [])
            if !rows.isEmpty { rows = [] }
            return
        }
        local = Autocomplete.local(candidates(for: window), query: text)
        ask(text)
        show()
    }

    /// Typing is over, sent or not.
    func end() {
        asking?.cancel()
        asking = nil
        start = ""
        query = ""
        local = []
        answer = ("", [])
        selection = nil
        if !rows.isEmpty { rows = [] }
    }

    /// ↓ from the field goes to the first row, ↑ from the first row back to the field.
    func move(_ by: Int) {
        guard !rows.isEmpty else { return }
        guard let index = selection else {
            if by > 0 { selection = 0 }
            return
        }
        let next = index + by
        selection = next < 0 ? nil : min(next, rows.count - 1)
    }

    private func show() {
        // The engine's words for a few letters fewer stay while they still
        // fit, so the rows don't empty and fill again with every letter.
        let typed = query.trimmingCharacters(in: .whitespaces).lowercased()
        let words = answer.query == query ? answer.words : answer.words.filter { $0.lowercased().hasPrefix(typed) }
        let engine = Autocomplete.engine(words, query: query,
                                         engine: Autocomplete.engineName(Session.shared.preferences.engine))
        rows = Autocomplete.rows(local: local, engine: engine)
    }

    /// The engine's suggestions for `text`, when Settings has them on and
    /// the engine offers them. Never for an address (suggestionsURL).
    private func ask(_ text: String) {
        asking?.cancel()
        let preferences = Session.shared.preferences
        guard preferences.searchSuggestions,
              let url = Autocomplete.suggestionsURL(for: text, engine: preferences.engine)
        else {
            answer = ("", [])
            return
        }
        asking = Task { [weak self] in
            // A moment first, so a word typed quickly asks once, not once a letter.
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, let reply = try? await Suggestions.session.data(from: url),
                  (reply.1 as? HTTPURLResponse)?.statusCode == 200,
                  !Task.isCancelled, let self, self.query == text
            else { return }
            answer = (text, Autocomplete.parse(reply.0))
            show()
        }
    }

    /// No cookies and nothing kept: the engine hears the words, and nothing
    /// about who typed them.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 5
        return URLSession(configuration: configuration)
    }()

    /// The window's space's tabs that have somewhere to go, its bookmarks,
    /// and the commands this device has.
    private func candidates(for window: WindowModel) -> [Autocomplete.Candidate] {
        let workspace = Session.shared.workspace
        var list: [Autocomplete.Candidate] = []
        if let space = workspace.space(window.spaceID) {
            for tab in space.tabs where tab.id != window.tabID {
                guard let url = tab.url ?? tab.pinned else { continue }
                list.append(Autocomplete.Candidate(
                    id: "tab-\(tab.id)", source: tab.isPinned ? .pinnedTab : .tab, action: .tab(tab.id),
                    title: tab.label, url: url, shown: tab.shown
                ))
            }
            for bookmark in space.bookmarks.flatMap(\.links) {
                guard let url = bookmark.url else { continue }
                list.append(Autocomplete.Candidate(
                    id: "bookmark-\(bookmark.id)", source: .bookmark, action: .open(url), title: bookmark.label, url: url
                ))
            }
        }
        // Not the palette or Open Address: the field is open already.
        for command in Command.allCases where command != .palette && command != .address && Device.offers(command) {
            list.append(Autocomplete.Candidate(
                id: "command-\(command.rawValue)", source: .command, action: .command(command), title: command.title,
                keywords: command.keywords, detail: Device.keys(for: command) ?? ""
            ))
        }
        return list
    }
}

/// The rows, under the field on iPad and over the bar on a phone, in the
/// palette's see-through material. The browser sizes it to its rows
/// (Browser.placeSuggestions); it scrolls when the room is less.
struct SuggestionList: View {
    @ObservedObject var suggestions: Suggestions
    let choose: (Suggestion) -> Void

    static let rowHeight: CGFloat = 44
    static let inset: CGFloat = 6

    /// The list's height for `rows` rows, before the room it has is counted.
    static func height(rows: Int) -> CGFloat {
        CGFloat(rows) * rowHeight + 2 * inset
    }

    var body: some View {
        let rows = suggestions.rows
        ScrollViewReader { scroller in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        SuggestionRow(row: row, selected: index == suggestions.selection)
                            .id(row.id)
                            .onTapGesture { choose(row) }
                    }
                }
                .padding(Self.inset)
            }
            .scrollBounceBehavior(.basedOnSize)
            .onChange(of: suggestions.selection) { _, index in
                if let index, rows.indices.contains(index) { scroller.scrollTo(rows[index].id) }
            }
        }
        // As the palette's: the system's material, solid by itself under
        // Reduce Transparency, with the label colour at an opacity on it
        // rather than .secondary, which drew nothing in a scrolling list
        // (PaletteView).
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Suggestions")
    }
}

/// A row: the page's icon, or a command's or a search's symbol; the phrase,
/// what was typed in the label colour and what the row completes in bold;
/// what else there is to say under it; and where it came from at the end.
private struct SuggestionRow: View {
    let row: Suggestion
    let selected: Bool

    var body: some View {
        HStack(spacing: 10) {
            icon
                .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 1) {
                phrase
                    .font(.system(size: 14))
                    .lineLimit(1)
                if !row.detail.isEmpty {
                    Text(row.detail)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.primary.opacity(0.5))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 8)
            SourceTag(source: row.source)
        }
        .padding(.horizontal, 10)
        .frame(height: SuggestionList.rowHeight)
        .background(selected ? Color.primary.opacity(0.1) : Color.clear,
                    in: RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous))
        .contentShape(Rectangle())
        .hoverEffect(.highlight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.phrase), \(row.source.label)")
        .accessibilityValue(row.detail)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder private var icon: some View {
        switch row.source {
        case .tab, .pinnedTab, .bookmark:
            SiteIconView(url: row.url, size: 18)
        case .command:
            Image(systemName: "command")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.5))
        case .engine:
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.5))
        }
    }

    /// The typed letters plain, the rest of the phrase in bold: what the row
    /// adds to what was typed.
    private var phrase: Text {
        let letters = Array(row.phrase)
        let typed = row.typed
            .map { $0.clamped(to: 0..<letters.count) }
            .filter { !$0.isEmpty }
            .sorted { $0.lowerBound < $1.lowerBound }
        var parts: [Text] = []
        var at = 0
        for range in typed where range.lowerBound >= at {
            parts.append(part(letters[at..<range.lowerBound], typed: false))
            parts.append(part(letters[range], typed: true))
            at = range.upperBound
        }
        parts.append(part(letters[at...], typed: false))
        return parts.reduce(Text(verbatim: "")) { Text("\($0)\($1)") }
    }

    private func part(_ letters: ArraySlice<Character>, typed: Bool) -> Text {
        Text(verbatim: String(letters))
            .fontWeight(typed ? .regular : .semibold)
            .foregroundStyle(typed ? Color.primary.opacity(0.7) : Color.primary)
    }
}

/// Where a row came from, in a small capsule at its end.
private struct SourceTag: View {
    let source: Suggestion.Source

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
            Text(source.label)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(Color.primary.opacity(0.55))
        .lineLimit(1)
        .padding(.horizontal, 7)
        .frame(height: 20)
        .background(Color.primary.opacity(0.07), in: Capsule())
        .fixedSize()
        .accessibilityHidden(true)
    }

    private var symbol: String {
        switch source {
        case .tab: return "square.on.square"
        case .pinnedTab: return "pin.fill"
        case .bookmark: return "star.fill"
        case .command: return "command"
        case .engine: return "magnifyingglass"
        }
    }
}
