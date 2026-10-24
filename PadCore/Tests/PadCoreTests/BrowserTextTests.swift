import Foundation
import Testing
@testable import PadCore

@Suite("Localization resources")
struct BrowserTextTests {
    @Test func countUsesPluralRules() {
        #expect(BrowserText.tabCount(0) == "0 tabs")
        #expect(BrowserText.tabCount(1) == "1 tab")
        #expect(BrowserText.tabCount(2) == "2 tabs")
    }

    @Test func koreanResourcesArePackagedSeparatelyFromUserContent() throws {
        let path = try #require(BrowserText.resourceBundle.path(forResource: "ko", ofType: "lproj"))
        let korean = try #require(Bundle(path: path))
        #expect(korean.localizedString(forKey: "New Tab", value: nil, table: nil) == "새 탭")
        #expect(korean.localizedString(forKey: "Workspace Unavailable", value: nil, table: nil) == "작업 공간을 사용할 수 없음")
        #expect(korean.localizedString(forKey: "Synthetic client name", value: nil, table: nil) == "Synthetic client name")
    }
}
