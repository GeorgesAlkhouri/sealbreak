import ComposableArchitecture
import Foundation

enum DNSSECStatus: Equatable, Sendable {
    case secure
    case insecure
    case bogus
    case indeterminate
    case notApplicable
    case unavailable
}

enum LocalSetupState: Equatable, Sendable {
    case empty
    case ready(ServerProfile)
    case recoveryRequired
}

enum SetupProtectionOutcome: Equatable, Sendable {
    case protected
    case recoveryRequired(String)
}

struct SealbreakClient: Sendable {
    var loadProfiles: @Sendable () async throws -> [ServerProfile]
    var loadLocalSetupState: @Sendable () async throws -> LocalSetupState
    var protectNewProfile: @Sendable (
        _ profile: ServerProfile,
        _ record: ShareRecord,
        _ reason: String
    ) async throws -> SetupProtectionOutcome
    var insertProfile: @Sendable (ServerProfile) async throws -> Void
    var saveProfile: @Sendable (ServerProfile) async throws -> Void
    var deleteProfile: @Sendable (UUID) async throws -> Void
    var resetLocalData: @Sendable () async throws -> Void
    var detectProduct: @Sendable (ServerProfile) async throws -> ServerProduct
    var dnssecStatus: @Sendable (String) async throws -> DNSSECStatus
    var status: @Sendable (ServerProfile) async throws -> SealStatus
    var submit: @Sendable (ShareRecord) async throws -> Void
    var readShare: @Sendable (_ profileID: UUID, _ reason: String) async throws -> ShareRecord
    var insertShare: @Sendable (_ record: ShareRecord, _ reason: String) async throws -> Void
    var replaceShare: @Sendable (
        _ expectedProfile: ServerProfile,
        _ replacement: ShareRecord,
        _ reason: String
    ) async throws -> Void
    var deleteShare: @Sendable (_ profileID: UUID, _ reason: String) async throws -> Void
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
        loadProfiles: { throw AppFailure("Unimplemented profile load dependency.") },
        loadLocalSetupState: { throw AppFailure("Unimplemented local setup state dependency.") },
        protectNewProfile: { _, _, _ in
            throw AppFailure("Unimplemented setup protection dependency.")
        },
        insertProfile: { _ in throw AppFailure("Unimplemented profile insert dependency.") },
        saveProfile: { _ in throw AppFailure("Unimplemented profile save dependency.") },
        deleteProfile: { _ in throw AppFailure("Unimplemented profile delete dependency.") },
        resetLocalData: { throw AppFailure("Unimplemented local-data reset dependency.") },
        detectProduct: { _ in throw AppFailure("Unimplemented server-product detection dependency.") },
        dnssecStatus: { _ in throw AppFailure("Unimplemented DNSSEC status dependency.") },
        status: { _ in throw AppFailure("Unimplemented seal-status dependency.") },
        submit: { _ in throw AppFailure("Unimplemented share submission dependency.") },
        readShare: { _, _ in throw AppFailure("Unimplemented protected-share dependency.") },
        insertShare: { _, _ in throw AppFailure("Unimplemented protected-share dependency.") },
        replaceShare: { _, _, _ in throw AppFailure("Unimplemented protected-share dependency.") },
        deleteShare: { _, _ in throw AppFailure("Unimplemented protected-share dependency.") },
        requireForeground: { throw AppFailure("Unimplemented foreground dependency.") },
        waitForForeground: { throw AppFailure("Unimplemented foreground dependency.") },
        cancelSensitiveOperation: {
            // Intentionally empty: the test dependency owns no sensitive context to cancel.
        }
    )
}
