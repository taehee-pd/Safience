import XCTest
@testable import PadCore

final class NewTabClickTests: XCTestCase {
    private func choice(_ kind: NewTabClick.Kind, command: Bool = true, shift: Bool = false, middle: Bool = false,
                        method: String? = "GET", scheme: String? = "https", mainFrame: Bool = true) -> NewTabClick.Choice {
        NewTabClick.choice(kind: kind, command: command, shift: shift, middleButton: middle,
                           method: method, scheme: scheme, mainFrame: mainFrame)
    }

    func testCommandClickOpensBehindAndWithShiftInFront() {
        XCTAssertEqual(choice(.link), .behind)
        XCTAssertEqual(choice(.link, shift: true), .inFront)
        XCTAssertEqual(choice(.link, command: false, middle: true), .behind)
        XCTAssertEqual(choice(.link, command: false), .here, "a plain click stays where it is")
        XCTAssertEqual(choice(.link, command: false, shift: true), .here, "⇧ alone is the page's")
    }

    func testButtonsThatOnlyAskForAPage() {
        XCTAssertEqual(choice(.form), .behind)
        XCTAssertEqual(choice(.form, method: "post"), .here, "sending it twice would do it twice")
        XCTAssertEqual(choice(.script), .behind)
        XCTAssertEqual(choice(.script, mainFrame: false), .here, "a frame's own script isn't the click")
        XCTAssertEqual(choice(.script, method: "POST"), .here, "a new tab would lose what was sent")
    }

    func testNeverHistoryOrAnythingButTheWeb() {
        XCTAssertEqual(choice(.history), .here)
        XCTAssertEqual(choice(.link, scheme: "mailto"), .here)
        XCTAssertEqual(choice(.link, scheme: "javascript"), .here)
        XCTAssertEqual(choice(.link, scheme: nil), .here)
        XCTAssertEqual(choice(.link, scheme: "HTTP"), .behind)
    }
}
