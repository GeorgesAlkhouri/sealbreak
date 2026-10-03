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
    var loadLocalSetupState: @Sendable () async throws -> LocalSetupState
    var protectNewProfile: @Sendable (
        _ profile: ServerProfile,
        _ record: ShareRecord,
        _ reason: LocalizedStringResource
    ) async throws -> LocalPersistenceOutcome
    var resetLocalData: @Sendable () async throws -> Void
    var detectProduct: @Sendable (ServerProfile) async throws -> ServerProduct
    var dnssecStatus: @Sendable (String) async throws -> DNSSECStatus
    var status: @Sendable (ServerProfile) async throws -> SealStatus
    var submit: @Sendable (ShareRecord) async throws -> Void
    var readShareFragment: @Sendable (
        _ profileID: UUID,
        _ reason: LocalizedStringResource
    ) async throws -> ShareComparisonFragment
    var readShare: @Sendable (_ profileID: UUID, _ reason: LocalizedStringResource) async throws -> ShareRecord
    var replaceShare: @Sendable (
        _ expectedProfile: ServerProfile,
        _ replacement: ShareRecord,
        _ reason: LocalizedStringResource
    ) async throws -> Void
    var removeLocalProfile: @Sendable (
        _ profileID: UUID,
        _ reason: LocalizedStringResource
    ) async throws -> LocalPersistenceOutcome
    var requireForeground: @Sendable () async throws -> Void
    var waitForForeground: @Sendable () async throws -> Void
    var cancelSensitiveOperation: @Sendable () async -> Void

    package init(
        loadLocalSetupState: @escaping @Sendable () async throws -> LocalSetupState,
        protectNewProfile: @escaping @Sendable (
            _ profile: ServerProfile,
            _ record: ShareRecord,
            _ reason: LocalizedStringResource
        ) async throws -> LocalPersistenceOutcome,
        resetLocalData: @escaping @Sendable () async throws -> Void,
        detectProduct: @escaping @Sendable (ServerProfile) async throws -> ServerProduct,
        dnssecStatus: @escaping @Sendable (String) async throws -> DNSSECStatus,
        status: @escaping @Sendable (ServerProfile) async throws -> SealStatus,
        submit: @escaping @Sendable (ShareRecord) async throws -> Void,
        readShareFragment: @escaping @Sendable (
            _ profileID: UUID,
            _ reason: LocalizedStringResource
        ) async throws -> ShareComparisonFragment,
        readShare: @escaping @Sendable (_ profileID: UUID, _ reason: LocalizedStringResource) async throws -> ShareRecord,
        replaceShare: @escaping @Sendable (
            _ expectedProfile: ServerProfile,
            _ replacement: ShareRecord,
            _ reason: LocalizedStringResource
        ) async throws -> Void,
        removeLocalProfile: @escaping @Sendable (
            _ profileID: UUID,
            _ reason: LocalizedStringResource
        ) async throws -> LocalPersistenceOutcome,
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

extension DependencyValues {
    package var sealbreakClient: SealbreakClient {
        get { self[SealbreakClient.self] }
        set { self[SealbreakClient.self] = newValue }
    }
}

extension SealbreakClient {
    package static let unimplemented = Self(
        loadLocalSetupState: { throw AppFailure(LocalizedStringResource("Unimplemented local setup state dependency.", bundle: .module)) },
        protectNewProfile: { _, _, _ in
            throw AppFailure(LocalizedStringResource("Unimplemented setup protection dependency.", bundle: .module))
        },
        resetLocalData: { throw AppFailure(LocalizedStringResource("Unimplemented local-data reset dependency.", bundle: .module)) },
        detectProduct: { _ in throw AppFailure(LocalizedStringResource("Unimplemented server-product detection dependency.", bundle: .module)) },
        dnssecStatus: { _ in throw AppFailure(LocalizedStringResource("Unimplemented DNSSEC status dependency.", bundle: .module)) },
        status: { _ in throw AppFailure(LocalizedStringResource("Unimplemented seal-status dependency.", bundle: .module)) },
        submit: { _ in throw AppFailure(LocalizedStringResource("Unimplemented share submission dependency.", bundle: .module)) },
        readShareFragment: { _, _ in throw AppFailure(LocalizedStringResource("Unimplemented protected-share dependency.", bundle: .module)) },
        readShare: { _, _ in throw AppFailure(LocalizedStringResource("Unimplemented protected-share dependency.", bundle: .module)) },
        replaceShare: { _, _, _ in throw AppFailure(LocalizedStringResource("Unimplemented protected-share dependency.", bundle: .module)) },
        removeLocalProfile: { _, _ in
            throw AppFailure(LocalizedStringResource("Unimplemented local removal dependency.", bundle: .module))
        },
        requireForeground: { throw AppFailure(LocalizedStringResource("Unimplemented foreground dependency.", bundle: .module)) },
        waitForForeground: { throw AppFailure(LocalizedStringResource("Unimplemented foreground dependency.", bundle: .module)) },
        cancelSensitiveOperation: {
            // Intentionally empty: the test dependency owns no sensitive context to cancel.
        }
    )
}
