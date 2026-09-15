import Foundation
import SwiftUI

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

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var profile: ServerProfile?
    @Published private(set) var status: SealStatus?
    @Published private(set) var busy = false
    @Published private(set) var activity = ""
    @Published private(set) var notice = "Prototype: use disposable test shares until the security checks in issue #1 have been completed."

    private let services: AppServicing
    private var operation: Task<Void, Never>?

    init(services: AppServicing) {
        self.services = services
        do {
            profile = try services.loadProfile()
        } catch {
            notice = "The display profile could not be read. Restore its protected copy from Keychain."
        }
    }

    var canUnseal: Bool {
        !busy && profile != nil && status?.supportsUnseal == true && status?.sealed == true
    }

    func refresh() {
        guard let target = profile else { return }
        run("Checking seal status…") {
            self.status = nil
            self.status = try await self.services.status(target)
            self.notice = self.status?.supportsUnseal == true
                ? "Status checked. Nothing is sent automatically."
                : "Only initialized Shamir seals are supported. Initialization, auto-unseal, and seal migration are not supported."
        }
    }

    func unseal() {
        guard canUnseal, let target = profile else { return }
        run("Checking target…") {
            self.status = nil
            let before = try await self.services.status(target)
            self.status = before
            guard before.supportsUnseal else {
                throw AppFailure("This target does not support manual Shamir unseal.")
            }
            guard before.sealed else {
                self.notice = "Already unsealed. No share was read or sent."
                return
            }

            self.activity = "Waiting for Face ID…"
            try await self.services.authorize("Send one Shamir share to \(target.origin)") {
                var record = try self.services.readShare()
                defer { record.share.removeAll(keepingCapacity: false) }
                guard record.profile == target else {
                    throw AppFailure("Target binding mismatch. Nothing was sent. Restore the protected profile; changing the display file cannot retarget a share.")
                }
                try self.services.requireForeground()
                self.activity = "Submitting one share…"
                self.status = nil

                do {
                    try await self.services.submit(record)
                    record.share.removeAll(keepingCapacity: false)
                    self.activity = "Verifying seal status…"
                    let after = try await self.services.status(target)
                    self.status = after
                    guard after.supportsUnseal else {
                        throw AppFailure("Unexpected seal configuration after submission.")
                    }
                    self.notice = after.sealed
                        ? "Submission completed; still sealed. Progress: \(after.progress)/\(after.t). Other holders must submit their own shares to this same node."
                        : "Verified: this endpoint now reports unsealed. This does not prove which operator completed the quorum."
                } catch {
                    self.status = nil
                    if error is CancellationError { throw error }
                    let detail = (error as? AppFailure)?.message ?? "Request failed."
                    throw AppFailure("\(detail) The final outcome is unknown. Check status before another attempt; a request already received cannot be undone.")
                }
            }
        }
    }

    func importShare(name: String, address: String, input: String, recoveryConfirmed: Bool) {
        guard profile == nil else { return }
        run("Importing share…") {
            guard recoveryConfirmed else {
                throw AppFailure("Confirm an independent recovery copy before importing.")
            }
            var record = try ShareRecord(profile: ServerProfile(name: name, address: address), input: input)
            defer { record.share.removeAll(keepingCapacity: false) }

            self.activity = "Waiting for Face ID…"
            try await self.services.authorize("Protect this share for \(record.profile.origin)") {
                try self.services.requireForeground()
                try self.services.insertShare(record)
                self.useProfile(record.profile, message: "Share saved with device-bound biometric protection. Check status to begin.")
            }
        }
    }

    func replaceShare(input: String, recoveryConfirmed: Bool) {
        guard let target = profile else { return }
        run("Replacing share…") {
            guard recoveryConfirmed else {
                throw AppFailure("Confirm recovery for the replacement share before saving.")
            }
            var replacement = try ShareRecord(profile: target, input: input)
            defer { replacement.share.removeAll(keepingCapacity: false) }

            self.activity = "Waiting for Face ID…"
            try await self.services.authorize("Replace the local share for \(target.origin)") {
                var existing = try self.services.readShare()
                defer { existing.share.removeAll(keepingCapacity: false) }
                guard existing.profile == target else {
                    throw AppFailure("Target binding mismatch. Restore the protected profile first.")
                }
                try self.services.requireForeground()
                try self.services.replaceShare(replacement)
                self.status = nil
                self.notice = "Local share replaced. This does not rotate OpenBao keys; server-side rekeying is a separate operation."
            }
        }
    }

    func restoreProfile() {
        run("Restoring local profile…") {
            self.activity = "Waiting for Face ID…"
            try await self.services.authorize("Restore the server profile from the protected Keychain record") {
                var record = try self.services.readShare()
                defer { record.share.removeAll(keepingCapacity: false) }
                self.useProfile(record.profile, message: "Protected target restored. No share was transmitted or exported.")
            }
        }
    }

    func removeLocalData() {
        run("Removing local data…") {
            self.activity = "Waiting for Face ID…"
            try await self.services.authorize("Permanently remove Sealbreak’s local share; independent recovery will be required") {
                try self.services.requireForeground()
                try self.services.deleteShare()
                self.profile = nil
                self.status = nil
                do {
                    try self.services.deleteProfile()
                    self.notice = "Local share removed. Copies elsewhere remain valid; only OpenBao rekeying replaces the server’s Shamir shares."
                } catch {
                    self.notice = "The Keychain share was removed, but its non-secret display file could not be removed. Restart may show stale metadata."
                }
            }
        }
    }

    func cancelForPrivacy() {
        operation?.cancel()
        services.cancelSensitiveOperation()
        status = nil
        if busy {
            notice = "Operation interrupted. Check status on return; an already submitted request cannot be recalled."
        }
    }

    private func useProfile(_ profile: ServerProfile, message: String) {
        self.profile = profile
        self.status = nil
        do {
            try services.saveProfile(profile)
            notice = message
        } catch {
            notice = "Protected share exists, but display metadata could not be saved. Use Restore profile from Keychain on the next launch."
        }
    }

    private func run(_ activity: String, work: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true
        self.activity = activity
        operation = Task { @MainActor in
            defer {
                self.services.cancelSensitiveOperation()
                self.busy = false
                self.activity = ""
                self.operation = nil
            }
            do {
                try await self.services.waitForForeground()
                try await work()
            } catch is CancellationError {
                self.status = nil
                self.notice = "Operation cancelled. Refresh status before retrying; a submitted request may already have been processed."
            } catch let error as AppFailure {
                self.notice = error.message
            } catch {
                self.notice = "Operation failed. No sensitive diagnostic data was recorded."
            }
        }
    }
}

#if canImport(UIKit)
extension AppModel {
    convenience init() {
        self.init(services: LiveAppServices())
    }
}
#endif
