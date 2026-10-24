import Combine
import Foundation
import os
import PadCore

@MainActor
final class WorkspacePersistence: ObservableObject {
    private static let log = Logger(subsystem: "net.taehee.safience", category: "Session")
    @Published private(set) var state = WorkspaceSaveState()
    @Published private(set) var isSaving = false
    private let writer: WorkspaceWriter
    private var waiting: Task<Void, Never>?
    private var inFlight = 0

    init(file: URL) { writer = WorkspaceWriter(file: file) }

    func changed(_ workspace: Workspace) {
        let revision = state.changed()
        waiting?.cancel()
        waiting = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(500)) }
            catch { return }
            guard let self, !Task.isCancelled else { return }
            self.waiting = nil
            self.submit(workspace, revision: revision) { _ in }
        }
    }

    func flush(_ workspace: Workspace, completion: @escaping @MainActor @Sendable (Bool) -> Void) {
        waiting?.cancel()
        waiting = nil
        guard state.isDirty else { return completion(true) }
        submit(workspace, revision: state.revision, completion: completion)
    }

    func flushNow(_ workspace: Workspace) -> Bool {
        waiting?.cancel()
        waiting = nil
        guard state.isDirty else { return true }
        state.acknowledge(writer.saveNow(workspace, revision: state.revision))
        return !state.isDirty
    }

    private func submit(_ workspace: Workspace, revision: UInt64,
                        completion: @escaping @MainActor @Sendable (Bool) -> Void) {
        inFlight += 1
        isSaving = true
        writer.save(workspace, revision: revision) { [weak self] receipt in
            Task { @MainActor in
                guard let self else { return }
                self.inFlight -= 1
                self.isSaving = self.inFlight != 0
                // For Console: the banner says it to the person (WorkspaceSaveStatusView).
                if let failure = receipt.failure {
                    Self.log.error("Workspace not saved: \(String(describing: failure), privacy: .public)")
                }
                self.state.acknowledge(receipt)
                completion(!self.state.isDirty)
            }
        }
    }
}
