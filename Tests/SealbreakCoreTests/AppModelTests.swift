import Foundation
import Testing
@testable import SealbreakCore

private enum StubError: Error {
    case failure
}

@MainActor
private final class StubServices: AppServicing {
    var loadedProfile: ServerProfile?
    var loadError: Error?
    var saveError: Error?
    var deleteProfileError: Error?
    var statusResults: [Result<SealStatus, Error>] = []
    var submitError: Error?
    var authorizeError: Error?
    var readError: Error?
    var insertError: Error?
    var replaceError: Error?
    var deleteShareError: Error?
    var foregroundError: Error?
    var waitError: Error?
    var storedShare: ShareRecord?
    var suspendStatus = false

    var savedProfiles: [ServerProfile] = []
    var submittedRecords: [ShareRecord] = []
    var insertedRecords: [ShareRecord] = []
    var replacedRecords: [ShareRecord] = []
    var statusCalls = 0
    var authorizeCalls = 0
    var readCalls = 0
    var deleteShareCalls = 0
    var deleteProfileCalls = 0
    var foregroundCalls = 0
    var waitCalls = 0
    var cancelCalls = 0

    func loadProfile() throws -> ServerProfile? {
        if let loadError { throw loadError }
        return loadedProfile
    }

    func saveProfile(_ profile: ServerProfile) throws {
        if let saveError { throw saveError }
        savedProfiles.append(profile)
        loadedProfile = profile
    }

    func deleteProfile() throws {
        deleteProfileCalls += 1
        if let deleteProfileError { throw deleteProfileError }
        loadedProfile = nil
    }

    func status(_ profile: ServerProfile) async throws -> SealStatus {
        statusCalls += 1
        if suspendStatus {
            try await Task.sleep(for: .seconds(60))
        }
        guard !statusResults.isEmpty else { throw StubError.failure }
        return try statusResults.removeFirst().get()
    }

    func submit(_ record: ShareRecord) async throws {
        submittedRecords.append(record)
        if let submitError { throw submitError }
    }

    func authorize(_ reason: String, action: @MainActor () async throws -> Void) async throws {
        authorizeCalls += 1
        if let authorizeError { throw authorizeError }
        try await action()
    }

    func readShare() throws -> ShareRecord {
        readCalls += 1
        if let readError { throw readError }
        guard let storedShare else { throw StubError.failure }
        return storedShare
    }

    func insertShare(_ record: ShareRecord) throws {
        if let insertError { throw insertError }
        insertedRecords.append(record)
        storedShare = record
    }

    func replaceShare(_ record: ShareRecord) throws {
        if let replaceError { throw replaceError }
        replacedRecords.append(record)
        storedShare = record
    }

    func deleteShare() throws {
        deleteShareCalls += 1
        if let deleteShareError { throw deleteShareError }
        storedShare = nil
    }

    func requireForeground() throws {
        foregroundCalls += 1
        if let foregroundError { throw foregroundError }
    }

    func waitForForeground() async throws {
        waitCalls += 1
        if let waitError { throw waitError }
    }

    func cancelSensitiveOperation() {
        cancelCalls += 1
    }
}

@MainActor
struct AppModelTests {
    private let origin = "https://bao.example.com"
    private let share = String(repeating: "a", count: 64)

    private func profile(_ name: String = "OpenBao") throws -> ServerProfile {
        try ServerProfile(name: name, address: origin)
    }

    private func record(_ profile: ServerProfile) throws -> ShareRecord {
        try ShareRecord(profile: profile, input: share)
    }

    private func status(
        sealed: Bool = true,
        type: String = "shamir",
        initialized: Bool = true,
        threshold: Int = 3,
        shares: Int = 5,
        progress: Int = 0,
        migration: Bool? = false,
        recoverySeal: Bool? = false
    ) -> SealStatus {
        SealStatus(
            type: type,
            initialized: initialized,
            sealed: sealed,
            t: threshold,
            n: shares,
            progress: progress,
            migration: migration,
            recoverySeal: recoverySeal
        )
    }

    private func settle(_ model: AppModel) async {
        for _ in 0..<1_000 where model.busy {
            await Task.yield()
        }
    }

    @Test
    func initializationLoadsProfileAndHandlesFailure() throws {
        let target = try profile()
        let services = StubServices()
        services.loadedProfile = target
        let model = AppModel(services: services)
        #expect(model.profile == target)
        #expect(!model.canUnseal)

        let failing = StubServices()
        failing.loadError = StubError.failure
        let failedModel = AppModel(services: failing)
        #expect(failedModel.profile == nil)
        #expect(failedModel.notice.contains("could not be read"))
    }

