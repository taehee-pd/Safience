import XCTest
@testable import PadCore

final class AutocompleteTests: XCTestCase {
    private func url(_ text: String) -> URL {
        URL(string: text) ?? URL(fileURLWithPath: "/")
    }

    private func bookmark(_ title: String, _ address: String) -> Autocomplete.Candidate {
        Autocomplete.Candidate(id: "bookmark-\(title)", source: .bookmark, action: .open(url(address)), title: title,
                               url: url(address))
    }

    private func tab(_ title: String, _ address: String, pinned: Bool = false, shown: Date = .distantPast) -> Autocomplete.Candidate {
        let id = UUID()
        return Autocomplete.Candidate(id: "tab-\(id)", source: pinned ? .pinnedTab : .tab, action: .tab(id), title: title,
                                      url: url(address), shown: shown)
    }

    private func command(_ command: Command, keys: String = "") -> Autocomplete.Candidate {
        Autocomplete.Candidate(id: "command-\(command.rawValue)", source: .command, action: .command(command),
                               title: command.title, keywords: command.keywords, detail: keys)
    }

    // MARK: Matching

    /// The letters typed start a word, never sit inside one.
    func testLettersStartAWord() {
        XCTAssertEqual(Autocomplete.match("fig", in: "Figma: Flows")?.typed, [0..<3])
        XCTAssertEqual(Autocomplete.match("flo", in: "Figma: Flows")?.typed, [7..<10])
        XCTAssertNil(Autocomplete.match("fig", in: "Configure"))
        XCTAssertEqual(Autocomplete.match("피그", in: "피그마 강좌")?.typed, [0..<2])
    }

    /// Words typed in any order each find the start of one.
    func testWordsInAnyOrder() {
        let found = Autocomplete.match("guide auto", in: "Auto Layout Guide")
        XCTAssertEqual(found?.fit, .words)
        XCTAssertEqual(found?.typed, [0..<4, 12..<17])
        XCTAssertNil(Autocomplete.match("guide zoom", in: "Auto Layout Guide"))
    }

    // MARK: The device's rows

