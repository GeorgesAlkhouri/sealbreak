import ComposableArchitecture
import Foundation
import Testing
@testable import SealbreakCore

private actor ClientSpy {
    var loadedProfile: ServerProfile?
    var loadError: AppFailure?
    var saveProfileError: AppFailure?
    var deleteProfileError: AppFailure?
    var statusQueue: [Result<SealStatus, AppFailure>] = []
    var readRecord: ShareRecord?
    var readError: AppFailure?
    var insertError: AppFailure?
    var replaceError: AppFailure?
    var deleteShareError: AppFailure?
    var submitError: AppFailure?
    var waitError: AppFailure?

    var savedProfiles: [ServerProfile] = []
    var insertedRecords: [ShareRecord] = []
    var replacedRecords: [ShareRecord] = []
    var submittedRecords: [ShareRecord] = []
    var statusCalls = 0
    var deleteProfileCalls = 0
    var deleteShareCalls = 0
    var cancelCalls = 0

    func loadProfile() throws -> ServerProfile? {
        if let loadError { throw loadError }
        return loadedProfile
    }

    func saveProfile(_ profile: ServerProfile) throws {
        if let saveProfileError { throw saveProfileError }
        savedProfiles.append(profile)
        loadedProfile = profile
    }

    func deleteProfile() throws {
        deleteProfileCalls += 1
        if let deleteProfileError { throw deleteProfileError }
        loadedProfile = nil
    }

    func status() throws -> SealStatus {
        statusCalls += 1
        guard !statusQueue.isEmpty else { throw AppFailure("No status result configured.") }
        return try statusQueue.removeFirst().get()
    }

    func readShare() throws -> ShareRecord {
        if let readError { throw readError }
        guard let readRecord else { throw AppFailure("No protected share configured.") }
        return readRecord
    }

    func insert(_ record: ShareRecord) throws {
        if let insertError { throw insertError }
        insertedRecords.append(record)
        readRecord = record
    }

    func replace(_ record: ShareRecord) throws {
        if let replaceError { throw replaceError }
        replacedRecords.append(record)
        readRecord = record
    }

    func deleteShare() throws {
        deleteShareCalls += 1
        if let deleteShareError { throw deleteShareError }
        readRecord = nil
    }

    func submit(_ record: ShareRecord) throws {
        submittedRecords.append(record)
        if let submitError { throw submitError }
    }

    func waitForForeground() throws {
        if let waitError { throw waitError }
    }

    func cancel() {
        cancelCalls += 1
    }
}

private func client(_ spy: ClientSpy) -> SealbreakClient {
    SealbreakClient(
        loadProfile: { try await spy.loadProfile() },
        saveProfile: { try await spy.saveProfile($0) },
        deleteProfile: { try await spy.deleteProfile() },
        status: { _ in try await spy.status() },
        submit: { try await spy.submit($0) },
        readShare: { _ in try await spy.readShare() },
        insertShare: { record, _ in try await spy.insert(record) },
        replaceShare: { _, replacement, _ in try await spy.replace(replacement) },
        deleteShare: { _ in try await spy.deleteShare() },
        requireForeground: {},
        waitForForeground: { try await spy.waitForForeground() },
        cancelSensitiveOperation: { await spy.cancel() }
    )
}

@MainActor
struct FeatureTests {
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

    private func homeStore(
        profile: ServerProfile,
        status: SealStatus? = nil,
        spy: ClientSpy
    ) -> TestStore<HomeFeature.State, HomeFeature.Action> {
        let store = TestStore(initialState: HomeFeature.State(profile: profile, status: status)) {
            HomeFeature()
        } withDependencies: {
            $0.sealbreakClient = client(spy)
        }
        store.exhaustivity = .off(showSkippedAssertions: false)
        return store
    }

    @Test
    func appLoadsProfileIntoHomeAndRefreshes() async throws {
        let target = try profile()
        let checked = status(progress: 1)
        let spy = ClientSpy()
        await spy.setLoadedProfile(target)
        await spy.setStatusQueue([.success(checked)])

        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.sealbreakClient = client(spy)
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.task).finish()
        await store.skipReceivedActions()

