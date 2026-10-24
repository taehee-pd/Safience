import PadCore
import SwiftUI

/// Status remains visible while disconnected. The date is a historical server
/// confirmation, not a claim that a newly enabled or offline device is current.
struct SyncStatusView: View {
    @ObservedObject private var sync = Sync.shared

    private var title: String {
        switch sync.status.phase {
        case .off: return "Sync is off"
        case .checkingAccount: return "Checking iCloud account"
        case .syncing: return "Syncing with iCloud"
        case .retrying: return "Retrying iCloud sync"
        case .completed: return "Sync completed"
        case .waiting(let reason):
            switch reason {
            case .connection: return "Waiting for a connection"
            case .service: return "Waiting for iCloud to retry"
            case .account: return "Waiting for an available Apple Account"
            case .approval: return "Sync is paused until you approve this Apple Account"
            case .pendingChanges: return "Changes are waiting to sync"
            case .confirmation: return "Waiting for iCloud confirmation"
            case .error: return "Sync could not complete. Retry when iCloud is available."
            }
        }
    }

    private var working: Bool {
        switch sync.status.phase {
        case .checkingAccount, .syncing, .retrying: return true
        default: return false
        }
    }

    private var canRetry: Bool {
        if case .waiting(let reason) = sync.status.phase { return reason != .approval }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if working { ProgressView().controlSize(.small) }
                Text(LocalizedStringKey(title)).font(.subheadline)
            }
            if let confirmed = sync.status.lastSuccessfulSync {
                LabeledContent("Last confirmed sync", value: confirmed.formatted(date: .abbreviated, time: .shortened))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("No sync has been confirmed yet.").font(.footnote).foregroundStyle(.secondary)
            }
            if canRetry { Button("Retry Sync") { sync.retrySync() } }
            if !sync.canConfigureHistory {
                Text("History sync requires an approved Apple Account and readable local history. While history sync is paused, clearing history affects this device only.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("syncStatus")
    }
}

/// Account permission is persistent and available again after closing Settings.
struct SyncAccountChoiceView: View {
    @ObservedObject private var sync = Sync.shared

    var body: some View {
        if sync.accountDecisionNeeded {
            VStack(alignment: .leading, spacing: 12) {
                Text(sync.keepingDataLocal ? "Data Stays on This Device" : "iCloud Sync Is Paused")
                    .font(.headline)
                Text("Choose whether to sync this device's spaces, bookmarks and pinned tabs with its current Apple Account, including history when Sync history is on. On Macs this also syncs Chrome Web Store extensions. Spaces with the same name stay separate. Sign-ins and site data stay on this device.")
                    .font(.callout)
                if !sync.keepingDataLocal {
                    Button("Keep Data on This Device") { sync.keepDataOnDevice() }
                        .disabled(sync.savingAccountChoice)
                }
                Button("Sync with Current Apple Account") { Task { await sync.syncWithCurrentAccount() } }
                    .disabled(sync.savingAccountChoice)
                if sync.savingAccountChoice { ProgressView("Saving account choice") }
                if let problem = sync.problem {
                    Label(problem, systemImage: "exclamationmark.icloud")
                        .font(.footnote)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("syncAccountChoice")
        }
    }
}
