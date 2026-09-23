import ComposableArchitecture
import Foundation
import LocalAuthentication
import UIKit

extension SealbreakClient: DependencyKey {
    static var liveValue: Self {
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
            deleteProfile: { profileID in
                try await LiveSealbreakClientController.shared.deleteProfile(profileID)
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
            deleteShare: { profileID, reason in
                try await LiveSealbreakClientController.shared.deleteShare(
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
private final class LiveSealbreakClientController {
    static let shared = LiveSealbreakClientController()

    private let keychain = KeychainStore()
    private let profiles = ProfileStore()
    private let setupState = SetupStateStore()
    private let client = SealServerClient()
    private let dnssecResolver = DNSSECResolver.live
    private var activeContext: LAContext?

    func loadLocalSetupState() throws -> LocalSetupState {
        try resolveLocalSetupState(
            persistedState: setupState.load(),
            profiles: profiles.loadAll()
        )
    }

    func protectNewProfile(
        profile: ServerProfile,
        record: ShareRecord,
        reason: String
    ) async throws -> SetupProtectionOutcome {
        try await withAuthorizedContext(reason: reason) { context in
            do {
                guard try setupState.load() == nil else {
                    return .recoveryRequired(
                        "Local Sealbreak setup already exists or did not finish. Reset local data before continuing."
                    )
                }

                let storedProfiles = try profiles.loadAll()
                guard storedProfiles.isEmpty else {
                    return .recoveryRequired(
                        "Local profile data exists without a committed setup. Reset local Sealbreak data before continuing."
                    )
                }

                try setupState.begin(profileID: profile.id)
                try profiles.insert(profile)
                try keychain.insert(record, context: context)
                try setupState.commit(profileID: profile.id)
                return .protected
            } catch {
                return .recoveryRequired(
                    "Local setup could not be completed safely. Reset local Sealbreak data before continuing."
                )
            }
        }
    }

    func deleteProfile(_ profileID: UUID) throws {
        try profiles.delete(id: profileID)

        guard let state = try setupState.load() else {
            return
        }

        let storedProfileID: UUID
        switch state {
        case .pending(let id), .ready(let id):
            storedProfileID = id
        }

        if storedProfileID == profileID {
            try setupState.reset()
        }
    }

    func resetLocalData() throws {
        try requireForeground()
        try resetLocalStorage(
            deleteShares: {
                try keychain.deleteAll()
            },
            resetProfiles: {
                try profiles.reset()
            }
        )
        try setupState.reset()
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

    func readShare(profileID: UUID, reason: String) async throws -> ShareRecord {
        try await withAuthorizedContext(reason: reason) { context in
            try keychain.read(profileID: profileID, context: context)
        }
    }

    func replaceShare(
        expectedProfile: ServerProfile,
        replacement: ShareRecord,
        reason: String
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

    func deleteShare(profileID: UUID, reason: String) async throws {
        try await withAuthorizedContext(reason: reason) { context in
            try requireForeground()
            try keychain.delete(profileID: profileID, context: context)
        }
    }

    func requireForeground() throws {
        try Task.checkCancellation()
        guard UIApplication.shared.applicationState == .active else {
            throw AppFailure(
                "Sealbreak is not the active app. Return to it after the system dialog closes, then retry."
            )
        }
        guard UIApplication.shared.isProtectedDataAvailable else {
            throw AppFailure(
                "Protected iPhone data is unavailable. Unlock the device and retry in Sealbreak."
            )
        }
        guard !UIScreen.main.isCaptured else {
            throw AppFailure(
                "iPhone screen capture or mirroring is active. Stop it and retry directly on the unlocked device."
            )
        }
    }

    func waitForForeground() async throws {
        for _ in 0..<50 {
            try Task.checkCancellation()
            if UIApplication.shared.applicationState == .active {
                try requireForeground()
                return
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        try requireForeground()
    }

    func cancelSensitiveOperation() {
        activeContext?.invalidate()
        activeContext = nil
    }

    private func withAuthorizedContext<Value>(
        reason: String,
        operation: (LAContext) throws -> Value
    ) async throws -> Value {
        try requireForeground()

        let context = LAContext()
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
            throw AppFailure(
                "Face ID is unavailable, not enrolled, or locked out. Enable Face ID and a device passcode, or unlock the device in iOS before retrying. No app passcode fallback is offered."
            )
        }

        do {
            guard try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            ) else {
                throw AppFailure("Face ID did not authorize this action.")
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw AppFailure(
                "Face ID was cancelled or denied. No new share submission was started."
            )
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
