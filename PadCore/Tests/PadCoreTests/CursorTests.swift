import XCTest
@testable import PadCore

final class CursorTests: XCTestCase {
    // A one-pixel PNG, as bridge.js sends a drawn cursor.
    private let png = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="

    func testAPictureComesWithItsSizeHotspotAndDensity() throws {
        let cursor = PageCursor(message: ["kind": "cursor", "id": 3, "image": png, "width": 32, "height": 32,
                                          "x": 4, "y": 4, "scale": 2])
        guard case .image(let image) = cursor else { return XCTFail("\(cursor)") }
        XCTAssertEqual(image.id, 3)
        XCTAssertEqual(image.width, 32)
        XCTAssertEqual(image.hotspotX, 4)
        XCTAssertEqual(image.hotspotY, 4)
        XCTAssertEqual(image.scale, 2)
        XCTAssertEqual(try XCTUnwrap(image.png).prefix(4), Data([0x89, 0x50, 0x4E, 0x47]))
    }

    func testACursorSeenBeforeComesByItsIdAlone() {
        guard case .image(let image) = PageCursor(message: ["kind": "cursor", "id": 3]) else { return XCTFail() }
        XCTAssertEqual(image.id, 3)
        XCTAssertNil(image.png)
    }

    func testNoneHidesThePointerAutoIsTheSystemsAndOthersAreNamed() {
        XCTAssertEqual(PageCursor(message: ["kind": "cursor", "keyword": "none"]), .hidden)
        for keyword in ["auto", "default", ""] {
            XCTAssertEqual(PageCursor(message: ["kind": "cursor", "keyword": keyword]), .system, keyword)
        }
        for keyword in ["pointer", "text", "crosshair", "ew-resize"] {
            XCTAssertEqual(PageCursor(message: ["kind": "cursor", "keyword": keyword]), .keyword(keyword), keyword)
        }
        XCTAssertEqual(PageCursor(message: ["kind": "cursor", "keyword": "Pointer "]), .keyword("pointer"))
        XCTAssertEqual(PageCursor(message: ["kind": "cursor"]), .system)
    }

    func testWhatCantBeShownIsTheSystemsPointer() {
        // Too big for a cursor, no size, a picture that isn't a PNG, one that doesn't decode.
        XCTAssertEqual(PageCursor(message: ["id": 1, "image": png, "width": 200, "height": 32]), .system)
        XCTAssertEqual(PageCursor(message: ["id": 1, "image": png]), .system)
        XCTAssertEqual(PageCursor(message: ["id": 1, "image": "data:image/svg+xml,<svg/>", "width": 8, "height": 8]), .system)
        XCTAssertEqual(PageCursor(message: ["id": 1, "image": "data:image/png;base64,***", "width": 8, "height": 8]), .system)
    }

    func testTheHotspotStaysOnThePictureAndTheDensityIsSane() {
        guard case .image(let image) = PageCursor(message: ["id": 2, "image": png, "width": 24, "height": 20,
                                                           "x": 40, "y": -3, "scale": 9])
        else { return XCTFail() }
        XCTAssertEqual(image.hotspotX, 24)
        XCTAssertEqual(image.hotspotY, 0)
        XCTAssertEqual(image.scale, 3)
    }

    func testFractionalNumbersFromJavaScriptAreKept() {
        guard case .image(let image) = PageCursor(message: ["id": 5, "image": png, "width": 15.5, "height": 15.5,
                                                           "x": 7.75, "y": 0.5, "scale": 2])
        else { return XCTFail() }
        XCTAssertEqual(image.width, 15.5)
        XCTAssertEqual(image.hotspotX, 7.75)
    }

    func testPageCursorsAreOnUnlessSettingsSayNot() throws {
        XCTAssertTrue(Adapters.standard.bridges.cursors)
        XCTAssertTrue(Adapters.figma.bridges.cursors)
        var preferences = Preferences()
        XCTAssertTrue(preferences.pageCursors)
        XCTAssertTrue(preferences.bridges(for: Adapters.figma).cursors)
        preferences.pageCursors = false
        XCTAssertFalse(preferences.bridges(for: Adapters.figma).cursors)
        let saved = try JSONDecoder().decode(Preferences.self, from: Data("{}".utf8))
        XCTAssertTrue(saved.pageCursors)
    }

    func testOurScriptIsToldWhetherToReadCursors() {
        var bridges = Bridges.standard
        XCTAssertTrue(Scripts.ours(for: Adapters.standard, bridges: bridges).contains(#""cursor":true"#))
        bridges.cursors = false
        XCTAssertTrue(Scripts.ours(for: Adapters.standard, bridges: bridges).contains(#""cursor":false"#))
    }
}
