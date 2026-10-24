import Foundation
import Testing
@testable import PadCore

struct PageLoadStateTests {
    @Test func aFailedProvisionalAddressSurvivesThePreviousDocumentReturning() {
        let previous = URL(string: "https://example.com/old")!
        let attempted = URL(string: "https://missing.example/new")!
        var state = PageLoadState()
        state.begin(attempted); state.fail(nil)
        #expect(state.displayURL(current: previous) == attempted)
        #expect(state.failed == attempted)
        state.begin(previous)
        #expect(state.failed == nil)
        state.commit()
        #expect(state.displayURL(current: previous) == previous)
    }
    @Test func aRedirectFailureUsesItsActualFailingAddress() {
        var state = PageLoadState()
        state.begin(URL(string: "https://example.com/start"))
        let redirected = URL(string: "https://signin.example/end")!
        state.fail(redirected)
        #expect(state.displayURL(current: nil) == redirected)
    }
    @Test func recoveryExplainsConnectionAddressAndSecurityFailures() {
        let offline = PageLoadFailure.message(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        let address = PageLoadFailure.message(domain: NSURLErrorDomain, code: NSURLErrorCannotFindHost)
        let certificate = PageLoadFailure.message(domain: NSURLErrorDomain, code: NSURLErrorServerCertificateUntrusted)
        #expect(offline.contains("connection"))
        #expect(address.contains("address"))
        #expect(certificate.contains("verified"))
        #expect(!certificate.contains("continue"))
        #expect(Set([offline, address, certificate]).count == 3)
    }
}