    @Test
    func refreshCoversSupportedUnsupportedAndErrors() async throws {
        let empty = StubServices()
        let emptyModel = AppModel(services: empty)
        emptyModel.refresh()
        #expect(empty.statusCalls == 0)

        let services = StubServices()
        services.loadedProfile = try profile()
        services.statusResults = [.success(status())]
        let model = AppModel(services: services)
        model.refresh()
        await settle(model)
        #expect(model.status?.sealed == true)
        #expect(model.notice == "Status checked. Nothing is sent automatically.")
        #expect(model.canUnseal)

        services.statusResults = [.success(status(type: "transit", threshold: 0, shares: 0, recoverySeal: true))]
        model.refresh()
        await settle(model)
        #expect(model.notice.contains("Only initialized Shamir seals"))
        #expect(!model.canUnseal)

        services.statusResults = [.failure(AppFailure("status failed"))]
        model.refresh()
        await settle(model)
        #expect(model.notice == "status failed")

        services.waitError = StubError.failure
        model.refresh()
        await settle(model)
        #expect(model.notice == "Operation failed. No sensitive diagnostic data was recorded.")
    }

    @Test
    func importShareCoversGuardsSuccessAndFailures() async throws {
        let services = StubServices()
        let model = AppModel(services: services)

        model.importShare(name: "OpenBao", address: origin, input: share, recoveryConfirmed: false)
        await settle(model)
        #expect(model.notice == "Confirm an independent recovery copy before importing.")

        model.importShare(name: "OpenBao", address: origin, input: share, recoveryConfirmed: true)
        await settle(model)
        #expect(model.profile?.origin == origin)
        #expect(services.insertedRecords.count == 1)
        #expect(services.savedProfiles.count == 1)
        #expect(model.notice.contains("Share saved"))

        let calls = services.authorizeCalls
        model.importShare(name: "Other", address: origin, input: share, recoveryConfirmed: true)
        #expect(services.authorizeCalls == calls)

        let saveFailure = StubServices()
        saveFailure.saveError = StubError.failure
        let saveModel = AppModel(services: saveFailure)
        saveModel.importShare(name: "OpenBao", address: origin, input: share, recoveryConfirmed: true)
        await settle(saveModel)
        #expect(saveModel.profile != nil)
        #expect(saveModel.notice.contains("display metadata could not be saved"))

        let authFailure = StubServices()
        authFailure.authorizeError = AppFailure("auth failed")
        let authModel = AppModel(services: authFailure)
        authModel.importShare(name: "OpenBao", address: origin, input: share, recoveryConfirmed: true)
        await settle(authModel)
        #expect(authModel.notice == "auth failed")

        let foregroundFailure = StubServices()
        foregroundFailure.foregroundError = AppFailure("foreground failed")
        let foregroundModel = AppModel(services: foregroundFailure)
        foregroundModel.importShare(name: "OpenBao", address: origin, input: share, recoveryConfirmed: true)
        await settle(foregroundModel)
        #expect(foregroundModel.notice == "foreground failed")

        let insertFailure = StubServices()
        insertFailure.insertError = AppFailure("insert failed")
        let insertModel = AppModel(services: insertFailure)
        insertModel.importShare(name: "OpenBao", address: origin, input: share, recoveryConfirmed: true)
        await settle(insertModel)
        #expect(insertModel.notice == "insert failed")
    }

    @Test
    func replaceShareCoversGuardsBindingAndSuccess() async throws {
        let empty = StubServices()
        let emptyModel = AppModel(services: empty)
        emptyModel.replaceShare(input: share, recoveryConfirmed: true)
        #expect(empty.authorizeCalls == 0)

        let target = try profile()
        let services = StubServices()
        services.loadedProfile = target
        services.storedShare = try record(target)
        let model = AppModel(services: services)

        model.replaceShare(input: share, recoveryConfirmed: false)
        await settle(model)
        #expect(model.notice.contains("Confirm recovery"))

        services.storedShare = try record(profile("Other"))
        model.replaceShare(input: share, recoveryConfirmed: true)
        await settle(model)
        #expect(model.notice.contains("Target binding mismatch"))

        services.storedShare = try record(target)
        let replacement = String(repeating: "b", count: 64)
        model.replaceShare(input: replacement, recoveryConfirmed: true)
        await settle(model)
        #expect(services.replacedRecords.last?.share == replacement)
        #expect(model.notice.contains("Local share replaced"))

        services.readError = AppFailure("read failed")
        model.replaceShare(input: share, recoveryConfirmed: true)
        await settle(model)
        #expect(model.notice == "read failed")
        services.readError = nil

        services.replaceError = AppFailure("replace failed")
        model.replaceShare(input: share, recoveryConfirmed: true)
        await settle(model)
        #expect(model.notice == "replace failed")
    }

    @Test
    func restoreProfileCoversSuccessAndSaveFailure() async throws {
        let target = try profile()
        let services = StubServices()
        services.storedShare = try record(target)
        let model = AppModel(services: services)

        model.restoreProfile()
        await settle(model)
        #expect(model.profile == target)
        #expect(model.notice.contains("Protected target restored"))

        let failing = StubServices()
        failing.storedShare = try record(target)
        failing.saveError = StubError.failure
        let failingModel = AppModel(services: failing)
        failingModel.restoreProfile()
        await settle(failingModel)
        #expect(failingModel.notice.contains("display metadata could not be saved"))
    }