    /// A page whose address the letters start is offered by its address,
    /// completed, with its title under it.
    func testAddressIsCompleted() {
        let rows = Autocomplete.local([bookmark("Figma", "https://www.figma.com/files/recent")], query: "fig")
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.phrase, "figma.com/files/recent")
        XCTAssertEqual(rows.first?.typed, [0..<3])
        XCTAssertEqual(rows.first?.detail, "Figma")
        XCTAssertEqual(rows.first?.source, .bookmark)
        XCTAssertEqual(rows.first?.source.label, "Bookmark")
    }

    /// Otherwise by its title, with its address under it.
    func testTitleWhenTheAddressDoesNotStartWithIt() {
        let rows = Autocomplete.local([tab("Auto Layout Guide", "https://example.com/al")], query: "lay")
        XCTAssertEqual(rows.first?.phrase, "Auto Layout Guide")
        XCTAssertEqual(rows.first?.typed, [5..<8])
        XCTAssertEqual(rows.first?.detail, "example.com/al")
        XCTAssertEqual(rows.first?.source.label, "Open Tab")
    }

    /// One row a page: the open tab, rather than its bookmark.
    func testOpenTabBeforeItsBookmark() {
        let rows = Autocomplete.local([bookmark("Figma", "https://figma.com"), tab("Figma", "https://figma.com/")],
                                      query: "fig")
        XCTAssertEqual(rows.map(\.source), [.tab])
    }

    /// Pinned tabs say so; the tab seen last comes first.
    func testPinnedTabsAndRecency() {
        let now = Date()
        let rows = Autocomplete.local([
            tab("Figma Files", "https://figma.com/files", shown: now.addingTimeInterval(-60)),
            tab("Figma Community", "https://figma.com/community", pinned: true, shown: now),
        ], query: "figma")
        XCTAssertEqual(rows.map(\.source), [.pinnedTab, .tab])
        XCTAssertEqual(rows.first?.source.label, "Pinned Tab")
    }

    /// Commands need two letters, are found by their other words too, and
    /// take at most two rows.
    func testCommands() {
        let commands = [command(.newTab, keys: "⌘T"), command(.newSpace), command(.newWindow), command(.reload)]
        XCTAssertTrue(Autocomplete.local(commands, query: "n").isEmpty)
        let new = Autocomplete.local(commands, query: "new")
        XCTAssertEqual(new.count, 2)
        XCTAssertEqual(new.first?.phrase, "New Tab")
        XCTAssertEqual(new.first?.detail, "⌘T")
        XCTAssertEqual(new.first?.source.label, "Command")
        let refresh = Autocomplete.local(commands, query: "refresh")
        XCTAssertEqual(refresh.first?.phrase, "Reload Page")
        XCTAssertEqual(refresh.first?.typed, [])
        XCTAssertEqual(refresh.first?.action, .command(.reload))
    }

    func testNothingTypedOffersNothing() {
        XCTAssertTrue(Autocomplete.local([bookmark("Figma", "https://figma.com")], query: "  ").isEmpty)
    }

    // MARK: The engine's rows and the order

    /// The words as typed are left out, and repeats; four at most.
    func testEngineRows() {
        let words = ["figma", "Figma login", "figma login", "figma jam", "figma fonts", "figma ai", "figma pricing"]
        let rows = Autocomplete.engine(words, query: "figma", engine: "Google")
        XCTAssertEqual(rows.map(\.phrase), ["Figma login", "figma jam", "figma fonts", "figma ai"])
        XCTAssertEqual(rows.first?.typed, [0..<5])
        XCTAssertEqual(rows.first?.action, .go("Figma login"))
        XCTAssertEqual(rows.first?.source.label, "Google")
    }

    /// A page the letters start comes first, then the engine's words, then
    /// the rest; a command is never first.
    func testOrder() {
        let figma = Suggestion(id: "b", source: .bookmark, action: .open(url("https://figma.com")), phrase: "figma.com",
                               typed: [0..<3])
        let guide = Suggestion(id: "t", source: .tab, action: .open(url("https://example.com")),
                               phrase: "Auto Figma Guide", typed: [5..<8])
        let new = Suggestion(id: "c", source: .command, action: .command(.newTab), phrase: "New Tab", typed: [0..<3])
        let search = Suggestion(id: "e", source: .engine("Google"), action: .go("figma login"), phrase: "figma login",
                                typed: [0..<3])
        XCTAssertEqual(Autocomplete.rows(local: [figma, guide], engine: [search]).map(\.id), ["b", "e", "t"])
        XCTAssertEqual(Autocomplete.rows(local: [guide], engine: [search]).map(\.id), ["e", "t"])
        XCTAssertEqual(Autocomplete.rows(local: [new, figma], engine: [search]).map(\.id), ["b", "e", "c"])
    }

    // MARK: Asking the engine

    func testSuggestionsAddress() {
        XCTAssertEqual(Autocomplete.suggestionsURL(for: "auto layout", engine: "google")?.absoluteString,
                       "https://suggestqueries.google.com/complete/search?client=firefox&ie=utf-8&oe=utf-8&q=auto%20layout")
        XCTAssertEqual(Autocomplete.suggestionsURL(for: "피그마", engine: "google")?.absoluteString,
                       "https://suggestqueries.google.com/complete/search?client=firefox&ie=utf-8&oe=utf-8&q=%ED%94%BC%EA%B7%B8%EB%A7%88")
        XCTAssertEqual(Autocomplete.suggestionsURL(for: "figma", engine: "duckduckgo")?.absoluteString,
                       "https://duckduckgo.com/ac/?type=list&q=figma")
        XCTAssertEqual(Autocomplete.suggestionsURL(for: "figma", engine: "bing")?.absoluteString,
                       "https://api.bing.com/osjson.aspx?query=figma")
    }

    /// An address typed never goes to the engine, nor anything to an engine without suggestions.
    func testAddressesAreNotSent() {
        XCTAssertNil(Autocomplete.suggestionsURL(for: "figma.com", engine: "google"))
        XCTAssertNil(Autocomplete.suggestionsURL(for: "github.com/team/private-repo", engine: "google"))
        XCTAssertNil(Autocomplete.suggestionsURL(for: "localhost:3000", engine: "google"))
        XCTAssertNil(Autocomplete.suggestionsURL(for: "   ", engine: "google"))
        XCTAssertNil(Autocomplete.suggestionsURL(for: "figma", engine: "kagi"))
    }

    func testEngineName() {
        XCTAssertEqual(Autocomplete.engineName("bing"), "Bing")
        XCTAssertEqual(Autocomplete.engineName("nonsense"), "Google")
    }

    func testParse() {
        XCTAssertEqual(Autocomplete.parse(Data(#"["fig",["figma","figma login"]]"#.utf8)), ["figma", "figma login"])
        XCTAssertEqual(Autocomplete.parse(Data(#"["피그",["피그마"],[],{}]"#.utf8)), ["피그마"])
        XCTAssertEqual(Autocomplete.parse(Data("not json".utf8)), [])
        XCTAssertEqual(Autocomplete.parse(Data(#"{"q":"fig"}"#.utf8)), [])
    }

    /// On unless turned off, settings saved before it included.
    func testSuggestionsSettingDefaultsToOn() throws {
        XCTAssertTrue(try JSONDecoder().decode(Preferences.self, from: Data("{}".utf8)).searchSuggestions)
        XCTAssertFalse(try JSONDecoder().decode(Preferences.self, from: Data(#"{"searchSuggestions":false}"#.utf8)).searchSuggestions)
    }

    // MARK: Apple Intelligence

    /// The letters do the work alone for fewer than three of them, and for an address.
    func testIntentQuestionWaitsForThreeLettersAndSkipsAddresses() {
        let list = [bookmark("Figma", "https://figma.com")]
        XCTAssertNil(Autocomplete.intentQuestion(query: "fi", candidates: list))
        XCTAssertNil(Autocomplete.intentQuestion(query: "figma.com", candidates: list))
        XCTAssertNotNil(Autocomplete.intentQuestion(query: "design tool", candidates: list))
    }

    /// The pages seen last first, one line a page with its site, then every
    /// command, numbered from 1.
    func testIntentQuestionLists() throws {
        let now = Date()
        let list = [
            bookmark("Linear", "https://linear.app"),
            tab("Onboarding flows", "https://www.figma.com/file/abc", shown: now),
            tab("Older", "https://example.com", shown: now.addingTimeInterval(-60)),
            bookmark("Figma file", "https://www.figma.com/file/abc"),
            command(.closeTab),
        ]
        let question = try XCTUnwrap(Autocomplete.intentQuestion(query: "close everything", candidates: list))
        XCTAssertEqual(question.prompt, """
            Typed: close everything

            1. Open tab: Onboarding flows (figma.com)
            2. Open tab: Older (example.com)
            3. Bookmark: Linear (linear.app)
            4. Command: Close Tab
            """)
        XCTAssertEqual(question.candidates.map(\.title), ["Onboarding flows", "Older", "Linear", "Close Tab"])
    }

    /// The numbers the model names become rows that still say where they
    /// came from, marked as found by meaning; one already shown, one not in
    /// the list, and any after the third are passed over.
    func testIntentRows() throws {
        let list = [
            tab("Onboarding flows", "https://figma.com/file/abc", shown: Date()),
            bookmark("Linear", "https://linear.app"),
            command(.closeTab, keys: "⌘W"),
            bookmark("Notion", "https://notion.so"),
            bookmark("Slack", "https://slack.com"),
        ]
        let question = try XCTUnwrap(Autocomplete.intentQuestion(query: "close everything", candidates: list))
        XCTAssertEqual(question.candidates.map(\.title), ["Onboarding flows", "Linear", "Notion", "Slack", "Close Tab"])
        let shown = Autocomplete.local([bookmark("Linear", "https://linear.app")], query: "lin")
        let answer = Autocomplete.IntentAnswer(
            picks: [5, 2, 0, 99, 1, 3, 4],
            searches: ["close everything", "close all tabs chrome", "Close all tabs chrome", "", "close tabs shortcut"]
        )
        let found = Autocomplete.intentRows(answer, to: question, shown: shown)
        XCTAssertEqual(found.meant.map(\.phrase), ["Close Tab", "Onboarding flows", "Notion"])
        XCTAssertEqual(found.meant.map(\.source), [.command, .tab, .bookmark])
        XCTAssertTrue(found.meant.allSatisfy(\.byMeaning))
        XCTAssertEqual(found.meant.first?.detail, "⌘W")
        XCTAssertEqual(found.meant.dropFirst().first?.detail, "figma.com/file/abc")
        XCTAssertEqual(found.searches.map(\.phrase), ["close all tabs chrome", "close tabs shortcut"])
        XCTAssertEqual(found.searches.first?.source.label, "Apple Intelligence")
        XCTAssertEqual(found.searches.first?.action, .go("close all tabs chrome"))
    }

    /// What the model found comes after the page the letters start, before the searches.
    func testOrderWithWhatWasMeant() {
        let figma = Suggestion(id: "b", source: .bookmark, action: .open(url("https://figma.com")), phrase: "figma.com",
                               typed: [0..<3])
        let guide = Suggestion(id: "t", source: .tab, action: .open(url("https://example.com")),
                               phrase: "Auto Figma Guide", typed: [5..<8])
        let meant = Suggestion(id: "m", source: .command, action: .command(.closeTab), phrase: "Close Tab", typed: [],
                               byMeaning: true)
        let search = Suggestion(id: "e", source: .engine("Google"), action: .go("figma login"), phrase: "figma login",
                                typed: [0..<3])
        XCTAssertEqual(Autocomplete.rows(local: [figma, guide], meant: [meant], engine: [search]).map(\.id),
                       ["b", "m", "e", "t"])
        XCTAssertEqual(Autocomplete.rows(local: [guide], meant: [meant], engine: [search]).map(\.id), ["m", "e", "t"])
    }

    func testIntelligenceSettingDefaultsToOn() throws {
        XCTAssertTrue(try JSONDecoder().decode(Preferences.self, from: Data("{}".utf8)).intelligence)
        XCTAssertFalse(try JSONDecoder().decode(Preferences.self, from: Data(#"{"intelligence":false}"#.utf8)).intelligence)
    }
}
