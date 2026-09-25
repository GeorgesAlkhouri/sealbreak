import Foundation

struct AppFailure: Equatable, LocalizedError, Sendable {
    let resource: LocalizedStringResource

    init(_ resource: LocalizedStringResource) {
        self.resource = resource
    }

    var message: String { String(localized: resource) }
    var errorDescription: String? { message }
}

func normalizedAppFailure(_ error: Error) -> AppFailure {
    if let failure = error as? AppFailure {
        return failure
    }
    return AppFailure("Operation failed. No sensitive diagnostic data was recorded.")
}
