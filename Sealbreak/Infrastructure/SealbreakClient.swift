import ComposableArchitecture
import Foundation

struct SealbreakClient: Sendable {
    var loadProfile: @Sendable () async throws -> ServerProfile?
    var saveProfile: @Sendable (ServerProfile) async throws -> Void
    var deleteProfile: @Sendable () async throws -> Void
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

extension SealbreakClient: DependencyKey {
    static var liveValue: Self {
        #if canImport(UIKit)
        Self(
            loadProfile: {
                try await LiveSealbreakClientController.shared.loadProfile()
            },
            saveProfile: { profile in
                try await LiveSealbreakClientController.shared.saveProfile(profile)
            },
            deleteProfile: {
                try await LiveSealbreakClientController.shared.deleteProfile()
            },
            status: { profile in
                try await LiveSealbreakClientController.shared.status(profile)
            },
            submit: { record in
                try await LiveSealbreakClientController.shared.submit(record)
            },
            readShare: { reason in
                try await LiveSealbreakClientController.shared.readShare(reason: reason)
            },
            insertShare: { record, reason in
                try await LiveSealbreakClientController.shared.insertShare(record, reason: reason)
            },
            replaceShare: { expectedProfile, replacement, reason in
                try await LiveSealbreakClientController.shared.replaceShare(
                    expectedProfile: expectedProfile,
                    replacement: replacement,
                    reason: reason
                )
            },
            deleteShare: { reason in
                try await LiveSealbreakClientController.shared.deleteShare(reason: reason)
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
        #else
        .unimplemented
        #endif
    }

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
        status: { _ in throw AppFailure("Unimplemented seal-status dependency.") },
        submit: { _ in throw AppFailure("Unimplemented share submission dependency.") },
        readShare: { _ in throw AppFailure("Unimplemented protected-share dependency.") },
        insertShare: { _, _ in throw AppFailure("Unimplemented protected-share dependency.") },
        replaceShare: { _, _, _ in throw AppFailure("Unimplemented protected-share dependency.") },
        deleteShare: { _ in throw AppFailure("Unimplemented protected-share dependency.") },
        requireForeground: { throw AppFailure("Unimplemented foreground dependency.") },
        waitForForeground: { throw AppFailure("Unimplemented foreground dependency.") },
        cancelSensitiveOperation: {}
    )
}

func normalizedAppFailure(_ error: Error) -> AppFailure {
    if let failure = error as? AppFailure {
        return failure
    }
    return AppFailure("Operation failed. No sensitive diagnostic data was recorded.")
}

#if canImport(UIKit)
import LocalAuthentication
import UIKit

@MainActor
private final class LiveSealbreakClientController {
    static let shared = LiveSealbreakClientController()

    private let keychain = KeychainStore()
    private let profiles = ProfileStore()
    private let client = OpenBaoClient()
    private var activeContext: LAContext?

    func loadProfile() throws -> ServerProfile? {
        try profiles.load()
    }

    func saveProfile(_ profile: ServerProfile) throws {
        try profiles.save(profile)
    }

    func deleteProfile() throws {
        try profiles.delete()
    }

    func status(_ profile: ServerProfile) async throws -> SealStatus {
        try await client.status(profile)
    }

    func submit(_ record: ShareRecord) async throws {
        try await client.submit(record)
    }

    func readShare(reason: String) async throws -> ShareRecord {
        try await withAuthorizedContext(reason: reason) { context in
            try keychain.read(context: context)
        }
    }

    func insertShare(_ record: ShareRecord, reason: String) async throws {
        try await withAuthorizedContext(reason: reason) { context in
            try requireForeground()
            try keychain.insert(record, context: context)
        }
    }

    func replaceShare(
        expectedProfile: ServerProfile,
        replacement: ShareRecord,
        reason: String
    ) async throws {
        try await withAuthorizedContext(reason: reason) { context in
            var existing = try keychain.read(context: context)
            defer { existing.share.removeAll(keepingCapacity: false) }
            guard existing.profile == expectedProfile else {
                throw AppFailure("Target binding mismatch. Restore the protected profile first.")
            }
            try requireForeground()
            try keychain.replace(replacement, context: context)
        }
    }

    func deleteShare(reason: String) async throws {
        try await withAuthorizedContext(reason: reason) { context in
            try requireForeground()
            try keychain.delete(context: context)
        }
    }

    func requireForeground() throws {
        try Task.checkCancellation()
        guard UIApplication.shared.applicationState == .active else {
            throw AppFailure("Sealbreak is not the active app. Return to it after the system dialog closes, then retry.")
        }
        guard UIApplication.shared.isProtectedDataAvailable else {
            throw AppFailure("Protected iPhone data is unavailable. Unlock the device and retry in Sealbreak.")
        }
        guard !UIScreen.main.isCaptured else {
            throw AppFailure("iPhone screen capture or mirroring is active. Stop it and retry directly on the unlocked device.")
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
            throw AppFailure("Face ID is unavailable, not enrolled, or locked out. Enable Face ID and a device passcode, or unlock the device in iOS before retrying. No app passcode fallback is offered.")
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
            throw AppFailure("Face ID was cancelled or denied. No new share submission was started.")
        }

        try await waitForForeground()
        context.interactionNotAllowed = true
        try requireForeground()
        return try operation(context)
    }
}
#endif
