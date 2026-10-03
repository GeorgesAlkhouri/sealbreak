import Foundation

package enum FeedbackLevel: Equatable, Sendable {
    case info
    case success
    case warning
    case error
}

package struct AppFeedback: Equatable, Sendable {
    package let level: FeedbackLevel
    package let text: LocalizedStringResource

    package static func info(_ text: LocalizedStringResource) -> Self {
        Self(level: .info, text: text)
    }

    static func success(_ text: LocalizedStringResource) -> Self {
        Self(level: .success, text: text)
    }

    package static func warning(_ text: LocalizedStringResource) -> Self {
        Self(level: .warning, text: text)
    }

    static func error(_ text: LocalizedStringResource) -> Self {
        Self(level: .error, text: text)
    }
}

package struct AppFailure: Equatable, LocalizedError, Sendable {
    package let feedback: AppFeedback

    package init(_ text: LocalizedStringResource) {
        feedback = .error(text)
    }

    package init(feedback: AppFeedback) {
        self.feedback = feedback
    }

    var message: String { String(localized: feedback.text) }
    package var errorDescription: String? { message }
}

package func normalizedAppFailure(_ error: Error) -> AppFailure {
    if let failure = error as? AppFailure {
        return failure
    }
    return AppFailure(LocalizedStringResource("Operation failed. No sensitive diagnostic data was recorded.", bundle: .module))
}
