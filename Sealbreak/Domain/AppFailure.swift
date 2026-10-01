import Foundation

enum FeedbackLevel: Equatable, Sendable {
    case info
    case success
    case warning
    case error
}

struct AppFeedback: Equatable, Sendable {
    let level: FeedbackLevel
    let text: LocalizedStringResource

    static func info(_ text: LocalizedStringResource) -> Self {
        Self(level: .info, text: text)
    }

    static func success(_ text: LocalizedStringResource) -> Self {
        Self(level: .success, text: text)
    }

    static func warning(_ text: LocalizedStringResource) -> Self {
        Self(level: .warning, text: text)
    }

    static func error(_ text: LocalizedStringResource) -> Self {
        Self(level: .error, text: text)
    }
}

struct AppFailure: Equatable, LocalizedError, Sendable {
    let feedback: AppFeedback

    init(_ text: LocalizedStringResource) {
        feedback = .error(text)
    }

    init(feedback: AppFeedback) {
        self.feedback = feedback
    }

    var message: String { String(localized: feedback.text) }
    var errorDescription: String? { message }
}

func normalizedAppFailure(_ error: Error) -> AppFailure {
    if let failure = error as? AppFailure {
        return failure
    }
    return AppFailure("Operation failed. No sensitive diagnostic data was recorded.")
}