        #expect(store.state.setup == nil)
        #expect(store.state.home?.profile == target)
        #expect(store.state.home?.status == checked)
        #expect(store.state.home?.notice == "Status checked. Nothing is sent automatically.")
    }

    @Test
    func appLoadFailureEntersSetup() async {
        let spy = ClientSpy()
        await spy.setLoadError(AppFailure("broken"))
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.sealbreakClient = client(spy)
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.task).finish()
        await store.skipReceivedActions()

        #expect(store.state.home == nil)
        #expect(store.state.setup?.notice.contains("could not be read") == true)
    }

    @Test
    func refreshUpdatesStatusAndUnsupportedNotice() async throws {
        let target = try profile()
        let spy = ClientSpy()
        await spy.setStatusQueue([
            .success(status()),
            .success(status(type: "transit", threshold: 0, shares: 0, recoverySeal: true))
        ])
        let store = homeStore(profile: target, spy: spy)

        await store.send(.refreshRequested).finish()
        await store.skipReceivedActions()
        #expect(store.state.status?.sealed == true)
        #expect(store.state.canUnseal)

        await store.send(.refreshTapped).finish()
        await store.skipReceivedActions()
        #expect(store.state.status?.type == "transit")
        #expect(!store.state.canUnseal)
        #expect(store.state.notice.contains("Only initialized Shamir seals"))
    }

    @Test
    func refreshSurfacesFailure() async throws {
        let target = try profile()
        let spy = ClientSpy()
        await spy.setStatusQueue([.failure(AppFailure("status failed"))])
        let store = homeStore(profile: target, spy: spy)

        await store.send(.refreshTapped).finish()
        await store.skipReceivedActions()

        #expect(store.state.status == nil)
        #expect(store.state.notice == "status failed")
        #expect(store.state.operation == nil)
    }

    @Test
    func unsealVerifiedSuccessSubmitsExactlyOneBoundShare() async throws {
        let target = try profile()
        let before = status()
        let after = status(sealed: false)
        let spy = ClientSpy()
        await spy.setReadRecord(try record(target))
        await spy.setStatusQueue([.success(before), .success(after)])
        let store = homeStore(profile: target, status: before, spy: spy)

        await store.send(.unsealTapped)
        #expect(store.state.confirmation == .unseal)
        await store.send(.confirmUnsealTapped).finish()
        await store.skipReceivedActions()

        #expect(store.state.status == after)
        #expect(store.state.operation == nil)
        #expect(store.state.notice.contains("now reports unsealed"))
        let submittedCount = await spy.submittedCount
        #expect(submittedCount == 1)
    }

    @Test
    func unsealTargetMismatchNeverSubmits() async throws {
        let target = try profile()
        let spy = ClientSpy()
        await spy.setReadRecord(try record(profile("Other")))
        await spy.setStatusQueue([.success(status())])
        let store = homeStore(profile: target, status: status(), spy: spy)

        await store.send(.unsealTapped)
        await store.send(.confirmUnsealTapped).finish()
        await store.skipReceivedActions()

        #expect(store.state.notice.contains("Target binding mismatch"))
        let submittedCount = await spy.submittedCount
        #expect(submittedCount == 0)
    }

    @Test
    func unsealSubmissionFailureMarksOutcomeUnknown() async throws {
        let target = try profile()
        let spy = ClientSpy()
        await spy.setReadRecord(try record(target))
        await spy.setStatusQueue([.success(status())])
        await spy.setSubmitError(AppFailure("submit failed"))
        let store = homeStore(profile: target, status: status(), spy: spy)

        await store.send(.unsealTapped)
        await store.send(.confirmUnsealTapped).finish()
        await store.skipReceivedActions()

        #expect(store.state.status == nil)
        #expect(store.state.notice.contains("submit failed"))
        #expect(store.state.notice.contains("final outcome is unknown"))
    }

    @Test
    func unsealAlreadyUnsealedDoesNotReadOrSubmit() async throws {
        let target = try profile()
        let spy = ClientSpy()
        await spy.setStatusQueue([.success(status(sealed: false))])
        let store = homeStore(profile: target, status: status(), spy: spy)

        await store.send(.unsealTapped)
        await store.send(.confirmUnsealTapped).finish()
        await store.skipReceivedActions()

        #expect(store.state.status?.sealed == false)
        #expect(store.state.notice == "Already unsealed. No share was read or sent.")
        let submittedCount = await spy.submittedCount
        #expect(submittedCount == 0)
    }

    @Test
    func setupImportRequiresRecoveryAndDelegatesProfile() async throws {
        let target = try profile()
        let spy = ClientSpy()
        let store = TestStore(initialState: SetupFeature.State()) {
            SetupFeature()
        } withDependencies: {
            $0.sealbreakClient = client(spy)
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(
            .saveTapped(name: target.name, address: target.origin, share: share, recoveryConfirmed: false)
        )
        #expect(store.state.notice.contains("Confirm an independent recovery copy"))
        let insertedCountBefore = await spy.insertedCount
        #expect(insertedCountBefore == 0)

        await store.send(
            .saveTapped(name: target.name, address: target.origin, share: share, recoveryConfirmed: true)
        ).finish()
        let savedNotice = "Share saved with device-bound biometric protection. Check status to begin."
        await store.receive(.importResponse(.success(.init(profile: target, notice: savedNotice))))
        await store.receive(.delegate(.profileReady(target, notice: savedNotice)))

        #expect(store.state.operation == nil)
        #expect(store.state.notice.contains("Share saved"))
        let insertedCount = await spy.insertedCount
        #expect(insertedCount == 1)
        let savedProfilesCount = await spy.savedProfilesCount
        #expect(savedProfilesCount == 1)
    }

    @Test
    func setupImportPreservesShareWhenDisplayProfileSaveFails() async throws {
        let target = try profile()
        let spy = ClientSpy()
        await spy.setSaveProfileError(AppFailure("save failed"))
        let store = TestStore(initialState: SetupFeature.State()) {
            SetupFeature()
        } withDependencies: {
            $0.sealbreakClient = client(spy)
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(
            .saveTapped(name: target.name, address: target.origin, share: share, recoveryConfirmed: true)
        ).finish()
        let fallbackNotice =
            "Protected share exists, but display metadata could not be saved. Use Restore profile from Keychain on the next launch."
        await store.receive(.importResponse(.success(.init(profile: target, notice: fallbackNotice))))
        await store.receive(.delegate(.profileReady(target, notice: fallbackNotice)))

        let insertedCount = await spy.insertedCount
        #expect(insertedCount == 1)
        #expect(store.state.notice.contains("display metadata could not be saved"))
    }

    @Test
    func restoreProfileAndRemoveLocalDataCoverPersistenceFailures() async throws {
        let target = try profile()
        let spy = ClientSpy()
        await spy.setReadRecord(try record(target))
        let store = TestStore(initialState: SetupFeature.State()) {
            SetupFeature()
        } withDependencies: {
            $0.sealbreakClient = client(spy)
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.restoreProfileTapped).finish()
        let restoredNotice = "Protected target restored. No share was transmitted or exported."
        await store.receive(.restoreResponse(.success(.init(profile: target, notice: restoredNotice))))
        await store.receive(.delegate(.profileReady(target, notice: restoredNotice)))
        #expect(store.state.notice.contains("Protected target restored"))

        await spy.setDeleteProfileError(AppFailure("delete display failed"))
        await store.send(.removeLocalDataTapped)
        #expect(store.state.confirmDelete)
        await store.send(.confirmRemoveLocalDataTapped).finish()
        await store.skipReceivedActions()
        #expect(store.state.notice.contains("display file could not be removed"))
        let deleteShareCalls = await spy.deleteShareCalls
        #expect(deleteShareCalls == 1)
    }

    @Test
    func replaceSharePreservesTargetBindingInDependency() async throws {
        let target = try profile()
        let spy = ClientSpy()
        let store = TestStore(initialState: ReplaceShareFeature.State(profile: target)) {
            ReplaceShareFeature()
        } withDependencies: {
            $0.sealbreakClient = client(spy)
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.saveTapped(share: share, recoveryConfirmed: false))
        #expect(store.state.notice.contains("Confirm recovery"))

        await store.send(.saveTapped(share: share, recoveryConfirmed: true)).finish()
        let replacedNotice =
            "Local share replaced. This does not rotate OpenBao keys; server-side rekeying is a separate operation."
        await store.receive(.saveResponse(.success(replacedNotice)))
        await store.receive(.delegate(.saved(notice: replacedNotice)))
        let replacedCount = await spy.replacedCount
        #expect(replacedCount == 1)
        #expect(store.state.notice.contains("Local share replaced"))
    }

    @Test
    func privacyInterruptClearsSensitiveHomeStateAndCancelsDependency() async throws {
        let target = try profile()
        let spy = ClientSpy()
        var initial = HomeFeature.State(profile: target, status: status())
        initial.confirmation = .unseal
        initial.replaceShare = ReplaceShareFeature.State(profile: target)
        initial.serverDetails = ServerDetailsFeature.State(
            profile: target,
            status: status(),
            isBusy: false,
            activity: "",
            notice: ""
        )
        let store = TestStore(initialState: initial) {
            HomeFeature()
        } withDependencies: {
            $0.sealbreakClient = client(spy)
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.privacyInterrupted).finish()

        #expect(store.state.status == nil)
        #expect(store.state.confirmation == nil)
        #expect(store.state.replaceShare == nil)
        #expect(store.state.serverDetails == nil)
        let cancelCalls = await spy.cancelCalls
        #expect(cancelCalls == 1)
    }

    @Test
    func privacyFeatureEmitsOnlySecurityRelevantTransitions() async {
        let store = TestStore(initialState: PrivacyFeature.State()) {
            PrivacyFeature()
        }

        await store.send(.phaseChanged(.active)) {
            $0.phase = .active
        }
        await store.receive(.delegate(.becameActive))
        await store.send(.phaseChanged(.inactive)) {
            $0.phase = .inactive
        }
        await store.send(.phaseChanged(.background)) {
            $0.phase = .background
        }
        await store.receive(.delegate(.interrupted))
        await store.send(.captureChanged(true)) {
            $0.isCaptured = true
        }
        await store.receive(.delegate(.interrupted))
    }
}

private extension ClientSpy {
    func setLoadedProfile(_ value: ServerProfile?) { loadedProfile = value }
    func setLoadError(_ value: AppFailure?) { loadError = value }
    func setSaveProfileError(_ value: AppFailure?) { saveProfileError = value }
    func setDeleteProfileError(_ value: AppFailure?) { deleteProfileError = value }
    func setStatusQueue(_ value: [Result<SealStatus, AppFailure>]) { statusQueue = value }
    func setReadRecord(_ value: ShareRecord?) { readRecord = value }
    func setSubmitError(_ value: AppFailure?) { submitError = value }

    var submittedCount: Int { submittedRecords.count }
    var insertedCount: Int { insertedRecords.count }
    var replacedCount: Int { replacedRecords.count }
    var savedProfilesCount: Int { savedProfiles.count }
}
