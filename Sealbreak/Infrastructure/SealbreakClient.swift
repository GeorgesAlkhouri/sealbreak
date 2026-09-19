import ComposableArchitecture
import Foundation

struct SealbreakClient: Sendable {
    var loadProfile: @Sendable () async throws -> ServerProfile?
    var saveProfile: @Sendable (ServerProfile) async throws -> Void
    var deleteProfile: @Sendable () async throws -> Void
    var detectProduct: @Sendable (ServerProfile) async throws -> ServerProduct
    var status: @Sendable (ServerProfile) async throws -> SealStatus
    var submit: @Sendable (ShareRecord) async throws -> Void
    var readShare: @Sendable (_ reason: String) async throws -> ShareRecord
    var insertShare: @Sendable (_ record: ShareRecord, _ reason: String) async throws -> Void
    var replaceShare: @Sendable (
        _ expectedProfile: ServerProfile,
        _ replacement: ShareRecord,
        _ reason: String
    ) async throws -> Void
    var deleteShare: @Sendable (_ reason: String) async throws -> Void
    var requireForeground: @Sendable () async throws -> Void
    var waitForForeground: @Sendable () async throws -> Void
    var cancelSensitiveOperation: @Sendable () async -> Void
}

extension SealbreakClient: TestDependencyKey {
    static let testValue = Self.unimplemented
}

extension DependencyValues {
    var sealbreakClient: SealbreakClient {
        get { self[SealbreakClient.self] }
        set { self[SealbreakClient.self] = newValue }
    }
}

extension SealbreakClient {
    static let unimplemented = Self(
        loadProfile: { throw AppFailure("Unimplemented profile load dependency.") },
        saveProfile: { _ in throw AppFailure("Unimplemented profile save dependency.") },
        deleteProfile: { throw AppFailure("Unimplemented profile delete dependency.") },
        detectProduct: { _ in throw AppFailure("Unimplemented server-product detection dependency.") },
        status: { _ in throw AppFailure("Unimplemented seal-status dependency.") },
        submit: { _ in throw AppFailure("Unimplemented share submission dependency.") },
        readShare: { _ in throw AppFailure("Unimplemented protected-share dependency.") },
        insertShare: { _, _ in throw AppFailure("Unimplemented protected-share dependency.") },
        replaceShare: { _, _, _ in throw AppFailure("Unimplemented protected-share dependency.") },
        deleteShare: { _ in throw AppFailure("Unimplemented protected-share dependency.") },
        requireForeground: { throw AppFailure("Unimplemented foreground dependency.") },
        waitForForeground: { throw AppFailure("Unimplemented foreground dependency.") },
        cancelSensitiveOperation: {
            // Intentionally empty: the test dependency owns no sensitive context to cancel.
        }
    )
}

func normalizedAppFailure(_ error: Error) -> AppFailure {
    if let failure = error as? AppFailure {
        return failure
    }
    return AppFailure("Operation failed. No sensitive diagnostic data was recorded.")
}

func replaceShareIfBound(
    expectedProfile: ServerProfile,
    replacement: ShareRecord,
    readExisting: () throws -> ShareRecord,
    beforeReplace: () throws -> Void,
    replace: (ShareRecord) throws -> Void
) throws {
    var existing = try readExisting()
    defer { existing.share.removeAll(keepingCapacity: false) }

    guard existing.profile == expectedProfile,
          replacement.profile == expectedProfile else {
        throw AppFailure("Target binding mismatch. Restore the protected profile first.")
    }

    try beforeReplace()
    try replace(replacement)
}
