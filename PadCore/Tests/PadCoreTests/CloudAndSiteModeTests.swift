import XCTest
@testable import PadCore

final class SiteModeTests: XCTestCase {
    func testTheWindowsSizeChooses() {
        // Points: an iPhone 17 Pro either way up, the Duo folded and
        // unfolded (third-party figures), an iPad Pro, a third of one.
        XCTAssertEqual(SiteMode.choose(host: "figma.com", width: 402, height: 874, overrides: [:]), .mobile)
        XCTAssertEqual(SiteMode.choose(host: "figma.com", width: 874, height: 402, overrides: [:]), .mobile)
        XCTAssertEqual(SiteMode.choose(host: "figma.com", width: 466, height: 678, overrides: [:]), .mobile)
        XCTAssertEqual(SiteMode.choose(host: "figma.com", width: 626, height: 890, overrides: [:]), .desktop)
        XCTAssertEqual(SiteMode.choose(host: "figma.com", width: 1032, height: 1376, overrides: [:]), .desktop)
        XCTAssertEqual(SiteMode.choose(host: "figma.com", width: 320, height: 1376, overrides: [:]), .mobile)
    }

    func testASitesOwnChoiceWins() {
        let overrides: [String: SiteMode] = ["figma.com": .desktop, "linear.app": .mobile]
        XCTAssertEqual(SiteMode.choose(host: "www.figma.com", width: 402, height: 874, overrides: overrides), .desktop)
        XCTAssertEqual(SiteMode.choose(host: "linear.app", width: 1032, height: 1376, overrides: overrides), .mobile)
        XCTAssertEqual(SiteMode.choose(host: nil, width: 402, height: 874, overrides: overrides), .mobile)
    }

    func testMobileUserAgentsAreSafarisOwn() {
        XCTAssertEqual(Identity.mobileUserAgent(major: 27, minor: 0, pad: false),
                       "Mozilla/5.0 (iPhone; CPU iPhone OS 27_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/27.0 Mobile/15E148 Safari/604.1")
        XCTAssertEqual(Identity.mobileUserAgent(major: 27, minor: 1, patch: 2, pad: true),
                       "Mozilla/5.0 (iPad; CPU OS 27_1_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/27.1.2 Mobile/15E148 Safari/604.1")
    }

    func testPreferencesFromBeforeSiteModesAndSyncStillRead() throws {
        let old = try XCTUnwrap(#"{"layout":"compact","pageCursors":true}"#.data(using: .utf8))
        let preferences = try JSONDecoder().decode(Preferences.self, from: old)
        XCTAssertEqual(preferences.siteModes, [:])
        XCTAssertFalse(preferences.iCloudSync)
    }
}
