import Foundation

struct AppFailure: Equatable, LocalizedError, Sendable {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}

enum BiometricAuthorizationFailure: Error, Equatable, Sendable {
    case userCancelled
    case systemCancelled
    case appCancelled
    case authenticationFailed

    var message: String {
        switch self {
        case .userCancelled:
            return "Face ID was cancelled. The share remains ready to retry."
        case .systemCancelled, .appCancelled:
            return "Face ID was interrupted because Sealbreak left the active foreground."
        case .authenticationFailed:
            return "Face ID did not authorize this action. The share remains ready to retry."
        }
    }

    var discardsSensitiveDraft: Bool {
        switch self {
        case .systemCancelled, .appCancelled:
            return true
        case .userCancelled, .authenticationFailed:
            return false
        }
    }
}

func normalizedAppFailure(_ error: Error) -> AppFailure {
    if let failure = error as? AppFailure {
        return failure
    }
    if let failure = error as? BiometricAuthorizationFailure {
        return AppFailure(failure.message)
    }
    return AppFailure("Operation failed. No sensitive diagnostic data was recorded.")
}
