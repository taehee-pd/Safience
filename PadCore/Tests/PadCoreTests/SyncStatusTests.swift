import Foundation
import XCTest
@testable import PadCore

final class SyncStatusTests: XCTestCase {
    func testRelaunchRetainsHistoricalDateWithoutClaimingCurrentSync() {
        let previous = Date(timeIntervalSince1970: 10)
        var status = SyncStatus(lastSuccessfulSync: previous)
        status.start()
        XCTAssertEqual(status.phase, .checkingAccount)
        XCTAssertEqual(status.lastSuccessfulSync, previous)
        status.fetched(confirmed: false, pending: false, failed: false)
        XCTAssertEqual(status.phase, .waiting(.confirmation))
        XCTAssertEqual(status.lastSuccessfulSync, previous)
    }

    func testOfflineFailuresAndSendOnlyNeverBecomeCompleted() {
        var status = SyncStatus()
        status.start()
        status.wait(.connection)
        status.beginWork()
        XCTAssertEqual(status.phase, .retrying)
        status.wait(.service)
        status.fetched(confirmed: true, pending: false, failed: true)
        XCTAssertEqual(status.phase, .waiting(.service))
        XCTAssertNil(status.lastSuccessfulSync)
        XCTAssertFalse(status.sent(changed: true, pending: false, failed: true))
        XCTAssertEqual(status.phase, .waiting(.service))
        XCTAssertTrue(status.sent(changed: true, pending: false, failed: false))
        XCTAssertEqual(status.phase, .waiting(.confirmation))
        XCTAssertNil(status.lastSuccessfulSync)
    }

    func testUnrelatedZoneFetchDoesNotLeaveStatusSpinningOrInventANewConfirmation() {
        var status = SyncStatus()
        let confirmed = Date(timeIntervalSince1970: 20)
        status.fetched(confirmed: true, pending: false, failed: false, now: confirmed)
        status.beginWork()
        status.fetched(confirmed: false, pending: false, failed: false, now: confirmed.addingTimeInterval(10))
        XCTAssertEqual(status.phase, .completed)
        XCTAssertEqual(status.lastSuccessfulSync, confirmed)
        status.beginWork()
        status.fetched(confirmed: false, pending: true, failed: false)
        XCTAssertEqual(status.phase, .waiting(.pendingChanges))
    }

    func testSuccessfulRoundtripRequiresConfirmedReadAndNoPendingChanges() {
        var status = SyncStatus()
        let confirmed = Date(timeIntervalSince1970: 20)
        status.start()
        status.fetched(confirmed: true, pending: true, failed: false, now: confirmed)
        XCTAssertEqual(status.phase, .waiting(.pendingChanges))
        XCTAssertNil(status.lastSuccessfulSync)
        XCTAssertTrue(status.sent(changed: true, pending: false, failed: false))
        status.fetched(confirmed: true, pending: false, failed: false, now: confirmed)
        XCTAssertEqual(status.phase, .completed)
        XCTAssertEqual(status.lastSuccessfulSync, confirmed)
        status.changed()
        XCTAssertEqual(status.phase, .waiting(.pendingChanges))
        XCTAssertEqual(status.lastSuccessfulSync, confirmed)
        status.wait(.approval)
        XCTAssertEqual(status.phase, .waiting(.approval))
        status.stop()
        XCTAssertEqual(status.phase, .off)
        XCTAssertEqual(status.lastSuccessfulSync, confirmed)
    }
}
