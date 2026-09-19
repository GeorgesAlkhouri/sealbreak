import Foundation

struct AppFailure: Equatable, LocalizedError, Sendable {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}

func normalizedAppFailure(_ error: Error) -> AppFailure {
    if let failure = error as? AppFailure {
        return failure
    }
    return AppFailure("Operation failed. No sensitive diagnostic data was recorded.")
}
