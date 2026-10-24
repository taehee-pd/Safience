import Foundation

public enum WorkspaceSaveFailure: Error, Equatable, Sendable {
    case outOfSpace, permissionDenied, sourceUnavailable, writeFailed

    init(_ error: Error) {
        if error is WorkspaceFile.Failure {
            self = .sourceUnavailable
            return
        }
        let error = error as NSError
        if error.domain == NSCocoaErrorDomain, error.code == NSFileWriteOutOfSpaceError {
            self = .outOfSpace
        } else if error.domain == NSCocoaErrorDomain, error.code == NSFileWriteNoPermissionError {
            self = .permissionDenied
        } else if error.domain == NSCocoaErrorDomain, error.code == NSFileReadNoPermissionError {
            self = .permissionDenied
        } else {
            self = .writeFailed
        }
    }
}

public struct WorkspaceSaveReceipt: Sendable {
    public let revision: UInt64
    public let failure: WorkspaceSaveFailure?
}

/// An acknowledgement belongs to the revision written, not the latest UI edit.
public struct WorkspaceSaveState: Equatable, Sendable {
    public private(set) var revision: UInt64 = 0
    public private(set) var savedRevision: UInt64 = 0
    public private(set) var failure: WorkspaceSaveFailure?
    public var isDirty: Bool { savedRevision < revision }

    public init() {}

    @discardableResult
    public mutating func changed() -> UInt64 {
        revision += 1
        return revision
    }

    public mutating func acknowledge(_ receipt: WorkspaceSaveReceipt) {
        guard receipt.revision <= revision else { return }
        if let failure = receipt.failure {
            if receipt.revision > savedRevision { self.failure = failure }
        } else {
            savedRevision = max(savedRevision, receipt.revision)
            if !isDirty { failure = nil }
        }
    }
}

/// The serial queue owns revision ordering and all writes. Older submissions
/// cannot replace a newer acknowledged file, even when submitted out of order.
public final class WorkspaceWriter: @unchecked Sendable {
    private let file: URL
    private let write: @Sendable (Workspace, URL) throws -> Void
    private let queue = DispatchQueue(label: "Safience.workspace", qos: .utility)
    private var savedRevision: UInt64 = 0

    public init(file: URL) {
        self.file = file
        write = { try WorkspaceFile.write($0, to: $1) }
    }

    init(file: URL, write: @escaping @Sendable (Workspace, URL) throws -> Void) {
        self.file = file
        self.write = write
    }

    public func save(_ workspace: Workspace, revision: UInt64,
                     completion: @escaping @Sendable (WorkspaceSaveReceipt) -> Void) {
        queue.async { completion(self.commit(workspace, revision: revision)) }
    }

    public func saveNow(_ workspace: Workspace, revision: UInt64) -> WorkspaceSaveReceipt {
        queue.sync { commit(workspace, revision: revision) }
    }

    private func commit(_ workspace: Workspace, revision: UInt64) -> WorkspaceSaveReceipt {
        guard revision > savedRevision else { return WorkspaceSaveReceipt(revision: savedRevision, failure: nil) }
        do {
            try write(workspace, file)
            savedRevision = revision
            return WorkspaceSaveReceipt(revision: revision, failure: nil)
        } catch {
            return WorkspaceSaveReceipt(revision: revision, failure: WorkspaceSaveFailure(error))
        }
    }
}
