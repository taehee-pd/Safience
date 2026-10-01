import XCTest
@testable import PadCore

final class SignInTests: XCTestCase {
    func testIdentityProvidersAreSignInPages() {
        for address in [
            "https://accounts.google.com/v3/signin/identifier",
            "https://login.microsoftonline.com/common/oauth2/v2.0/authorize",
            "https://appleid.apple.com/auth/authorize",
            "https://acme.okta.com/app/figma/sso/saml",
            "https://acme.onelogin.com/login2",
            "https://id.atlassian.com/login",
        ] {
            XCTAssertTrue(SignIn.isSignInPage(URL(string: address)), address)
        }
    }

    func testToolsOwnSignInPagesByPath() {
        for address in [
            "https://www.figma.com/login",
            "https://www.figma.com/signup?locale=en",
            "https://app.slack.com/signin",
            "https://acme.slack.com/sso/saml/start",
            "https://www.notion.so/login",
            "https://linear.app/login",
            "https://github.com/session",
            "https://example.com/users/sign_in",
            "https://example.com/auth/callback?code=1",
        ] {
            XCTAssertTrue(SignIn.isSignInPage(URL(string: address)), address)
        }
    }

    func testOAuthRequestsAnywhereAreSignInPages() {
        let address = "https://example.com/connect?client_id=abc&redirect_uri=https%3A%2F%2Fapp.example%2Fcb&response_type=code"
        XCTAssertTrue(SignIn.isSignInPage(URL(string: address)))
    }

    func testOrdinaryPagesAreNot() {
        for address in [
            "https://www.figma.com/design/AbC/Login-screen-mockups",
            "https://www.figma.com/files/recents",
            "https://example.com/author/someone",
            "https://example.com/blog/how-to-login-faster",
            "https://mail.google.com/mail/u/0/",
        ] {
            XCTAssertFalse(SignIn.isSignInPage(URL(string: address)), address)
        }
        XCTAssertFalse(SignIn.isSignInPage(nil))
    }

    func testGoogleRefusalIsReadFromTheAddress() {
        // The reason Google puts in the address, base64url inside a message.
        var message = Data([0x0A, 0x14])
        message.append(Data("disallowed_useragent".utf8))
        message.append(Data([0x12, 0x02, 0x41, 0x42]))
        let encoded = message.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let refused = URL(string: "https://accounts.google.com/signin/oauth/error?authError=\(encoded)&client_id=1")
        XCTAssertTrue(SignIn.googleRefused(refused))
        XCTAssertTrue(SignIn.googleRefused(URL(string: "https://accounts.google.com/v3/signin/rejected?continue=x")))
        XCTAssertTrue(SignIn.googleRefused(URL(string: "https://accounts.google.com/signin/rejected")))
    }

    func testOtherGooglePagesAreNotRefusals() {
        XCTAssertFalse(SignIn.googleRefused(URL(string: "https://accounts.google.com/v3/signin/identifier")))
        XCTAssertFalse(SignIn.googleRefused(URL(string: "https://accounts.google.com/signin/oauth/error?authError=bm90aGluZw")))
        XCTAssertFalse(SignIn.googleRefused(URL(string: "https://example.com/signin/rejected")))
    }

    func testAddressBarShowsOnSignInPagesWhateverTheMode() {
        let login = URL(string: "https://www.figma.com/login")
        let design = URL(string: "https://www.figma.com/design/abc")
        XCTAssertTrue(AddressVisibility.shows(mode: .automatic, url: login, passwordField: false, editing: false, failed: false))
        XCTAssertFalse(AddressVisibility.shows(mode: .automatic, url: design, passwordField: false, editing: false, failed: false))
        XCTAssertTrue(AddressVisibility.shows(mode: .automatic, url: design, passwordField: true, editing: false, failed: false))
        XCTAssertTrue(AddressVisibility.shows(mode: .automatic, url: design, passwordField: false, editing: true, failed: false))
        XCTAssertTrue(AddressVisibility.shows(mode: .automatic, url: design, passwordField: false, editing: false, failed: true))
        XCTAssertTrue(AddressVisibility.shows(mode: .automatic, url: nil, passwordField: false, editing: false, failed: false))
        XCTAssertTrue(AddressVisibility.shows(mode: .always, url: design, passwordField: false, editing: false, failed: false))
    }
}