    @Test
    func removeLocalDataCoversSuccessAndFailures() async throws {
        let target = try profile()
        let services = StubServices()
        services.loadedProfile = target
        services.storedShare = try record(target)
        let model = AppModel(services: services)
        model.removeLocalData()
        await settle(model)
        #expect(model.profile == nil)
        #expect(services.deleteShareCalls == 1)
        #expect(services.deleteProfileCalls == 1)
        #expect(model.notice.contains("Local share removed"))

        let profileFailure = StubServices()
        profileFailure.loadedProfile = target
        profileFailure.storedShare = try record(target)
        profileFailure.deleteProfileError = StubError.failure
        let profileFailureModel = AppModel(services: profileFailure)
        profileFailureModel.removeLocalData()
        await settle(profileFailureModel)
        #expect(profileFailureModel.notice.contains("display file could not be removed"))

        let shareFailure = StubServices()
        shareFailure.loadedProfile = target
        shareFailure.storedShare = try record(target)
        shareFailure.deleteShareError = AppFailure("delete failed")
        let shareFailureModel = AppModel(services: shareFailure)
        shareFailureModel.removeLocalData()
        await settle(shareFailureModel)
        #expect(shareFailureModel.notice == "delete failed")
    }

    @Test
    func unsealCoversAllBehaviorBranches() async throws {
        let target = try profile()
        let services = StubServices()
        services.loadedProfile = target
        services.storedShare = try record(target)
        services.statusResults = [.success(status())]
        let model = AppModel(services: services)

        model.unseal()
        #expect(services.statusCalls == 0)

        model.refresh()
        await settle(model)
        #expect(model.canUnseal)

        services.statusResults = [.success(status(type: "transit", threshold: 0, shares: 0, recoverySeal: true))]
        model.unseal()
        await settle(model)
        #expect(model.notice == "This target does not support manual Shamir unseal.")

        services.statusResults = [.success(status(sealed: false))]
        services.statusResults.insert(.success(status()), at: 0)
        model.refresh()
        await settle(model)
        model.unseal()
        await settle(model)
        #expect(model.notice == "Already unsealed. No share was read or sent.")

        services.statusResults = [.success(status())]
        model.refresh()
        await settle(model)
        services.storedShare = try record(profile("Other"))
        services.statusResults = [.success(status())]
        model.unseal()
        await settle(model)
        #expect(model.notice.contains("Target binding mismatch"))

        services.storedShare = try record(target)
        services.statusResults = [.success(status())]
        model.refresh()
        await settle(model)
        services.statusResults = [.success(status()), .success(status(sealed: true, progress: 1))]
        model.unseal()
        await settle(model)
        #expect(model.notice.contains("still sealed. Progress: 1/3"))
        #expect(services.submittedRecords.count == 1)

        services.statusResults = [.success(status())]
        model.refresh()
        await settle(model)
        services.statusResults = [.success(status()), .success(status(sealed: false))]
        model.unseal()
        await settle(model)
        #expect(model.notice.contains("now reports unsealed"))

        services.statusResults = [.success(status())]
        model.refresh()
        await settle(model)
        services.statusResults = [
            .success(status()),
            .success(status(type: "transit", threshold: 0, shares: 0, recoverySeal: true))
        ]
        model.unseal()
        await settle(model)
        #expect(model.notice.contains("Unexpected seal configuration"))
        #expect(model.notice.contains("final outcome is unknown"))

        services.statusResults = [.success(status())]
        model.refresh()
        await settle(model)
        services.submitError = AppFailure("submit failed")
        services.statusResults = [.success(status())]
        model.unseal()
        await settle(model)
        #expect(model.notice.contains("submit failed"))
        services.submitError = StubError.failure
        services.statusResults = [.success(status())]
        model.unseal()
        await settle(model)
        #expect(model.notice.contains("Request failed"))
        services.submitError = nil

        services.statusResults = [.success(status())]
        model.refresh()
        await settle(model)
        services.submitError = CancellationError()
        services.statusResults = [.success(status())]
        model.unseal()
        await settle(model)
        #expect(model.notice.contains("Operation cancelled"))
    }

    @Test
    func busyGuardAndPrivacyCancellationAreCovered() async throws {
        let services = StubServices()
        services.loadedProfile = try profile()
        services.suspendStatus = true
        let model = AppModel(services: services)
        model.refresh()
        #expect(model.busy)
        model.refresh()
        #expect(services.statusCalls <= 1)
        model.cancelForPrivacy()
        await settle(model)
        #expect(!model.busy)
        #expect(model.status == nil)
        #expect(services.cancelCalls >= 1)

        model.cancelForPrivacy()
        #expect(model.status == nil)
    }
}
