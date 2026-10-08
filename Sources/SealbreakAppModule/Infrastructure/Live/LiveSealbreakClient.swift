import Foundation
import LocalAuthentication
import SealbreakCore
import SealbreakInfrastructure
import UIKit

extension SealbreakClient {
    package static var live: Self {
        Self(
            loadLocalSetupState: {
                try await LiveSealbreakClientController.shared.loadLocalSetupState()
            },
            protectNewProfile: { profile, record, reason in
                try await LiveSealbreakClientController.shared.protectNewProfile(
                    profile: profile,
                    record: record,
                    reason: reason
                )
            },
            resetLocalData: {
                try await LiveSealbreakClientController.shared.resetLocalData()
            },
            detectProduct: { profile in
                try await LiveSealbreakClientController.shared.detectProduct(profile)
            },
            dnssecStatus: { host in
                await LiveSealbreakClientController.shared.dnssecStatus(host)
            },
            status: { profile in
                try await LiveSealbreakClientController.shared.status(profile)
            },
            submit: { record in
                try await LiveSealbreakClientController.shared.submit(record)
            },
            readShareFragment: { profileID, reason in
                try await LiveSealbreakClientController.shared.readShareFragment(
                    profileID: profileID,
                    reason: reason
                )
            },
            readShare: { profileID, reason in
                try await LiveSealbreakClientController.shared.readShare(
                    profileID: profileID,
                    reason: reason
                )
            },
            replaceShare: { expectedProfile, replacement, reason in
                try await LiveSealbreakClientController.shared.replaceShare(
                    expectedProfile: expectedProfile,
                    replacement: replacement,
                    reason: reason
                )
            },
            removeLocalProfile: { profileID, reason in
                try await LiveSealbreakClientController.shared.removeLocalProfile(
                    profileID: profileID,
                    reason: reason
                )
            },
            requireForeground: {
                try await LiveSealbreakClientController.shared.requireForeground()
            },
            waitForForeground: {
                try await LiveSealbreakClientController.shared.waitForForeground()
            },
            cancelSensitiveOperation: {
                await LiveSealbreakClientController.shared.cancelSensitiveOperation()
            }
        )
    }
}

@MainActor
final class LiveSealbreakClientController {
    static let shared = LiveSealbreakClientController()

    private let keychain: KeychainStore
    private let profiles: ProfileStore
    private let client: SealServerClient
    private let dnssecResolver = DNSSECResolver.live
    private let makeContext: () -> LAContext
    private let applicationState: () -> UIApplication.State
    private let protectedDataAvailable: () -> Bool
    private let sceneCaptured: @MainActor () -> Bool
    private let sleep: (Duration) async throws -> Void
    private var activeContext: LAContext?

    init(
        keychain: KeychainStore = KeychainStore(),
        profiles: ProfileStore = ProfileStore(),
        client: SealServerClient = SealServerClient(),
        makeContext: @escaping () -> LAContext = { LAContext() },
        applicationState: @escaping () -> UIApplication.State = { UIApplication.shared.applicationState },
        protectedDataAvailable: @escaping () -> Bool = { UIApplication.shared.isProtectedDataAvailable },
        sceneCaptured: @escaping @MainActor () -> Bool = { LiveSealbreakClientController.isForegroundSceneCaptured },
        sleep: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.keychain = keychain
        self.profiles = profiles
        self.client = client
        self.makeContext = makeContext
        self.applicationState = applicationState
        self.protectedDataAvailable = protectedDataAvailable
        self.sceneCaptured = sceneCaptured
        self.sleep = sleep
    }

    func loadLocalSetupState() throws -> LocalSetupState {
        try resolveLocalSetupState(
            profiles: profiles.loadAll()
        )
    }

    func protectNewProfile(
        profile: ServerProfile,
        record: ShareRecord,
        reason: LocalizedStringResource
    ) async throws -> LocalPersistenceOutcome {
        try await withAuthorizedContext(reason: reason) { context in
            createLocalProfileTransaction(
                beginProfile: {
                    try profiles.begin(profile)
                },
                insertShare: {
                    try keychain.insert(record, context: context)
                },
                commitProfile: {
                    try profiles.commit(id: profile.id)
                }
            )
        }
    }

    func removeLocalProfile(
        profileID: UUID,
        reason: LocalizedStringResource
    ) async throws -> LocalPersistenceOutcome {
        try await withAuthorizedContext(reason: reason) { context in
            removeLocalProfileTransaction(
                beginRemoval: {
                    try profiles.beginRemoval(id: profileID)
                },
                deleteShare: {
                    try keychain.delete(profileID: profileID, context: context)
                },
                deleteProfile: {
                    try profiles.delete(id: profileID)
                }
            )
        }
    }

    func resetLocalData() throws {
        try requireForeground()
        try resetLocalStorage(
            prepareReset: {
                try profiles.prepareForReset()
            },
            deleteShares: {
                try keychain.deleteAll()
            },
            resetProfiles: {
                try profiles.reset()
            }
        )
    }

