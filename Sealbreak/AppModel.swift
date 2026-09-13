import SwiftUI
import LocalAuthentication
import UIKit

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var profile: ServerProfile?
    @Published private(set) var status: SealStatus?
    @Published private(set) var busy = false
    @Published private(set) var activity = ""
    @Published private(set) var notice = "Prototype: use disposable test shares until the security checks in issue #1 have been completed."

    private let keychain = KeychainStore()
    private let profiles = ProfileStore()
    private let client = OpenBaoClient()
    private var operation: Task<Void, Never>?
    private var activeContext: LAContext?

    init() {
        do {
            profile = try profiles.load()
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
            self.status = try await self.client.status(target)
            self.notice = self.status?.supportsUnseal == true
                ? "Status checked. Nothing is sent automatically."
                : "Only initialized Shamir seals are supported. Initialization, auto-unseal, and seal migration are not supported."
        }
    }

    func unseal() {
        guard canUnseal, let target = profile else { return }
        run("Checking target…") {
            self.status = nil
            let before = try await self.client.status(target)
            self.status = before
            guard before.supportsUnseal else {
                throw AppFailure("This target does not support manual Shamir unseal.")
            }
            guard before.sealed else {
                self.notice = "Already unsealed. No share was read or sent."
                return
            }

            try await self.authorize("Send one Shamir share to \(target.origin)") { context in
                var record = try self.keychain.read(context: context)
                defer {
                    record.share.removeAll(keepingCapacity: false)
                }
                guard record.profile == target else {
                    throw AppFailure("Target binding mismatch. Nothing was sent. Restore the protected profile; changing the display file cannot retarget a share.")
                }
                try self.requireForeground()
                self.activity = "Submitting one share…"
                self.status = nil

                do {
                    try await self.client.submit(record)
                    record.share.removeAll(keepingCapacity: false)
                    self.activity = "Verifying seal status…"
                    let after = try await self.client.status(target)
                    self.status = after
                    guard after.supportsUnseal else {
                        throw AppFailure("Unexpected seal configuration after submission.")
                    }
                    self.notice = after.sealed
                        ? "Submission completed; still sealed. Progress: \(after.progress)/\(after.t). Other holders must submit their own shares to this same node."
                        : "Verified: this endpoint now reports unsealed. This does not prove which operator completed the quorum."
                } catch {
                    self.status = nil
                    if error is CancellationError {
                        throw error
                    }
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
            var record = try ShareRecord(
                profile: ServerProfile(name: name, address: address),
                input: input
            )
            defer {
                record.share.removeAll(keepingCapacity: false)
            }

            try await self.authorize("Protect this share for \(record.profile.origin)") { context in
                try self.requireForeground()
                try self.keychain.insert(record, context: context)
                self.useProfile(
                    record.profile,
                    message: "Share saved with device-bound biometric protection. Check status to begin."
                )
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
            defer {
                replacement.share.removeAll(keepingCapacity: false)
            }

            try await self.authorize("Replace the local share for \(target.origin)") { context in
                var existing = try self.keychain.read(context: context)
                defer {
                    existing.share.removeAll(keepingCapacity: false)
                }
                guard existing.profile == target else {
                    throw AppFailure("Target binding mismatch. Restore the protected profile first.")
                }
                try self.requireForeground()
                try self.keychain.replace(replacement, context: context)
                self.status = nil
                self.notice = "Local share replaced. This does not rotate OpenBao keys; server-side rekeying is a separate operation."
            }
        }
    }

    func restoreProfile() {
        run("Restoring local profile…") {
            try await self.authorize("Restore the server profile from the protected Keychain record") { context in
                var record = try self.keychain.read(context: context)
                defer {
                    record.share.removeAll(keepingCapacity: false)
                }
                self.useProfile(
                    record.profile,
                    message: "Protected target restored. No share was transmitted or exported."
                )
            }
        }
    }

    func removeLocalData() {
        run("Removing local data…") {
            try await self.authorize("Permanently remove Sealbreak’s local share; independent recovery will be required") { context in
                try self.requireForeground()
                try self.keychain.delete(context: context)
                self.profile = nil
                self.status = nil
                do {
                    try self.profiles.delete()
                    self.notice = "Local share removed. Copies elsewhere remain valid; only OpenBao rekeying replaces the server’s Shamir shares."
                } catch {
                    self.notice = "The Keychain share was removed, but its non-secret display file could not be removed. Restart may show stale metadata."
                }
            }
        }
    }

    func cancelForPrivacy() {
        operation?.cancel()
        activeContext?.invalidate()
        status = nil
        if busy {
            notice = "Operation interrupted. Check status on return; an already submitted request cannot be recalled."
        }
    }

    private func useProfile(_ profile: ServerProfile, message: String) {
        self.profile = profile
        self.status = nil
        do {
            try profiles.save(profile)
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
                self.activeContext?.invalidate()
                self.activeContext = nil
                self.busy = false
                self.activity = ""
                self.operation = nil
            }
            do {
                try await self.waitForForeground()
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

    private func requireForeground() throws {
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

    private func waitForForeground() async throws {
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

    private func authorize(
        _ reason: String,
        action: @MainActor (LAContext) async throws -> Void
    ) async throws {
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

        activity = "Waiting for Face ID…"
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
        try await action(context)
    }
}
