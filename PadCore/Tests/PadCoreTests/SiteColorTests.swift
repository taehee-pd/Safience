import XCTest
@testable import PadCore

final class SiteColorTests: XCTestCase {
    func testAverageOfOpaquePixels() throws {
        // Two pixels, RGBA: pure red and pure blue.
        let color = try XCTUnwrap(SiteColor.average(rgba: [255, 0, 0, 255, 0, 0, 255, 255]))
        XCTAssertEqual(color.red, 0.5, accuracy: 0.01)
        XCTAssertEqual(color.green, 0, accuracy: 0.01)
        XCTAssertEqual(color.blue, 0.5, accuracy: 0.01)
    }

    func testSeeThroughPixelsDontCount() throws {
        let color = try XCTUnwrap(SiteColor.average(rgba: [255, 255, 255, 255, 0, 0, 0, 0]))
        XCTAssertEqual(color.red, 1, accuracy: 0.01)
        XCTAssertNil(SiteColor.average(rgba: [0, 0, 0, 0]))
        XCTAssertNil(SiteColor.average(rgba: []))
        XCTAssertNil(SiteColor.average(rgba: [1, 2, 3]))
    }

    func testDarkColoursGetLightText() {
        XCTAssertTrue(SiteColor(red: 0.12, green: 0.12, blue: 0.12).isDark)      // Figma's dark UI
        XCTAssertTrue(SiteColor(red: 0.29, green: 0.08, blue: 0.29).isDark)      // Slack's aubergine
        XCTAssertFalse(SiteColor(red: 1, green: 1, blue: 1).isDark)
        XCTAssertFalse(SiteColor(red: 0.96, green: 0.96, blue: 0.96).isDark)
        XCTAssertFalse(SiteColor(red: 1, green: 0.8, blue: 0).isDark)            // a bright yellow
    }
}