    func detectProduct(_ profile: ServerProfile) async throws -> ServerProduct {
        try await client.detectProduct(profile)
    }

    func dnssecStatus(_ host: String) async -> DNSSECStatus {
        await dnssecResolver.status(for: host)
    }

    func status(_ profile: ServerProfile) async throws -> SealStatus {
        try await client.status(profile)
    }

    func submit(_ record: ShareRecord) async throws {
        try await client.submit(record)
    }

    func readShareFragment(
        profileID: UUID,
        reason: LocalizedStringResource
    ) async throws -> ShareComparisonFragment {
        try await withAuthorizedContext(reason: reason) { context in
            var record = try keychain.read(profileID: profileID, context: context)
            defer {
                record.share.removeAll(keepingCapacity: false)
            }
            return ShareComparisonFragment(validatedShare: record.share)
        }
    }

    func readShare(profileID: UUID, reason: LocalizedStringResource) async throws -> ShareRecord {
        try await withAuthorizedContext(reason: reason) { context in
            try keychain.read(profileID: profileID, context: context)
        }
    }

    func replaceShare(
        expectedProfile: ServerProfile,
        replacement: ShareRecord,
        reason: LocalizedStringResource
    ) async throws {
        try await withAuthorizedContext(reason: reason) { context in
            try replaceShareIfBound(
                expectedProfile: expectedProfile,
                replacement: replacement,
                readExisting: {
                    try keychain.read(profileID: expectedProfile.id, context: context)
                },
                beforeReplace: {
                    try requireForeground()
                },
                replace: { record in
                    try keychain.replace(record, context: context)
                }
            )
        }
    }

    func requireForeground() throws {
        try Task.checkCancellation()
        guard applicationState() == .active else {
            throw AppFailure(
                LocalizedStringResource("Sealbreak is not the active app. Return to it after the system dialog closes, then retry.", bundle: .module)
            )
        }
        guard protectedDataAvailable() else {
            throw AppFailure(
                LocalizedStringResource("Protected iPhone data is unavailable. Unlock the device and retry in Sealbreak.", bundle: .module)
            )
        }
        guard !sceneCaptured() else {
            throw AppFailure(
                LocalizedStringResource("iPhone screen capture or mirroring is active. Stop it and retry directly on the unlocked device.", bundle: .module)
            )
        }
    }

    private static var isForegroundSceneCaptured: Bool {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .contains { $0.traitCollection.sceneCaptureState == .active }
    }

    func waitForForeground() async throws {
        for _ in 0..<50 {
            try Task.checkCancellation()
            if applicationState() == .active {
                try requireForeground()
                return
            }
            try await sleep(.milliseconds(100))
        }
        try requireForeground()
    }

    func cancelSensitiveOperation() {
        activeContext?.invalidate()
        activeContext = nil
    }

    private func faceIDFailure(from error: NSError?) -> AppFailure {
        guard let error,
              let code = LAError.Code(rawValue: error.code) else {
            return AppFailure(LocalizedStringResource("Face ID isn’t available for this action.", bundle: .module))
        }

        switch code {
        case .biometryNotEnrolled:
            return AppFailure(
                LocalizedStringResource("Face ID isn’t set up. Set up Face ID in Settings, then try again.", bundle: .module)
            )
        case .biometryLockout:
            return AppFailure(
                LocalizedStringResource("Face ID is locked. Unlock your iPhone with the device passcode, then try again.", bundle: .module)
            )
        case .passcodeNotSet:
            return AppFailure(
                LocalizedStringResource("A device passcode is required before Face ID can be used.", bundle: .module)
            )
        case .biometryNotAvailable:
            return AppFailure(LocalizedStringResource("Face ID isn’t available for this action.", bundle: .module))
        case .userCancel, .appCancel, .systemCancel:
            return AppFailure(
                feedback: .warning(
                    LocalizedStringResource("Face ID was cancelled or denied. No new share submission was started.", bundle: .module)
                )
            )
        default:
            return AppFailure(LocalizedStringResource("Face ID did not authorize this action.", bundle: .module))
        }
    }

    private func withAuthorizedContext<Value>(
        reason: LocalizedStringResource,
        operation: (LAContext) throws -> Value
    ) async throws -> Value {
        try requireForeground()

        let context = makeContext()
        context.localizedFallbackTitle = ""
        context.touchIDAuthenticationAllowableReuseDuration = 0
        activeContext = context
        defer {
            context.invalidate()
            if activeContext === context {
                activeContext = nil
            }
        }

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error),
              context.biometryType == .faceID else {
            throw faceIDFailure(from: error)
        }

        do {
            guard try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: String(localized: reason)
            ) else {
                throw AppFailure(LocalizedStringResource("Face ID did not authorize this action.", bundle: .module))
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw faceIDFailure(from: error as NSError)
        }

        try await waitForForeground()
        guard activeContext === context else {
            throw CancellationError()
        }
        context.interactionNotAllowed = true
        try requireForeground()
        return try operation(context)
    }
}
