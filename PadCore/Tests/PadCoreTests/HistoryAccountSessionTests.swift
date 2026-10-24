import Foundation
import XCTest
@testable import PadCore

final class HistoryAccountSessionTests: XCTestCase {
    func testUnavailableStorageAtNewAccountApprovalCannotUseOldQueueOrCutoffAfterRetry() {
        var session = HistoryAccountSession()
        let oldCutoff = Date(timeIntervalSince1970: 10)
        let retryTime = Date(timeIntervalSince1970: 100)
        var metadataAccount = "A"
        var uploadAfter = oldCutoff
        var queue = ["A-day", "A-clearing"]
        let durableLocalClearings = ["A": ["local-clearing"]]

        XCTAssertEqual(session.loaded(verified: "B", stored: metadataAccount, available: false), .unavailable)
        XCTAssertFalse(session.allows(verified: "B", stored: metadataAccount))
        XCTAssertEqual(queue.count, 2, "A failed read does not destroy retained metadata")

        XCTAssertEqual(session.loaded(verified: "B", stored: metadataAccount, available: true, now: retryTime),
                       .reset(uploadAfter: retryTime))
        XCTAssertFalse(session.confirm(verified: "B", stored: metadataAccount, persisted: true),
                       "The new engine cannot use A metadata merely because disk became readable")
        XCTAssertFalse(session.allows(verified: "B", stored: metadataAccount))
        // The native owner applies this decision to cloud metadata only.
        metadataAccount = "B"
        queue = []
        uploadAfter = retryTime
        XCTAssertTrue(session.confirm(verified: "B", stored: metadataAccount, persisted: true))
        XCTAssertTrue(session.allows(verified: "B", stored: metadataAccount))
        XCTAssertTrue(queue.isEmpty)
        XCTAssertGreaterThan(uploadAfter, oldCutoff)
        XCTAssertEqual(durableLocalClearings["A"], ["local-clearing"],
                       "Account normalization does not erase SQLite's account-bound local removals")
    }

    func testReadFailureAndAccountChangesInvalidateAPreviousValidation() {
        var session = HistoryAccountSession()
        XCTAssertEqual(session.loaded(verified: "A", stored: "A", available: true), .retain)
        XCTAssertTrue(session.confirm(verified: "A", stored: "A", persisted: true))
        XCTAssertFalse(session.allows(verified: "B", stored: "A"))
        XCTAssertEqual(session.loaded(verified: "B", stored: "A", available: false), .unavailable)
        XCTAssertFalse(session.allows(verified: "A", stored: "A"))
        XCTAssertFalse(session.allows(verified: "B", stored: "A"))
        session.revoke()
        XCTAssertFalse(session.allows(verified: nil, stored: "A"))
    }

    func testNormalizationMustBeAcknowledgedAndDurableEpochRejectsStaleSameAccountMetadata() {
        var consent = SyncAccountConsent()
        consent.observe("A")
        let oldAEpoch = consent.historyEpoch
        consent.observe("B")
        let bEpoch = consent.historyEpoch
        var session = HistoryAccountSession()
        XCTAssertFalse(session.confirm(verified: "B", stored: "B", persisted: false,
                                       verifiedEpoch: bEpoch, storedEpoch: bEpoch))
        XCTAssertFalse(session.allows(verified: "B", stored: "B", verifiedEpoch: bEpoch, storedEpoch: bEpoch))
        // B's SQLite normalization failed, leaving A's metadata on disk. The
        // independently saved consent boundary rotates again when A returns.
        consent.observe("A")
        let newAEpoch = consent.historyEpoch
        XCTAssertNotEqual(oldAEpoch, newAEpoch)
        let now = Date(timeIntervalSince1970: 300)
        XCTAssertEqual(session.loaded(verified: "A", stored: "A", available: true,
                                      verifiedEpoch: newAEpoch, storedEpoch: oldAEpoch, now: now),
                       .reset(uploadAfter: now))
        XCTAssertFalse(session.confirm(verified: "A", stored: "A", persisted: true,
                                       verifiedEpoch: newAEpoch, storedEpoch: oldAEpoch))
        XCTAssertTrue(session.confirm(verified: "A", stored: "A", persisted: true,
                                      verifiedEpoch: newAEpoch, storedEpoch: newAEpoch))
    }

    func testMatchingAccountRetainsMetadataButCannotSendBeforeValidation() {
        var session = HistoryAccountSession()
        XCTAssertFalse(session.allows(verified: "A", stored: "A"))
        XCTAssertEqual(session.loaded(verified: "A", stored: "A", available: true), .retain)
        XCTAssertFalse(session.allows(verified: "A", stored: "A"))
        XCTAssertTrue(session.confirm(verified: "A", stored: "A", persisted: true))
        XCTAssertTrue(session.allows(verified: "A", stored: "A"))
        XCTAssertFalse(session.allows(verified: "A", stored: "B"))
        XCTAssertFalse(session.allows(verified: nil, stored: "A"))
    }
}
