import Foundation

@MainActor
protocol AppServicing: AnyObject {
    func loadProfile() throws -> ServerProfile?
    func saveProfile(_ profile: ServerProfile) throws
    func deleteProfile() throws
    func status(_ profile: ServerProfile) async throws -> SealStatus
    func submit(_ record: ShareRecord) async throws
    func authorize(_ reason: String, action: @MainActor () async throws -> Void) async throws
    func readShare() throws -> ShareRecord
    func insertShare(_ record: ShareRecord) throws
    func replaceShare(_ record: ShareRecord) throws
    func deleteShare() throws
    func requireForeground() throws
    func waitForForeground() async throws
    func cancelSensitiveOperation()
}

#if canImport(UIKit)
import LocalAuthentication
import UIKit

@MainActor
final class LiveAppServices: AppServicing {
    private let keychain = KeychainStore()
    private let profiles = ProfileStore()
    private let client = OpenBaoClient()
    private var activeContext: LAContext?

    func loadProfile() throws -> ServerProfile? { try profiles.load() }
    func saveProfile(_ profile: ServerProfile) throws { try profiles.save(profile) }
    func deleteProfile() throws { try profiles.delete() }
    func status(_ profile: ServerProfile) async throws -> SealStatus { try await client.status(profile) }
    func submit(_ record: ShareRecord) async throws { try await client.submit(record) }

    func authorize(_ reason: String, action: @MainActor () async throws -> Void) async throws {
        let context = LAContext()
        context.localizedFallbackTitle = ""
        context.touchIDAuthenticationAllowableReuseDuration = 0
        activeContext = context
        defer {
            context.invalidate()
            activeContext = nil
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
        try await action()
    }

    func readShare() throws -> ShareRecord {
        guard let context = activeContext else { throw AppFailure("Face ID authorization context is unavailable.") }
        return try keychain.read(context: context)
    }

    func insertShare(_ record: ShareRecord) throws {
        guard let context = activeContext else { throw AppFailure("Face ID authorization context is unavailable.") }
        try keychain.insert(record, context: context)
    }

    func replaceShare(_ record: ShareRecord) throws {
        guard let context = activeContext else { throw AppFailure("Face ID authorization context is unavailable.") }
        try keychain.replace(record, context: context)
    }

    func deleteShare() throws {
        guard let context = activeContext else { throw AppFailure("Face ID authorization context is unavailable.") }
        try keychain.delete(context: context)
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
}
#endif
