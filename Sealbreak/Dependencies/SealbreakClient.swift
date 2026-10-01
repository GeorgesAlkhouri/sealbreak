import ComposableArchitecture
import Foundation

package enum DNSSECStatus: Equatable, Sendable {
    case secure
    case insecure
    case bogus
    case indeterminate
    case notApplicable
    case unavailable
}

package enum LocalSetupState: Equatable, Sendable {
    case empty
    case ready(ServerProfile)
    case recoveryRequired(LocalizedStringResource)
}

package enum LocalPersistenceOutcome: Equatable, Sendable {
    case completed
    case recoveryRequired(LocalizedStringResource)
}

package struct SealbreakClient: Sendable {
    package var loadLocalSetupState: @Sendable () async throws -> LocalSetupState
    package var protectNewProfile: @Sendable (
        _ profile: ServerProfile,
        _ record: ShareRecord,
        _ reason: LocalizedStringResource
    ) async throws -> LocalPersistenceOutcome
    package var resetLocalData: @Sendable () async throws -> Void
    package var detectProduct: @Sendable (ServerProfile) async throws -> ServerProduct
    package var dnssecStatus: @Sendable (String) async throws -> DNSSECStatus
    package var status: @Sendable (ServerProfile) async throws -> SealStatus
    package var submit: @Sendable (ShareRecord) async throws -> Void
    package var readShareFragment: @Sendable (
        _ profileID: UUID,
        _ reason: LocalizedStringResource
    ) async throws -> ShareComparisonFragment
    package var readShare: @Sendable (_ profileID: UUID, _ reason: LocalizedStringResource) async throws -> ShareRecord
    package var replaceShare: @Sendable (
        _ expectedProfile: ServerProfile,
        _ replacement: ShareRecord,
        _ reason: LocalizedStringResource
    ) async throws -> Void
    package var removeLocalProfile: @Sendable (
        _ profileID: UUID,
        _ reason: LocalizedStringResource
    ) async throws -> LocalPersistenceOutcome
    package var requireForeground: @Sendable () async throws -> Void
    package var waitForForeground: @Sendable () async throws -> Void
    package var cancelSensitiveOperation: @Sendable () async -> Void

    package init(
        loadLocalSetupState: @escaping @Sendable () async throws -> LocalSetupState,
        protectNewProfile: @escaping @Sendable (ServerProfile, ShareRecord, LocalizedStringResource) async throws -> LocalPersistenceOutcome,
        resetLocalData: @escaping @Sendable () async throws -> Void,
        detectProduct: @escaping @Sendable (ServerProfile) async throws -> ServerProduct,
        dnssecStatus: @escaping @Sendable (String) async throws -> DNSSECStatus,
        status: @escaping @Sendable (ServerProfile) async throws -> SealStatus,
        submit: @escaping @Sendable (ShareRecord) async throws -> Void,
        readShareFragment: @escaping @Sendable (UUID, LocalizedStringResource) async throws -> ShareComparisonFragment,
        readShare: @escaping @Sendable (UUID, LocalizedStringResource) async throws -> ShareRecord,
        replaceShare: @escaping @Sendable (ServerProfile, ShareRecord, LocalizedStringResource) async throws -> Void,
        removeLocalProfile: @escaping @Sendable (UUID, LocalizedStringResource) async throws -> LocalPersistenceOutcome,
        requireForeground: @escaping @Sendable () async throws -> Void,
        waitForForeground: @escaping @Sendable () async throws -> Void,
        cancelSensitiveOperation: @escaping @Sendable () async -> Void
    ) {
        self.loadLocalSetupState = loadLocalSetupState
        self.protectNewProfile = protectNewProfile
        self.resetLocalData = resetLocalData
        self.detectProduct = detectProduct
        self.dnssecStatus = dnssecStatus
        self.status = status
        self.submit = submit
        self.readShareFragment = readShareFragment
        self.readShare = readShare
        self.replaceShare = replaceShare
        self.removeLocalProfile = removeLocalProfile
        self.requireForeground = requireForeground
        self.waitForForeground = waitForForeground
        self.cancelSensitiveOperation = cancelSensitiveOperation
    }
}

extension SealbreakClient: DependencyKey {
    package static let liveValue = Self.unimplemented
    package static let testValue = Self.unimplemented
}

package extension DependencyValues {
    var sealbreakClient: SealbreakClient {
        get { self[SealbreakClient.self] }
        set { self[SealbreakClient.self] = newValue }
    }
}

package extension SealbreakClient {
    static let unimplemented = Self(
        loadLocalSetupState: { throw AppFailure("Unimplemented local setup state dependency.") },
        protectNewProfile: { _, _, _ in
            throw AppFailure("Unimplemented setup protection dependency.")
        },
        resetLocalData: { throw AppFailure("Unimplemented local-data reset dependency.") },
        detectProduct: { _ in throw AppFailure("Unimplemented server-product detection dependency.") },
        dnssecStatus: { _ in throw AppFailure("Unimplemented DNSSEC status dependency.") },
        status: { _ in throw AppFailure("Unimplemented seal-status dependency.") },
        submit: { _ in throw AppFailure("Unimplemented share submission dependency.") },
        readShareFragment: { _, _ in throw AppFailure("Unimplemented protected-share dependency.") },
        readShare: { _, _ in throw AppFailure("Unimplemented protected-share dependency.") },
        replaceShare: { _, _, _ in throw AppFailure("Unimplemented protected-share dependency.") },
        removeLocalProfile: { _, _ in
            throw AppFailure("Unimplemented local removal dependency.")
        },
        requireForeground: { throw AppFailure("Unimplemented foreground dependency.") },
        waitForForeground: { throw AppFailure("Unimplemented foreground dependency.") },
        cancelSensitiveOperation: {
            // Intentionally empty: the test dependency owns no sensitive context to cancel.
        }
    )
}
