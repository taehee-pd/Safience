import Foundation
import Testing
@testable import PadCore

struct ExtensionPresentationTests {
    @Test func siteScopePreservesHostTransportAndPath() {
        #expect(ExtensionAccessDescription.site("https://*.example.com/private/*") == "example.com and its subdomains, pages matching /private/* over HTTPS")
        #expect(ExtensionAccessDescription.site("https://example.com/*") == "example.com over HTTPS")
        #expect(ExtensionAccessDescription.site("<all_urls>") == "All websites")
        #expect(ExtensionAccessDescription.site("http://*/*") == "All HTTP websites")
    }
    @Test func deniedCookiesAreNotPresentedAsGrantedAccess() {
        #expect(ExtensionAccessDescription.capability("cookies").contains("blocked"))
    }
    @Test(arguments: [ExtensionUpdateReport.Outcome.failed, .declined, .deferred])
    func zeroUpdatedIsNotASuccess(outcome: ExtensionUpdateReport.Outcome) {
        let report = ExtensionUpdateReport(entries: [.init(id: "one", name: "One", outcome: .current), .init(id: "two", name: "Two", outcome: outcome)])
        #expect(!report.fullyChecked)
        #expect(!report.summary.contains("up to date"))
    }
    @Test func successfulChecksRequireAnOutcomeForEveryItem() {
        #expect(!ExtensionUpdateReport().fullyChecked)
        #expect(!ExtensionUpdateReport(status: .busy).fullyChecked)
        #expect(ExtensionUpdateReport(entries: [.init(id: "one", name: "One", outcome: .current)]).fullyChecked)
    }
}
