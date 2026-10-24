import XCTest
@testable import PadCore

final class SettingsRoutingTests: XCTestCase {
    func testEveryOfferedSearchDestinationHasAReachableCategory() {
        for phone in [false, true] {
            for anchor in SettingsAnchor.allCases where anchor.isOffered(phone: phone) {
                XCTAssertTrue(anchor.group.isOffered(padLayout: !phone, keyboard: false, diagnostics: true),
                              "Search result \(anchor) must open a visible Settings category")
            }
        }
    }

    func testShortcutsHaveTheirOwnPageAndAppearWhenAKeyboardConnects() {
        XCTAssertEqual(SettingsAnchor.shortcuts.group, .shortcuts)
        XCTAssertEqual(SettingsAnchor.allCases.filter { $0.group == .shortcuts }, [.shortcuts])
        XCTAssertFalse(SettingsGroup.shortcuts.isOffered(padLayout: false, keyboard: false, diagnostics: false))
        XCTAssertTrue(SettingsGroup.shortcuts.isOffered(padLayout: false, keyboard: true, diagnostics: false))
        XCTAssertTrue(SettingsGroup.input.isOffered(padLayout: false, keyboard: true, diagnostics: false))
    }

    func testDeveloperCategoryRequiresTheDiagnosticsGate() {
        XCTAssertFalse(SettingsGroup.diagnostics.isOffered(padLayout: true, keyboard: true, diagnostics: false))
        XCTAssertTrue(SettingsGroup.diagnostics.isOffered(padLayout: false, keyboard: false, diagnostics: true))
        XCTAssertEqual(SettingsGroup.allCases.filter {
            $0.isOffered(padLayout: true, keyboard: false, diagnostics: false)
        }.count, 6)
    }
}
