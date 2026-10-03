import XCTest
@testable import PadCore

final class IdentityTests: XCTestCase {
    func testApplicationNameIsSafaris() {
        XCTAssertEqual(Identity.applicationName(major: 18, minor: 6), "Version/18.6 Safari/605.1.15")
        XCTAssertEqual(Identity.applicationName(major: 26, minor: 0), "Version/26.0 Safari/605.1.15")
        XCTAssertEqual(Identity.applicationName(major: 17, minor: 4, patch: 1), "Version/17.4.1 Safari/605.1.15")
        let system = OperatingSystemVersion(majorVersion: 26, minorVersion: 1, patchVersion: 0)
        XCTAssertEqual(Identity.applicationName(for: system), "Version/26.1 Safari/605.1.15")
    }

    func testWholeUserAgentIsMacSafaris() {
        let name = Identity.applicationName(major: 18, minor: 6)
        XCTAssertEqual(
            Identity.macUserAgent(applicationName: name),
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.6 Safari/605.1.15"
        )
    }
}

final class AdapterTests: XCTestCase {
    func testFigmaIsFirst() {
        XCTAssertEqual(Adapters.all.first?.id, "figma")
    }

    func testFigmaCoversItsHostsOnly() {
        for address in ["https://www.figma.com/files", "https://figma.com/design/abc/Name", "https://embed.figma.com/x", "https://WWW.FIGMA.COM./x"] {
            XCTAssertEqual(Adapters.adapter(for: URL(string: address)).id, "figma", address)
        }
        for address in ["https://notfigma.com/", "https://figma.com.evil.example/", "https://example.com/figma.com"] {
            XCTAssertEqual(Adapters.adapter(for: URL(string: address)).id, "standard", address)
        }
        XCTAssertEqual(Adapters.adapter(for: nil).id, "standard")
    }

    func testHeavyPagesAreDocumentsNotTheFileBrowser() {
        let figma = Adapters.figma
        XCTAssertTrue(figma.isHeavy(URL(string: "https://www.figma.com/design/AbC123/Product?node-id=1-2")))
        XCTAssertTrue(figma.isHeavy(URL(string: "https://www.figma.com/board/AbC123/Workshop")))
        XCTAssertTrue(figma.isHeavy(URL(string: "https://www.figma.com/file/AbC123/Legacy")))
        XCTAssertFalse(figma.isHeavy(URL(string: "https://www.figma.com/files/recents-and-sharing")))
        XCTAssertFalse(figma.isHeavy(URL(string: "https://www.figma.com/")))
        XCTAssertFalse(figma.isHeavy(URL(string: "https://example.com/design/x")))
        XCTAssertFalse(Adapters.standard.isHeavy(URL(string: "https://example.com/design/x")))
    }

    func testEveryBridgeIsOnByDefaultAndKeysAreLeftToTheSystem() {
        let bridges = Adapters.standard.bridges
        XCTAssertTrue(bridges.pinch)
        XCTAssertTrue(bridges.commandZoom)
        XCTAssertEqual(bridges.wheel, .auto)
        XCTAssertTrue(bridges.keys.isEmpty)
        XCTAssertEqual(bridges.pinchFactor, 100)
    }

    func testFigmaFollowsThePinch() {
        // Measured in Safari on a Mac (Validation/figma-ctrl-wheel.js): each
        // ctrl+wheel event zooms Figma by e^(-deltaY / 200).
        let figmaZoom = { (deltaY: Double) in Foundation.exp(-deltaY / 200) }
        let delta = Pinch.wheelDelta(step: 2, factor: Adapters.figma.bridges.pinchFactor)
        XCTAssertEqual(figmaZoom(delta), 2, accuracy: 0.001)
    }

    func testFigmaHidesTouchPointsInThePagesOwnWorld() {
        XCTAssertTrue(Adapters.figma.pageScript.contains("maxTouchPoints"))
        XCTAssertTrue(Adapters.standard.pageScript.isEmpty)
    }
}

final class HandsOffTests: XCTestCase {
    func testGoogleSignInIsHandsOff() {
        XCTAssertTrue(HandsOff.covers(URL(string: "https://accounts.google.com/v3/signin/identifier?flowName=GlifWebSignIn")))
        XCTAssertTrue(HandsOff.covers(URL(string: "https://ACCOUNTS.GOOGLE.COM./o/oauth2/auth")))
        XCTAssertTrue(HandsOff.covers(host: "accounts.google.com"))
    }

    func testOtherGoogleHostsAreNot() {
        XCTAssertFalse(HandsOff.covers(URL(string: "https://mail.google.com/")))
        XCTAssertFalse(HandsOff.covers(URL(string: "https://google.com/")))
        XCTAssertFalse(HandsOff.covers(URL(string: "https://notaccounts.google.com/")))
        XCTAssertFalse(HandsOff.covers(URL(string: "https://accounts.google.com.evil.example/")))
        XCTAssertFalse(HandsOff.covers(nil))
    }

    func testCookiesSentToGoogleSignInAreHandsOff() {
        XCTAssertTrue(HandsOff.covers(cookieDomain: "accounts.google.com"))
        XCTAssertTrue(HandsOff.covers(cookieDomain: ".accounts.google.com"))
        XCTAssertTrue(HandsOff.covers(cookieDomain: ".google.com"))
        XCTAssertTrue(HandsOff.covers(cookieDomain: "google.com"))
        XCTAssertFalse(HandsOff.covers(cookieDomain: "mail.google.com"))
        XCTAssertFalse(HandsOff.covers(cookieDomain: ".figma.com"))
        XCTAssertFalse(HandsOff.covers(cookieDomain: "google.co.uk"))
    }

    func testNativeScrollingOnlyWhereNoBridgeCanRun() {
        XCTAssertTrue(Scrolling.isNative(url: URL(string: "https://accounts.google.com/x"), mimeType: "text/html"))
        XCTAssertTrue(Scrolling.isNative(url: URL(string: "https://example.com/report"), mimeType: "application/pdf"))
        XCTAssertTrue(Scrolling.isNative(url: URL(string: "https://example.com/report.pdf"), mimeType: nil))
        XCTAssertFalse(Scrolling.isNative(url: URL(string: "https://www.figma.com/design/x"), mimeType: "text/html"))
        XCTAssertFalse(Scrolling.isNative(url: URL(string: "https://example.com/report.pdf"), mimeType: "text/html"))
    }
}
