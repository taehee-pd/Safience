import Foundation

public enum HistoryOperationError: Error, Equatable, Sendable {
    case unavailable, readFailed, writeFailed
    public var message: String {
        switch self {
        case .unavailable: return "History is unavailable. Unlock your device and check available storage or file access, then retry. Existing history has been retained."
        case .readFailed: return "History could not be read. Check available storage or file access, then retry."
        case .writeFailed: return "History changes could not be saved. Check available storage or file access, then retry."
        }
    }
}

public enum HistoryAvailability: Equatable, Sendable {
    case available
    case unavailable(HistoryOperationError)
}
