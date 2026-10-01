import XCTest
@testable import PadCore

final class ShortcutTests: XCTestCase {
    func testEveryChordIsControlOptionAndNamesOneCommand() {
        XCTAssertTrue(Shortcuts.isUnambiguous)
        for command in Command.allCases {
            let chord = Shortcuts.chord(for: command)
            XCTAssertNotNil(chord, command.rawValue)
            XCTAssertTrue(chord?.label.hasPrefix("⌃⌥") ?? false)
        }
    }

    func testLabels() {
        XCTAssertEqual(Shortcuts.chord(for: .palette)?.label, "⌃⌥K")
        XCTAssertEqual(Shortcuts.chord(for: .reopenTab)?.label, "⌃⌥⇧T")
        XCTAssertEqual(Shortcuts.chord(for: .nextTab)?.label, "⌃⌥→")
        XCTAssertEqual(Shortcuts.tabNumbers.first?.label, "⌃⌥1")
    }

    func testEveryCommandHasATitle() {
        for command in Command.allCases {
            XCTAssertFalse(command.title.isEmpty)
        }
    }
}

final class DestinationTests: XCTestCase {
    func testAddressesGoThere() {
        XCTAssertEqual(Destination.url(for: "figma.com", engine: "google")?.absoluteString, "https://figma.com")
        XCTAssertEqual(Destination.url(for: " https://www.figma.com/files ", engine: "google")?.absoluteString, "https://www.figma.com/files")
        XCTAssertEqual(Destination.url(for: "localhost:3000", engine: "google")?.absoluteString, "http://localhost:3000")
        XCTAssertEqual(Destination.url(for: "0.0.0.0:5173", engine: "google")?.absoluteString, "http://localhost:5173")
    }

    func testWordsAreSearched() {
        XCTAssertEqual(Destination.url(for: "auto layout tips", engine: "google")?.absoluteString,
                       "https://www.google.com/search?q=auto%20layout%20tips")
        XCTAssertEqual(Destination.url(for: "figma", engine: "duckduckgo")?.absoluteString, "https://duckduckgo.com/?q=figma")
        XCTAssertEqual(Destination.url(for: "figma", engine: "nonsense")?.host(), "www.google.com")
        XCTAssertNil(Destination.url(for: "   ", engine: "google"))
    }

    func testEnginesOfferedLeaveOutCustom() {
        let ids = Destination.engines.map(\.id)
        XCTAssertTrue(ids.contains("google"))
        XCTAssertFalse(ids.contains("custom"))
    }

    func testRegistrablePartOfAHost() {
        XCTAssertEqual(Destination.registrable("www.figma.com"), "figma.com")
        XCTAssertEqual(Destination.registrable("accounts.google.com"), "google.com")
        XCTAssertEqual(Destination.registrable("acme.okta.com"), "okta.com")
        XCTAssertEqual(Destination.registrable("news.bbc.co.uk"), "bbc.co.uk")
        XCTAssertEqual(Destination.registrable("someone.github.io"), "someone.github.io")
        XCTAssertEqual(Destination.registrable("localhost"), "localhost")
    }
}

final class PaletteSearchTests: XCTestCase {
    func entry(_ title: String, detail: String = "", keywords: [String] = []) -> PaletteEntry {
        PaletteEntry(id: title, kind: .command(.newTab), title: title, detail: detail, keywords: keywords)
    }

    func testLettersMustAppearInOrder() {
        XCTAssertNotNil(PaletteSearch.score("ffl", in: "Figma: Flows"))
        XCTAssertNil(PaletteSearch.score("lff", in: "Figma: Flows"))
        XCTAssertEqual(PaletteSearch.score("", in: "anything"), 0)
    }

    func testWordStartsAndRunsWin() {
        let ranked = PaletteSearch.rank([entry("Intent"), entry("New Tab")], query: "nt")
        XCTAssertEqual(ranked.first?.title, "New Tab")
        let runs = PaletteSearch.rank([entry("Settings"), entry("Close Tab")], query: "set")
        XCTAssertEqual(runs.first?.title, "Settings")
    }

    func testKeywordsAndDetailsCountForLess() {
        let ranked = PaletteSearch.rank([entry("Reload Page", keywords: ["refresh"]), entry("Refresh Tokens")], query: "refresh")
        XCTAssertEqual(ranked.map(\.title), ["Refresh Tokens", "Reload Page"])
        let detail = PaletteSearch.rank([entry("Design system", detail: "figma.com")], query: "figma")
        XCTAssertEqual(detail.count, 1)
    }

    func testNothingTypedKeepsTheOrderAndTheLimit() {
        let entries = (0..<80).map { entry("Tab \($0)") }
        let ranked = PaletteSearch.rank(entries, query: "  ", limit: 10)
        XCTAssertEqual(ranked.map(\.title), (0..<10).map { "Tab \($0)" })
    }
}
