import XCTest
@testable import PadCore

final class ExtensionLocalizationTests: XCTestCase {
    private let id = "abcdefghijklmnopabcdefghijklmnop"

    private func manifest(_ name: String = "__MSG_appName__", defaultLocale: String? = "en") throws -> ExtensionManifest {
        var object: [String: Any] = ["manifest_version": 3, "name": name, "version": "1"]
        object["default_locale"] = defaultLocale
        return try ExtensionManifest(json: JSONSerialization.data(withJSONObject: object))
    }

    private func archive(_ files: [String: String]) -> Data {
        ExtensionPreparationTests.zip(files.map { ($0.key, Data($0.value.utf8)) })
    }

    func testLiteralNamesNeedNoLocaleFiles() throws {
        let manifest = try manifest("Are.na", defaultLocale: nil)
        XCTAssertEqual(manifest.displayName(in: Data(), fallback: id, locale: "ko-KR"), "Are.na")
    }

    func testPreferredRegionUsesBaseAndDefaultForMissingMessages() throws {
        let manifest = try manifest("__MSG_brand__ __MSG_flavour__ __MSG_suffix__")
        let files = archive([
            "_locales/en_GB/messages.json": #"{"flavour":{"message":"Colour"}}"#,
            "_locales/en/messages.json": #"{"brand":{"message":"Clip"},"flavour":{"message":"Color"},"suffix":{"message":"tool"}}"#
        ])
        XCTAssertEqual(manifest.displayName(in: files, fallback: id, locale: "en-GB"), "Clip Colour tool")
    }

    func testLocalizedNamesUseCaseInsensitiveMessageKeys() throws {
        let files = archive([
            "_locales/ko/messages.json": #"{"APPNAME":{"message":"번역"}}"#,
            "_locales/en/messages.json": #"{"appName":{"message":"Translate"}}"#
        ])
        XCTAssertEqual(try manifest().displayName(in: files, fallback: id, locale: "ko-KR"), "번역")
    }

