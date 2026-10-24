import CoreGraphics
import XCTest
@testable import PadCore

final class PeekTests: XCTestCase {
    private func peeks(to address: String, from: URL? = URL(string: "https://www.figma.com/files/recent"),
                       kind: NewTabClick.Kind = .link, method: String? = "GET", mainFrame: Bool = true) -> Bool {
        Peek.opensFromPinned(from: from, to: URL(string: address), kind: kind, method: method, mainFrame: mainFrame)
    }

    func testALinkToAnotherSiteFromAPinnedTabPeeks() {
        XCTAssertTrue(peeks(to: "https://github.com/figma/plugin-samples"))
        XCTAssertTrue(peeks(to: "http://example.com/"))
    }

    func testTheTabsOwnSiteStaysInTheTab() {
        XCTAssertFalse(peeks(to: "https://www.figma.com/design/abc"), "the same host")
        XCTAssertFalse(peeks(to: "https://help.figma.com/hc/en-us"), "another host of the same site")
        XCTAssertFalse(peeks(to: "https://FIGMA.com/"), "a host's case is no other site")
        let shop = URL(string: "https://shop.example.co.uk/basket")
        XCTAssertFalse(peeks(to: "https://www.example.co.uk/", from: shop), "a two-level suffix is one site")
        XCTAssertTrue(peeks(to: "https://www.other.co.uk/", from: shop))
    }

    func testOnlyAClickOnALinkThatAsksForAPage() {
        XCTAssertFalse(peeks(to: "https://github.com/", kind: .form), "a form goes where it was sent")
        XCTAssertFalse(peeks(to: "https://github.com/", kind: .script), "the page's own script moving it is not a click")
        XCTAssertFalse(peeks(to: "https://github.com/", kind: .history))
        XCTAssertFalse(peeks(to: "https://github.com/", method: "POST"))
        XCTAssertTrue(peeks(to: "https://github.com/", method: nil), "a link names no method: GET")
        XCTAssertFalse(peeks(to: "https://github.com/", mainFrame: false), "a frame's link moves the frame")
    }

    func testNeverASignInOrAnythingButTheWeb() {
        XCTAssertFalse(peeks(to: "https://accounts.google.com/o/oauth2/auth?client_id=1&redirect_uri=x"),
                       "a sign-in comes back to the tab that started it")
        XCTAssertFalse(peeks(to: "https://acme.okta.com/app/figma/sso/saml"))
        XCTAssertFalse(peeks(to: "https://github.com/", from: URL(string: "https://www.figma.com/login")),
                       "a link out of a sign-in page is the sign-in's next step")
        XCTAssertFalse(peeks(to: "mailto:someone@example.com"))
        XCTAssertFalse(peeks(to: "about:blank"))
        XCTAssertFalse(peeks(to: "https://github.com/", from: nil), "a tab that is nowhere has no site to leave")
    }

    func testAPopUpIsTheSizeItAskedForWithinTheRoom() {
        let room = CGSize(width: 1200, height: 800)
        XCTAssertEqual(Peek.size(width: 500, height: 600, within: room), CGSize(width: 500, height: 600))
        XCTAssertEqual(Peek.size(width: 3000, height: 2000, within: room), room, "never more than the card has")
        XCTAssertEqual(Peek.size(width: 50, height: 50, within: room), Peek.smallest)
        XCTAssertEqual(Peek.size(width: 480.4, height: 640.6, within: room), CGSize(width: 480, height: 641))
    }

    func testALinkIsNearlyTheRoomAndNoWiderThanAPageOfReading() {
        XCTAssertEqual(Peek.size(width: nil, height: nil, within: CGSize(width: 1000, height: 800)),
                       CGSize(width: 1000 - 2 * Peek.margin, height: 800 - 2 * Peek.margin))
        XCTAssertEqual(Peek.size(width: nil, height: nil, within: CGSize(width: 2400, height: 1400)).width, Peek.widest)
        XCTAssertEqual(Peek.size(width: 600, height: nil, within: CGSize(width: 1000, height: 800)),
                       Peek.size(width: nil, height: nil, within: CGSize(width: 1000, height: 800)), "one side alone is no size")
        XCTAssertEqual(Peek.size(width: nil, height: nil, within: CGSize(width: 380, height: 300)), Peek.smallest,
                       "a small card's Peek is the smallest, not its room less the margins")
        XCTAssertEqual(Peek.size(width: nil, height: nil, within: CGSize(width: 200, height: 100)), CGSize(width: 200, height: 100),
                       "a tiny card's Peek is the card, its buttons on it")
        XCTAssertEqual(Peek.size(width: 500, height: 600, within: CGSize(width: 200, height: 150)), CGSize(width: 200, height: 150))
        XCTAssertEqual(Peek.size(width: nil, height: nil, within: CGSize(width: -20, height: 0)), CGSize(width: 1, height: 1),
                       "a card with no room left still gets a size")
    }

    func testATabCanBeMadeForAPageThatIsAlreadyLive() throws {
        var w = Workspace.onFigma()
        let space = w.spaces[0].id
        let first = try XCTUnwrap(w.spaces[0].selected)
        let live = UUID()
        XCTAssertEqual(w.openTab(URL(string: "https://github.com/"), in: space, after: first, id: live), live)
        XCTAssertEqual(w.spaces[0].selected, live)
        XCTAssertEqual(w.tab(live)?.url, URL(string: "https://github.com/"))
        XCTAssertNil(w.openTab(nil, in: space, id: live), "an id a tab has already is no new tab's")
        XCTAssertEqual(w.spaces[0].tabs.filter { $0.id == live }.count, 1)
    }

    func testPeekAndLittleWindowsAreOnUntilTurnedOff() throws {
        let fresh = Preferences()
        XCTAssertTrue(fresh.peekFromPinnedTabs)
        XCTAssertEqual(fresh.linksFromApps, .littleWindow)
        let old = try JSONDecoder().decode(Preferences.self, from: Data(#"{"handoff":true}"#.utf8))
        XCTAssertTrue(old.peekFromPinnedTabs, "settings saved before Peek take its default")
        XCTAssertEqual(old.linksFromApps, .littleWindow)
        var changed = Preferences()
        changed.peekFromPinnedTabs = false
        changed.linksFromApps = .newTab
        let again = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(changed))
        XCTAssertFalse(again.peekFromPinnedTabs)
        XCTAssertEqual(again.linksFromApps, .newTab)
    }
}
