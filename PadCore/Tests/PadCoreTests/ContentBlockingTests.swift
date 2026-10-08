import XCTest
@testable import PadCore
#if canImport(WebKit)
import WebKit
#endif

final class ContentBlockingTests: XCTestCase {
    private func network(_ text: String) -> [BlockingRule] {
        FilterConverter.convert(text).network
    }

    /// The url-filter as a regular expression, matched case-insensitively as WebKit does.
    private func matches(_ filter: String, _ url: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: filter, options: [.caseInsensitive]) else { return false }
        return regex.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)) != nil
    }

    func testADomainAnchorTakesTheSiteAndItsSubdomainsOnly() throws {
        let rule = try XCTUnwrap(network("||ads.example.com^").first)
        XCTAssertEqual(rule.action, .block)
        let filter = rule.trigger.urlFilter
        XCTAssertTrue(matches(filter, "https://ads.example.com/banner.png"))
        XCTAssertTrue(matches(filter, "https://cdn.ads.example.com:8443/x"))
        // WebKit matches the address as it writes it: a path after the host, always.
        XCTAssertTrue(matches(filter, "https://ads.example.com/"))
        XCTAssertTrue(matches(filter, "http://ads.example.com/?id=1"))
        XCTAssertFalse(matches(filter, "https://notads.example.com/"))
        XCTAssertFalse(matches(filter, "https://ads.example.community/"))
        XCTAssertFalse(matches(filter, "https://example.com/?u=https://ads.example.com/"))
    }

    func testSeparatorsWildcardsAndAnchors() throws {
        // Ending in a separator, away from a host: a separator, or the end.
        let ends = network("/banner/*/img^").map(\.trigger.urlFilter)
        XCTAssertEqual(ends.count, 2)
        let either = { (url: String) in ends.contains { self.matches($0, url) } }
        XCTAssertTrue(either("https://site.test/banner/big/img?x=1"))
        XCTAssertTrue(either("https://site.test/banner/big/img"))
        XCTAssertFalse(either("https://site.test/banner/big/imgs"))
        let middle = try XCTUnwrap(network("/ad^frame").first?.trigger.urlFilter)
        XCTAssertTrue(matches(middle, "https://site.test/ad/frame"))
        XCTAssertFalse(matches(middle, "https://site.test/adsframe"))
        let start = try XCTUnwrap(network("|https://ads.").first?.trigger.urlFilter)
        XCTAssertTrue(matches(start, "https://ads.site.test/"))
        XCTAssertFalse(matches(start, "http://x.test/?https://ads."))
        let end = try XCTUnwrap(network(".gif|").first?.trigger.urlFilter)
        XCTAssertTrue(matches(end, "https://x.test/a.gif"))
        XCTAssertFalse(matches(end, "https://x.test/a.gif?x"))
        XCTAssertEqual(network("-ad-banner.").first?.trigger.urlFilter, "-ad-banner\\.")
    }

    func testOptionsBecomeTheTrigger() throws {
        let rule = try XCTUnwrap(network("||tracker.test/p.js$script,third-party,domain=a.test|b.test").first)
        XCTAssertEqual(rule.trigger.resourceType, ["script"])
        XCTAssertEqual(rule.trigger.loadType, ["third-party"])
        XCTAssertEqual(rule.trigger.ifDomain, ["*a.test", "*b.test"])
        XCTAssertNil(rule.trigger.unlessDomain)
        let unless = try XCTUnwrap(network("/ads.js$~third-party,domain=~safe.test").first)
        XCTAssertEqual(unless.trigger.loadType, ["first-party"])
        XCTAssertEqual(unless.trigger.unlessDomain, ["*safe.test"])
        XCTAssertEqual(network("/AdUnit$match-case").first?.trigger.caseSensitive, true)
        XCTAssertEqual(network("||x.test^$xmlhttprequest,ping").first?.trigger.resourceType, ["ping", "raw"])
    }

    func testAFrameIsADocumentInsideThePage() throws {
        let rules = network("||ads.test^$subdocument,script")
        XCTAssertEqual(rules.count, 2, "the script, and the frame")
        XCTAssertEqual(rules[0].trigger.resourceType, ["script"])
        XCTAssertEqual(rules[1].trigger.resourceType, ["document"])
        XCTAssertEqual(rules[1].trigger.loadContext, ["child-frame"])
    }

    func testWhatWebKitCantSayIsLeftOut() {
        for filter in ["||x.test^$redirect=noop.js", "||x.test^$csp=script-src 'none'", "||x.test^$popup",
                       "$removeparam=utm_source", "/ads$domain=a.test|~b.a.test", "/(ads|banner)\\.js/",
                       "/ad\\d+\\.js/", "/a{2}/", "||bücher.test^", "||x.test^$object"] {
            let converted = FilterConverter.convert(filter)
            XCTAssertTrue(converted.network.isEmpty, filter)
            XCTAssertEqual(converted.skipped, 1, filter)
        }
        XCTAssertEqual(network("/ad[0-9]+\\.js/").first?.trigger.urlFilter, "ad[0-9]+\\.js")
        // A type WebKit lacks is left out of a filter that names others too.
        XCTAssertEqual(network("||x.test^$object,script").first?.trigger.resourceType, ["script"])
    }

    func testExceptionsComeAfterBlockingAndImportantAfterThem() throws {
        let rules = ContentBlocking.network([FilterConverter.convert("""
        ||a.test^$important
        @@||b.test/ok.js
        ||b.test^
        """)])
        XCTAssertEqual(rules.map(\.action.type), ["block", "ignore-previous-rules", "block", "ignore-previous-rules"])
        XCTAssertTrue(rules[0].trigger.urlFilter.contains("b\\.test"))
        XCTAssertTrue(rules[1].trigger.urlFilter.contains("b\\.test/ok"))
        XCTAssertTrue(rules[2].trigger.urlFilter.contains("a\\.test"), "$important: no exception undoes it")
        XCTAssertEqual(rules[3].trigger.resourceType, ["document"], "and last, the page you went to always loads")
        XCTAssertEqual(rules[3].trigger.loadContext, ["top-frame"])
    }

    func testAWholeSiteException() throws {
        let rule = try XCTUnwrap(FilterConverter.convert("@@||news.test^$document").exceptions.first)
        XCTAssertEqual(rule.action, .allow)
        XCTAssertEqual(rule.trigger.urlFilter, ".*")
        XCTAssertEqual(rule.trigger.ifDomain, ["*news.test"])
    }

    func testBadfilterTurnsAFilterOff() {
        let converted = FilterConverter.convert("""
        ||a.test^
        ||a.test^$badfilter
        ||b.test^
        """)
        XCTAssertEqual(converted.blocks.count, 1)
        XCTAssertTrue(converted.blocks[0].trigger.urlFilter.contains("b\\.test"))
    }

    func testHidingIsGroupedAndHonoursExceptions() throws {
        let hiding = FilterConverter.convert("""
        ##.ad
        ##.banner
        ###sponsor
        example.test#@#.ad
        ~other.test##.promo
        shop.test,deals.test##.offer
        #@#.banner
        """).hiding
        XCTAssertEqual(hiding.count, 4)
        let ad = try XCTUnwrap(hiding.first { $0.action.selector == ".ad" })
        XCTAssertEqual(ad.trigger.unlessDomain, ["*example.test"])
        let promo = try XCTUnwrap(hiding.first { $0.action.selector == ".promo" })
        XCTAssertEqual(promo.trigger.unlessDomain, ["*other.test"])
        let grouped = try XCTUnwrap(hiding.first { $0.action.selector == "#sponsor" })
        XCTAssertNil(grouped.trigger.unlessDomain)
        XCTAssertFalse(hiding.contains { $0.action.selector?.contains(".banner") == true }, "#@# with no site: hidden nowhere")
        let offer = try XCTUnwrap(hiding.first { $0.action.selector == ".offer" })
        XCTAssertEqual(offer.trigger.ifDomain, ["*deals.test", "*shop.test"])
    }

    func testSelectorsAreGroupedFiftyToARule() {
        let text = (0..<120).map { "##.ad-\($0)" }.joined(separator: "\n")
        let hiding = FilterConverter.convert(text).hiding
        XCTAssertEqual(hiding.count, 3)
        XCTAssertEqual(hiding[0].action.selector?.components(separatedBy: ", ").count, 50)
    }

    func testHidingWebKitCantParseIsLeftOut() {
        let converted = FilterConverter.convert("""
        ##div:-abp-has(.ad)
        example.test#?#div:has-text(Sponsored)
        ##+js(nowebrtc)
        example.test##^script:has-text(ads)
        ##.a::before
        ##div[class="unclosed]
        ##.x:upward(2)
        ##div:has(> .a:has(.b))
        example.*##.wild
        """)
        XCTAssertTrue(converted.hiding.isEmpty)
        XCTAssertEqual(converted.skipped, 9)
        XCTAssertEqual(FilterConverter.convert("##div:has(> .sponsored):not(.keep)").hiding.count, 1)
        XCTAssertEqual(FilterConverter.convert("##.trailing\\").hiding.count, 0, "an escape with nothing after it")
        XCTAssertEqual(FilterConverter.convert("##a[href^=\"https://ads.test/\"]").hiding.count, 1)
    }

    func testNoHidingOnASiteWithElemhide() throws {
        let hiding = FilterConverter.convert("""
        @@||app.test^$elemhide
        @@||mail.test^$generichide
        ##.ad
        app.test##.x
        mail.test##.y
        """).hiding
        let generic = try XCTUnwrap(hiding.first { $0.action.selector == ".ad" })
        XCTAssertEqual(generic.trigger.unlessDomain, ["*app.test", "*mail.test"])
        XCTAssertNil(hiding.first { $0.action.selector == ".x" }, "$elemhide: not even the site's own")
        XCTAssertEqual(hiding.first { $0.action.selector == ".y" }?.trigger.ifDomain, ["*mail.test"])
    }

    func testTheHeaderSaysTheVersionAndHowLongItKeeps() {
        let converted = FilterConverter.convert("""
        [Adblock Plus 2.0]
        ! Version: 202610080509
        ! Expires: 4 days (update frequency)
        """)
        XCTAssertEqual(converted.version, "202610080509")
        XCTAssertEqual(converted.expires, 4 * 86400)
        XCTAssertEqual(FilterConverter.convert("! Expires: 12 hours").expires, 12 * 3600)
    }

    func testAListTooLongForOneKeepsItsExceptions() {
        var big = FilterRules()
        big.blocks = Array(repeating: BlockingRule(trigger: .init(urlFilter: "ad"), action: .block), count: ContentBlocking.rulesPerList)
        big.exceptions = [BlockingRule(trigger: .init(urlFilter: "ok"), action: .allow)]
        var other = FilterRules()
        other.blocks = [BlockingRule(trigger: .init(urlFilter: "track"), action: .block)]
        let plan = ContentBlocking.plan([big, other])
        XCTAssertEqual(plan.count, 2)
        XCTAssertEqual(plan[0].rules, ContentBlocking.rulesPerList)
        let first = try? JSONSerialization.jsonObject(with: Data(plan[0].json.utf8)) as? [[String: Any]]
        let types = first?.suffix(2).compactMap { ($0["action"] as? [String: Any])?["type"] as? String }
        XCTAssertEqual(types, ["ignore-previous-rules", "ignore-previous-rules"], "the exception, then the page itself, kept at the end")
    }

    func testThePlanAndItsIdentifiers() {
        var one = FilterConverter.convert("! Version: 1\n||a.test^\n##.ad")
        let plan = ContentBlocking.plan([one])
        XCTAssertEqual(plan.map(\.rules), [2, 1])
        XCTAssertTrue(plan[0].id.hasSuffix(".network.0"))
        XCTAssertTrue(plan[1].id.hasSuffix(".hiding.0"))
        let decoded = try? JSONSerialization.jsonObject(with: Data(plan[0].json.utf8)) as? [[String: Any]]
        XCTAssertEqual(decoded?.count, 2)
        XCTAssertNotNil(decoded?.first?["trigger"])
        one.version = "2"
        XCTAssertNotEqual(ContentBlocking.plan([one])[0].id, plan[0].id, "a new version of a list compiles anew")
    }

    // MARK: The lists the app ships with

    private func bundled() throws -> [FilterRules] {
        try ContentBlocking.lists.map { list in
            FilterConverter.convert(try XCTUnwrap(ContentBlocking.bundled(list), list.name))
        }
    }

    func testTheBundledListsFitWebKitsLimits() throws {
        let converted = try bundled()
        XCTAssertEqual(converted.count, 2)
        let network = ContentBlocking.network(converted)
        XCTAssertLessThanOrEqual(network.count, ContentBlocking.rulesPerList, "both lists' blocking in one list")
        XCTAssertGreaterThan(network.count, 50_000)
        for rules in converted {
            XCTAssertNotNil(rules.version)
            let lines = rules.count + rules.skipped
            XCTAssertLessThan(Double(rules.skipped) / Double(max(lines, 1)), 0.1, "most of the list is kept")
        }
    }

    #if canImport(WebKit)
    /// WebKit itself compiles every list of the plan: one url-filter or
    /// selector it turned down would fail a list in the app.
    @MainActor
    func testWebKitCompilesTheBundledLists() throws {
        let plan = ContentBlocking.plan(try bundled())
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ContentBlockingTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try XCTUnwrap(WKContentRuleListStore(url: folder))
        var failures: [String] = []
        for list in plan {
            let compiled = expectation(description: list.id)
            store.compileContentRuleList(forIdentifier: list.id, encodedContentRuleList: list.json) { compiledList, error in
                if compiledList == nil { failures.append("\(list.id): \(error.map { "\($0)" } ?? "no list")") }
                compiled.fulfill()
            }
            wait(for: [compiled], timeout: 600)
        }
        XCTAssertEqual(failures, [])
    }
    #endif
}
