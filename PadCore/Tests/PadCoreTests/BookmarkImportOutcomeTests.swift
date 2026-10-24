import Foundation
import XCTest
@testable import PadCore

final class BookmarkImportOutcomeTests: XCTestCase {
    private var parsed: BookmarkImport {
        BookmarkFile.parse(Data("<DL><DT><A HREF=\"https://client.example\">Client</A></DL>".utf8))
    }

    func testDeletedDestinationRetainsParsedBookmarksAndDoesNotReportDuplicates() {
        var workspace = Workspace.starting()
        let before = workspace
        let parsed = parsed
        let outcome = workspace.importBookmarks(parsed, into: UUID())
        XCTAssertEqual(outcome, .destinationMissing(parsed))
        XCTAssertFalse(outcome.isComplete)
        XCTAssertEqual(outcome.parsed, parsed)
        XCTAssertEqual(workspace, before)
    }

    func testMissingDestinationCanBeRechosenWithoutReadingTheFileAgain() throws {
        var workspace = Workspace.starting()
        let outcome = workspace.importBookmarks(parsed, into: UUID())
        let retained = try XCTUnwrap(outcome.parsed)
        let destination = workspace.spaces[0].id
        XCTAssertEqual(workspace.importBookmarks(retained, into: destination),
                       .imported(added: 1, total: 1, space: workspace.spaces[0].name))
        XCTAssertEqual(workspace.spaces[0].bookmarks.flatMap(\.links).count, 1)
    }

    func testDestinationRenamedDuringReadUsesItsCurrentName() {
        var workspace = Workspace.starting()
        let destination = workspace.spaces[0].id
        workspace.renameSpace(destination, to: "Renamed Client")
        XCTAssertEqual(workspace.importBookmarks(parsed, into: destination),
                       .imported(added: 1, total: 1, space: "Renamed Client"))
    }

    func testRepeatedImportOnlyReportsDuplicatesForAnExistingDestination() {
        var workspace = Workspace.starting()
        let destination = workspace.spaces[0].id
        let first = workspace.importBookmarks(parsed, into: destination)
        XCTAssertTrue(first.isComplete)
        XCTAssertEqual(workspace.importBookmarks(parsed, into: destination), .duplicates(total: 1, space: workspace.spaces[0].name))
        XCTAssertEqual(workspace.spaces[0].bookmarks.flatMap(\.links).count, 1)
    }

    func testFailedDurableSaveDoesNotBecomeCompletedOnboarding() {
        let outcome = BookmarkImportOutcome.imported(added: 1, total: 2, space: "Client")
        let failed = outcome.acknowledgingSave(false)
        XCTAssertEqual(failed, .notSaved(added: 1, total: 2, space: "Client"))
        XCTAssertFalse(failed.isComplete)
        XCTAssertTrue(failed.needsSave)
        XCTAssertEqual(failed.acknowledgingSave(true), outcome)
    }

    func testFailedSaveRetainsDestinationIdentityAndParsedFileWhenDestinationIsRemoved() throws {
        let parsed = parsed
        var workspace = Workspace.starting()
        let destination = workspace.spaces[0].id
        let original = workspace.importBookmarks(parsed, into: destination)
        let retry = BookmarkImportRetry(bookmarks: parsed, destination: destination)
        let failed = original.acknowledgingSave(false, retry: retry)
        let replacement = workspace.addSpace(named: workspace.spaces[0].name)
        _ = workspace.removeSpace(destination)
        XCTAssertNotEqual(destination, replacement)
        let checked = failed.validatingDestination(in: workspace)
        XCTAssertEqual(checked, .destinationMissing(parsed))
        XCTAssertFalse(checked.acknowledgingSave(true).isComplete,
                       "An acknowledged workspace write cannot complete an import into a deleted space")
        let retained = try XCTUnwrap(checked.parsed)
        XCTAssertTrue(workspace.importBookmarks(retained, into: replacement).isComplete)
    }

    func testSaveRetryUsesRenamedDestinationWithoutLosingTheReceipt() {
        var workspace = Workspace.starting()
        let destination = workspace.spaces[0].id
        let original = workspace.importBookmarks(parsed, into: destination)
        let failed = original.acknowledgingSave(false, retry: BookmarkImportRetry(bookmarks: parsed, destination: destination))
        workspace.renameSpace(destination, to: "Renamed")
        let checked = failed.validatingDestination(in: workspace)
        XCTAssertEqual(checked.acknowledgingSave(true), .imported(added: 1, total: 1, space: "Renamed"))
        XCTAssertEqual(checked.acknowledgingSave(false).validatingDestination(in: workspace), checked)
    }

    func testEveryReadFailureKeepsAFileRecoveryRoute() {
        for outcome in [BookmarkImportOutcome.unreadable, .archiveWithoutBookmarks, .empty, .cancelled] {
            XCTAssertFalse(outcome.isComplete)
            XCTAssertTrue(outcome.canChooseFile)
        }
        XCTAssertEqual(BookmarkFile.readExport(Data("not a bookmarks export".utf8)), .failure(.empty))
    }
}
