import Foundation

/// A completed read with no pending writes is the only confirmation of sync.
/// Historical confirmation survives relaunch; current availability does not.
public struct SyncStatus: Equatable, Sendable {
    public enum Waiting: String, Equatable, Sendable {
        case connection, service, account, approval, pendingChanges, confirmation, error
    }
    public enum Phase: Equatable, Sendable {
        case off, checkingAccount, syncing, retrying, waiting(Waiting), completed
    }

    public private(set) var phase: Phase = .off
    public private(set) var lastSuccessfulSync: Date?
    private var confirmedFetch = false

    public init(lastSuccessfulSync: Date? = nil) { self.lastSuccessfulSync = lastSuccessfulSync }

    public mutating func start() { phase = .checkingAccount; confirmedFetch = false }
    public mutating func stop() { phase = .off; confirmedFetch = false }
    public mutating func wait(_ reason: Waiting) { phase = .waiting(reason); confirmedFetch = false }
    public mutating func beginWork() {
        switch phase {
        case .waiting(.connection), .waiting(.service), .waiting(.error), .retrying: phase = .retrying
        default: phase = .syncing
        }
    }
    public mutating func changed() { wait(.pendingChanges) }

    /// A send alone cannot prove that this device has fetched remote changes.
    /// Returns whether the native owner should request a confirming fetch.
    public mutating func sent(changed: Bool, pending: Bool, failed: Bool) -> Bool {
        guard !failed else { return false }
        if pending { wait(.pendingChanges); return false }
        if changed || !confirmedFetch { wait(.confirmation); return true }
        phase = .completed
        return false
    }

    public mutating func fetched(confirmed: Bool, pending: Bool, failed: Bool, now: Date = Date()) {
        guard !failed else { return }
        guard confirmed else {
            if pending { wait(.pendingChanges) }
            else if confirmedFetch { phase = .completed }
            else { wait(.confirmation) }
            return
        }
        guard !pending else { wait(.pendingChanges); return }
        confirmedFetch = true
        lastSuccessfulSync = now
        phase = .completed
    }
}
