import XCTest
@testable import PadCore

final class PreferencesTests: XCTestCase {
    func testMissingFieldsTakeTheirDefaults() throws {
        let saved = Data(#"{"address":"always","limits":{"heavy":1,"lightOffScreen":0}}"#.utf8)
        let preferences = try JSONDecoder().decode(Preferences.self, from: saved)
        XCTAssertEqual(preferences.address, .always)
        XCTAssertEqual(preferences.limits.lightOffScreen, 0)
        XCTAssertTrue(preferences.tabBar)
        XCTAssertNil(preferences.wheel)
        XCTAssertEqual(preferences.keys, .site)
        XCTAssertEqual(preferences.engine, "google")
    }

    func testUnknownValuesFallBackRatherThanFail() throws {
        let saved = Data(#"{"address":"sometimes","wheel":"sideways","tabBar":false}"#.utf8)
        let preferences = try JSONDecoder().decode(Preferences.self, from: saved)
        XCTAssertEqual(preferences.address, .automatic)
        XCTAssertNil(preferences.wheel)
        XCTAssertFalse(preferences.tabBar)
    }

    func testRoundTrip() throws {
        var preferences = Preferences()
        preferences.wheel = .always
        preferences.keys = .on
        preferences.diagnostics = true
        let data = try JSONEncoder().encode(preferences)
        XCTAssertEqual(try JSONDecoder().decode(Preferences.self, from: data), preferences)
    }

    func testSettingsLayOverTheAdaptersBridges() {
        var preferences = Preferences()
        XCTAssertEqual(preferences.bridges(for: Adapters.figma), Adapters.figma.bridges)
        preferences.wheel = .off
        preferences.keys = .on
        let bridges = preferences.bridges(for: Adapters.figma)
        XCTAssertEqual(bridges.wheel, .off)
        XCTAssertEqual(bridges.keys, [.tab, .arrows])
        XCTAssertTrue(bridges.pinch)
        preferences.keys = .off
        XCTAssertEqual(preferences.bridges(for: Adapters.figma).keys, [])
    }
}

final class ScriptsTests: XCTestCase {
    func testTheResourcesShip() {
        XCTAssertTrue(Scripts.bridge.contains("__safience"))
        XCTAssertTrue(Scripts.style.contains("-webkit-touch-callout: none"))
    }

    func testOurScriptCarriesTheSitesSettings() {
        var bridges = Adapters.figma.bridges
        bridges.keys = [.arrows]
        let script = Scripts.ours(for: Adapters.figma, bridges: bridges)
        XCTAssertTrue(script.hasPrefix("window.__safienceConfig = {"))
        XCTAssertTrue(script.contains(#""adapter":"figma""#))
        XCTAssertTrue(script.contains(#""wheel":"auto""#))
        XCTAssertTrue(script.contains(#""keys":["arrows"]"#))
        XCTAssertTrue(script.contains(#""handsOff":["accounts.google.com"]"#))
        XCTAssertTrue(script.contains("-webkit-touch-callout"))
        XCTAssertTrue(script.contains(Scripts.bridge))
    }

    func testOnlyFigmaHasAPageWorldScript() {
        XCTAssertNotNil(Scripts.page(for: Adapters.figma))
        XCTAssertNil(Scripts.page(for: Adapters.standard))
    }

    func testAdapterScriptsCannotBreakTheBridge() {
        let adapter = SiteAdapter(id: "x", name: "X", domains: ["x.example"], script: "throw new Error('no')")
        let script = Scripts.ours(for: adapter, bridges: .standard)
        XCTAssertTrue(script.contains("try {\nthrow new Error('no')\n} catch (_) {}"))
    }
}

/// The rules about Google's sign-in, kept by reading the app's own source:
/// a cookie read or a script call anywhere else would break them without any
/// test of behaviour noticing.
final class PolicyTests: XCTestCase {
    var iPad: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // PadCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // PadCore
            .deletingLastPathComponent()   // iPad
    }

    func sources(in folder: String, ending: String) throws -> [(String, String)] {
        let root = iPad.appendingPathComponent(folder)
        guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return [] }
        return try files.compactMap { $0 as? URL }
            .filter { $0.path.hasSuffix(ending) }
            .map { ($0.lastPathComponent, try String(contentsOf: $0, encoding: .utf8)) }
    }

    func testNothingReadsCookies() throws {
        let swift = try sources(in: "App", ending: ".swift") + sources(in: "PadCore/Sources", ending: ".swift")
        XCTAssertFalse(swift.isEmpty)
        for (name, text) in swift {
            for banned in ["getAllCookies", "httpCookieStore", "HTTPCookieStorage", "document.cookie"] {
                XCTAssertFalse(text.contains(banned), "\(name) uses \(banned)")
            }
        }
        for (name, text) in try sources(in: "PadCore/Sources", ending: ".js") {
            XCTAssertFalse(text.contains("document.cookie"), "\(name) reads cookies")
        }
    }

    func testOnlyPageSwiftCallsIntoPagesAndItAsksHandsOffFirst() throws {
        let swift = try sources(in: "App", ending: ".swift")
        for (name, text) in swift where name != "Page.swift" {
            for call in ["evaluateJavaScript", "callAsyncJavaScript", "addUserScript"] {
                XCTAssertFalse(text.contains(call), "\(name) calls \(call); calls into pages go through Page.swift")
            }
        }
        let page = try XCTUnwrap(swift.first { $0.0 == "Page.swift" }?.1)
        XCTAssertTrue(page.contains("HandsOff.covers"))
    }
}