    func testUnsupportedLocaleFallsBackToDeclaredDefault() throws {
        let files = archive(["_locales/en/messages.json": #"{"appName":{"message":"Notion Web Clipper"}}"#])
        XCTAssertEqual(try manifest().displayName(in: files, fallback: id, locale: "fr-FR"), "Notion Web Clipper")
    }

    func testDamagedPreferredCatalogFallsBackWithoutChangingTheArchive() throws {
        let files = archive([
            "_locales/ko/messages.json": "unreadable JSON",
            "_locales/en/messages.json": #"{"appName":{"message":"Translate"}}"#
        ])
        let original = files
        XCTAssertEqual(try manifest().displayName(in: files, fallback: id, locale: "ko"), "Translate")
        XCTAssertEqual(files, original)
    }

    func testExistingIDOrRawMessageRefreshesFromTheRetainedPackage() throws {
        let files = archive(["_locales/en/messages.json": #"{"appName":{"message":"Notion Web Clipper"}}"#])
        let manifest = try manifest()
        for saved in [id, "__MSG_appName__"] {
            XCTAssertEqual(manifest.displayName(in: files, fallback: saved, locale: "en-US"), "Notion Web Clipper")
        }
        XCTAssertEqual(manifest.displayName(in: Data(), fallback: "Notion Web Clipper", locale: "en"), "Notion Web Clipper")
        XCTAssertEqual(manifest.displayName(in: Data(), fallback: id, locale: "en"), id)
    }

    func testManifestNameExpandsStaticCaseInsensitivePlaceholdersAndLiteralDollars() throws {
        let files = archive(["_locales/en/messages.json": #"{"appName":{"message":"$PRODUCT$ $$","placeholders":{"product":{"content":"Clipper"}}}}"#])
        XCTAssertEqual(try manifest().displayName(in: files, fallback: id, locale: "en"), "Clipper $")
    }

    func testUnsupportedPositionalSubstitutionUsesDefaultOrRetainedName() throws {
        let files = archive([
            "_locales/ko/messages.json": #"{"appName":{"message":"Clip $product$","placeholders":{"product":{"content":"$1"}}}}"#,
            "_locales/en/messages.json": #"{"appName":{"message":"Clipper"}}"#
        ])
        XCTAssertEqual(try manifest().displayName(in: files, fallback: id, locale: "ko"), "Clipper")
        let unsupported = archive(["_locales/en/messages.json": #"{"appName":{"message":"Clip $1"}}"#])
        XCTAssertEqual(try manifest().displayName(in: unsupported, fallback: "Saved Clipper", locale: "en"), "Saved Clipper")
    }

    func testInvalidLocaleCannotReadOutsideLocaleCatalogs() throws {
        let files = archive(["messages.json": #"{"appName":{"message":"Wrong file"}}"#])
        XCTAssertEqual(try manifest(defaultLocale: "../..").displayName(in: files, fallback: id, locale: "../../"), id)
    }
}

final class ExtensionCheckEnvironmentTests: XCTestCase {
    private let environment = ExtensionCheckEnvironment(system: "macOS 27 build A", application: "1.0.8 (38)", shim: "shim A")

    func testGenuineFailureStillBlocksTheSameVersionInTheSameEnvironment() {
        let failure = environment.stamp(for: "2.14.3")
        XCTAssertEqual(environment.currentFailures(["clipper": failure], installed: ["clipper": "2.14.3"]), ["clipper": failure])
    }

    func testNewAppShimSystemOrExtensionCanBeReevaluated() {
        let failure = environment.stamp(for: "2.14.3")
        for changed in [
            ExtensionCheckEnvironment(system: environment.system, application: "1.0.8 (39)", shim: environment.shim),
            ExtensionCheckEnvironment(system: environment.system, application: environment.application, shim: "shim B"),
            ExtensionCheckEnvironment(system: "macOS 27 build B", application: environment.application, shim: environment.shim)
        ] {
            XCTAssertTrue(changed.currentFailures(["clipper": failure], installed: ["clipper": "2.14.3"]).isEmpty)
        }
        XCTAssertTrue(environment.currentFailures(["clipper": failure], installed: ["clipper": "2.14.4"]).isEmpty)
    }

    func testLegacyAndRemovedFailureMarkersExpireWithoutChangingInstalledVersions() {
        let installed = ["clipper": "2.14.3", "translator": "1.2"]
        XCTAssertTrue(environment.currentFailures(["clipper": "2.14.3", "removed": environment.stamp(for: "1")], installed: installed).isEmpty)
        XCTAssertEqual(installed, ["clipper": "2.14.3", "translator": "1.2"])
    }
}

final class ExtensionWorkerRecoveryTests: XCTestCase {
    func testDuplicateHistoricalNotificationsCannotDisableASuccessfullyRestartedWorker() {
        var recovery = ExtensionWorkerRecovery()
        _ = recovery.beganAttempt(restarting: false)
        XCTAssertEqual(recovery.noticedHistoricalFailure(), .restart)
        XCTAssertEqual(recovery.noticedHistoricalFailure(), .ignore)
        let retry = recovery.beganAttempt(restarting: true)
        XCTAssertEqual(recovery.finished(retry, failed: false), .ignore)
        for _ in 0..<5 { XCTAssertEqual(recovery.noticedHistoricalFailure(), .ignore) }
    }

    func testOnlyTheRestartAttemptsOwnConfirmedFailureEstablishesIncompatibility() {
        var recovery = ExtensionWorkerRecovery()
        let original = recovery.beganAttempt(restarting: false)
        XCTAssertEqual(recovery.finished(original, failed: true), .restart)
        let retry = recovery.beganAttempt(restarting: true)
        XCTAssertEqual(recovery.noticedHistoricalFailure(), .ignore)
        XCTAssertEqual(recovery.finished(retry, failed: true), .incompatible)
        XCTAssertEqual(recovery.finished(retry, failed: true), .ignore)
    }

    func testLatePreviousAttemptCompletionCannotDisableOrDowngradeReplacement() {
        var recovery = ExtensionWorkerRecovery()
        let original = recovery.beganAttempt(restarting: false)
        let retry = recovery.beganAttempt(restarting: true)
        XCTAssertEqual(recovery.finished(original, failed: true), .ignore)
        XCTAssertEqual(recovery.finished(retry, failed: false), .ignore)
        XCTAssertEqual(recovery.finished(original, failed: false), .ignore)
    }

    func testCooldownOrDeferredRestartDoesNotBecomeAFailedRestart() {
        var recovery = ExtensionWorkerRecovery()
        _ = recovery.beganAttempt(restarting: false)
        XCTAssertEqual(recovery.noticedHistoricalFailure(), .restart)
        // The caller declined/deferred the attempt. No new completion exists.
        for _ in 0..<5 { XCTAssertEqual(recovery.noticedHistoricalFailure(), .ignore) }
        let later = recovery.beganAttempt(restarting: true)
        XCTAssertEqual(recovery.finished(later, failed: false), .ignore)
    }
}
