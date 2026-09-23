import ComposableArchitecture
import Foundation
import Testing
@testable import SealbreakCore

private actor ClientSpy {
    var storedProfiles: [StoredProfile] = []
    var loadError: AppFailure?
    var protectOutcome: LocalPersistenceOutcome?
    var protectError: AppFailure?
    var removeOutcome: LocalPersistenceOutcome?
    var removeError: AppFailure?
    var insertProfileError: AppFailure?
    var deleteProfileError: AppFailure?
    var resetLocalDataError: AppFailure?
    var detectedProduct: ServerProduct = .generic
    var detectionError: AppFailure?
    var configuredDNSSECStatus: DNSSECStatus = .insecure
    var statusQueue: [Result<SealStatus, AppFailure>] = []
    var readRecord: ShareRecord?
    var readError: AppFailure?
    var insertError: AppFailure?
    var replaceError: AppFailure?
    var deleteShareError: AppFailure?
    var submitError: AppFailure?
    var waitError: AppFailure?
    var waitCancellation = false

    var savedProfiles: [ServerProfile] = []
    var insertedRecords: [ShareRecord] = []
    var replacedRecords: [ShareRecord] = []
    var submittedRecords: [ShareRecord] = []
    var statusCalls = 0
    var detectProductCalls = 0
    var dnssecCalls = 0
    var removeLocalProfileCalls = 0
    var resetLocalDataCalls = 0
    var cancelCalls = 0

    func loadProfiles() throws -> [StoredProfile] {
        if let loadError { throw loadError }
        return storedProfiles
    }

    func loadLocalSetupState() throws -> LocalSetupState {
        try resolveLocalSetupState(
            profiles: loadProfiles()
        )
    }

    func protectNewProfile(
        _ profile: ServerProfile,
        record: ShareRecord
    ) throws -> LocalPersistenceOutcome {
        if waitCancellation {
            throw CancellationError()
        }
        if let waitError {
            throw waitError
        }
        if let protectError {
            throw protectError
        }
        if let protectOutcome {
            return protectOutcome
        }

        let profiles = try loadProfiles()
        guard profiles.isEmpty else {
            return .recoveryRequired(
                "Local profile data already exists. Reset local Sealbreak data before continuing."
            )
        }

        if insertProfileError != nil {
            return .recoveryRequired(
                "Local setup did not finish safely. Reset local Sealbreak data before continuing."
            )
        }

        savedProfiles.append(profile)
        storedProfiles = [
            StoredProfile(
                profile: profile,
                state: .creating
            )
        ]

        if insertError != nil {
            return .recoveryRequired(
                "Local setup did not finish safely. Reset local Sealbreak data before continuing."
            )
        }

        insertedRecords.append(record)
        readRecord = record
        storedProfiles[0].state = .ready
        return .completed
    }

    func resetLocalData() throws {
        resetLocalDataCalls += 1
        if let resetLocalDataError { throw resetLocalDataError }
        storedProfiles = []
        readRecord = nil
    }

    func detectProduct() throws -> ServerProduct {
        detectProductCalls += 1
        if let detectionError { throw detectionError }
        return detectedProduct
    }

    func dnssecStatus() -> DNSSECStatus {
        dnssecCalls += 1
        return configuredDNSSECStatus
    }

    func status() throws -> SealStatus {
        statusCalls += 1
        guard !statusQueue.isEmpty else { throw AppFailure("No status result configured.") }
        return try statusQueue.removeFirst().get()
    }

    func readShare(_ profileID: UUID) throws -> ShareRecord {
        if let readError { throw readError }
        guard let readRecord else { throw AppFailure("No protected share configured.") }
        guard readRecord.profileID == profileID else {
            throw AppFailure("Protected share belongs to a different profile.")
        }
        return readRecord
    }

    func replace(_ record: ShareRecord) throws {
        if let replaceError { throw replaceError }
        replacedRecords.append(record)
        readRecord = record
    }

    func removeLocalProfile(_ profileID: UUID) throws -> LocalPersistenceOutcome {
        removeLocalProfileCalls += 1
        if waitCancellation {
            throw CancellationError()
        }
        if let waitError {
            throw waitError
        }
        if let removeError {
            throw removeError
        }
        if let removeOutcome {
            return removeOutcome
        }

        guard storedProfiles.count == 1,
              storedProfiles[0].profile.id == profileID,
              storedProfiles[0].state == .ready else {
            return .recoveryRequired(
                "Local removal could not be completed safely. Reset local Sealbreak data before continuing."
            )
        }

        storedProfiles[0].state = .removing

        if deleteShareError != nil {
            return .recoveryRequired(
                "Local removal could not be completed safely. Reset local Sealbreak data before continuing."
            )
        }
        if readRecord?.profileID == profileID {
            readRecord = nil
        }

        if deleteProfileError != nil {
            return .recoveryRequired(
                "Local removal could not be completed safely. Reset local Sealbreak data before continuing."
            )
        }

        storedProfiles.removeAll { $0.profile.id == profileID }
        return .completed
    }

    func submit(_ record: ShareRecord) throws {
        submittedRecords.append(record)
        if let submitError { throw submitError }
    }

    func waitForForeground() throws {
        if waitCancellation { throw CancellationError() }
        if let waitError { throw waitError }
    }

    func cancel() {
        cancelCalls += 1
    }
}

private func client(_ spy: ClientSpy) -> SealbreakClient {
    SealbreakClient(
        loadLocalSetupState: { try await spy.loadLocalSetupState() },
        protectNewProfile: { profile, record, _ in
            try await spy.protectNewProfile(profile, record: record)
        },
        resetLocalData: { try await spy.resetLocalData() },
        detectProduct: { _ in try await spy.detectProduct() },
        dnssecStatus: { _ in await spy.dnssecStatus() },
        status: { _ in try await spy.status() },
        submit: { try await spy.submit($0) },
        readShare: { profileID, _ in try await spy.readShare(profileID) },
        replaceShare: { _, replacement, _ in try await spy.replace(replacement) },
        removeLocalProfile: { profileID, _ in
            try await spy.removeLocalProfile(profileID)
        },
        requireForeground: {},
        waitForForeground: { try await spy.waitForForeground() },
        cancelSensitiveOperation: { await spy.cancel() }
    )
}

@MainActor
struct FeatureTests {
    private let origin = "https://bao.example.com"
    private let share = String(repeating: "a", count: 64)

    private func profile(
        _ name: String = "Server",
        product: ServerProduct = .generic
    ) throws -> ServerProfile {
        try ServerProfile(id: UUID(), name: name, address: origin, product: product)
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
            $0.uuid = .incrementing
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
            $0.uuid = .incrementing
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.task).finish()
        await store.skipReceivedActions()

        #expect(store.state.welcome == nil)
        #expect(store.state.setup == nil)
        #expect(store.state.home?.profile == target)
        #expect(store.state.home?.status == checked)
        #expect(store.state.home?.notice == "Status checked. Nothing is sent automatically.")
    }

    @Test
    func appRejectsMultiplePersistedProfilesUntilMultiServerUIExists() async throws {
        let first = try profile("First")
        let second = try ServerProfile(
            id: UUID(),
            name: "Second",
            address: "https://second.example.com"
        )
        let spy = ClientSpy()
        await spy.setLoadedProfiles([first, second])

        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.sealbreakClient = client(spy)
            $0.uuid = .incrementing
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.task).finish()
        await store.skipReceivedActions()

        #expect(store.state.home == nil)
        #expect(store.state.setup == nil)
        #expect(store.state.welcome?.requiresLocalReset == true)
        #expect(store.state.welcome?.notice?.contains("multiple server profiles") == true)
    }

    @Test
    func appLoadFailureEntersWelcome() async {
        let spy = ClientSpy()
        await spy.setLoadError(AppFailure("broken"))
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.sealbreakClient = client(spy)
            $0.uuid = .incrementing
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.task).finish()
        await store.skipReceivedActions()

        #expect(store.state.home == nil)
        #expect(store.state.setup == nil)
        #expect(store.state.welcome?.requiresLocalReset == true)
        #expect(store.state.welcome?.notice?.contains("Reset local data") == true)
    }

    @Test
    func appLoadFailureRequiresConfirmedLocalResetBeforeSetup() async {
        let spy = ClientSpy()
        await spy.setLoadError(AppFailure("broken"))
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.sealbreakClient = client(spy)
            $0.uuid = .incrementing
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.task).finish()
        await store.skipReceivedActions()
        #expect(store.state.welcome?.requiresLocalReset == true)

        await store.send(.welcome(.setUpTapped))
        #expect(store.state.setup == nil)

        await store.send(.welcome(.resetLocalDataTapped))
        #expect(store.state.welcome?.confirmReset == true)

        await store.send(.welcome(.resetConfirmationDismissed))
        #expect(store.state.welcome?.confirmReset == false)
        #expect(await spy.resetLocalDataCalls == 0)

        await store.send(.welcome(.resetLocalDataTapped))
        await store.send(.welcome(.confirmResetLocalDataTapped)).finish()
        await store.skipReceivedActions()

        #expect(await spy.resetLocalDataCalls == 1)
        #expect(store.state.welcome?.requiresLocalReset == false)
        #expect(store.state.welcome?.isResetting == false)
        #expect(store.state.welcome?.notice?.contains("was reset") == true)
    }

    @Test
    func welcomeResetFailureKeepsRecoveryRequired() async {
        let spy = ClientSpy()
        await spy.setResetLocalDataError(AppFailure("reset failed"))
        let store = TestStore(
            initialState: WelcomeFeature.State(
                notice: "damaged",
                requiresLocalReset: true
            )
        ) {
            WelcomeFeature()
        } withDependencies: {
            $0.sealbreakClient = client(spy)
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.resetLocalDataTapped)
        await store.send(.confirmResetLocalDataTapped).finish()
        await store.skipReceivedActions()

        #expect(store.state.requiresLocalReset)
        #expect(!store.state.isResetting)
        #expect(store.state.notice == "reset failed")
    }

    @Test
    func welcomeRoutesPrimaryIntent() async {
        let store = TestStore(initialState: WelcomeFeature.State()) {
            WelcomeFeature()
        }

        await store.send(.setUpTapped)
        await store.receive(.delegate(.setUp))
    }

    @Test
    func welcomeIgnoresResetActionsWhenResetIsNotRequired() async {
        let store = TestStore(initialState: WelcomeFeature.State()) {
            WelcomeFeature()
        }

        await store.send(.resetLocalDataTapped)
        #expect(!store.state.confirmReset)
        #expect(!store.state.isResetting)

        await store.send(.confirmResetLocalDataTapped)
        #expect(!store.state.confirmReset)
        #expect(!store.state.isResetting)
    }

    @Test
    func appWelcomeSetUpOpensSetup() async {
        var initialState = AppFeature.State()
        initialState.isLoading = false
        initialState.welcome = WelcomeFeature.State()

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.welcome(.delegate(.setUp)))

        #expect(store.state.welcome == nil)
        #expect(store.state.setup != nil)
        #expect(store.state.home == nil)
    }

    @Test
    func appSetupCancellationReturnsToWelcome() async {
        var initialState = AppFeature.State()
        initialState.isLoading = false
        initialState.didLoad = true
        initialState.setup = SetupFeature.State()

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.setup(.delegate(.cancelled)))

        #expect(store.state.setup == nil)
        #expect(store.state.home == nil)
        #expect(store.state.welcome != nil)
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
        let mismatchedRecordJSON = """
        {"version":1,"profileID":"\(target.id.uuidString)","boundOrigin":"https://other.example.com","share":"\(share)"}
        """
        let mismatchedRecord = try JSONDecoder().decode(
            ShareRecord.self,
            from: Data(mismatchedRecordJSON.utf8)
        ).validated()

        let spy = ClientSpy()
        await spy.setReadRecord(mismatchedRecord)
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
    func setupImportProtectsShareAndDelegatesProfile() async throws {
        let target = try profile(product: .vault)
        let spy = ClientSpy()
        let store = TestStore(
            initialState: ShareSetupFeature.State(profile: target)
        ) {
            ShareSetupFeature()
        } withDependencies: {
            $0.sealbreakClient = client(spy)
            $0.uuid = .incrementing
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.saveTapped(share: share)).finish()
        let savedNotice = "Share protected on this iPhone. Check status to begin."
        await store.receive(.importResponse(.success(.init(profile: target, notice: savedNotice))))
        await store.receive(.delegate(.profileReady(target, notice: savedNotice)))

        #expect(store.state.operation == nil)
        #expect(store.state.notice.contains("Share protected"))
        #expect(await spy.insertedCount == 1)
        #expect(await spy.insertedBoundOrigins == [target.origin])
        #expect(await spy.savedProfilesCount == 1)
    }

    @Test
    func setupRetryDoesNotDeleteExistingProfileOrShare() async throws {
        let target = try profile()
        let originalRecord = try record(target)
        let spy = ClientSpy()
        await spy.setLoadedProfile(target)
        await spy.setReadRecord(originalRecord)

        let store = TestStore(
            initialState: ShareSetupFeature.State(profile: target)
        ) {
            ShareSetupFeature()
        } withDependencies: {
            $0.sealbreakClient = client(spy)
            $0.uuid = .incrementing
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.saveTapped(share: share)).finish()
        await store.skipReceivedActions()

        #expect(store.state.operation == nil)
        #expect(store.state.notice.contains("already exists"))
        #expect(await spy.removeLocalProfileCalls == 0)
        #expect(await spy.insertedCount == 0)
        #expect(await spy.currentProfiles == [target])
        #expect(await spy.currentReadRecord == originalRecord)
    }

    @Test
    func instanceSetupFallsBackToGenericWhenProductDetectionFails() async throws {
        let spy = ClientSpy()
        await spy.setDNSSECStatus(.secure)
        await spy.setDetectionError(AppFailure("detection failed"))
        await spy.setStatusQueue([.success(status())])

        let store = TestStore(initialState: InstanceSetupFeature.State()) {
            InstanceSetupFeature()
        } withDependencies: {
            $0.sealbreakClient = client(spy)
            $0.uuid = .incrementing
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.addressChanged(origin))
        await store.send(.checkConnectionTapped).finish()
        await store.skipReceivedActions()

        #expect(store.state.checkedProfile?.product == .generic)
        #expect(store.state.checkedProfile?.id.uuidString == "00000000-0000-0000-0000-000000000000")
        #expect(store.state.canContinue)
        #expect(await spy.detectProductCalls == 1)
    }

    @Test
    func setupImportDoesNotProtectShareWhenProfileInsertFails() async throws {
        let target = try profile()
        let spy = ClientSpy()
        await spy.setInsertProfileError(AppFailure("insert failed"))
        let store = TestStore(
            initialState: ShareSetupFeature.State(profile: target)
        ) {
            ShareSetupFeature()
        } withDependencies: {
            $0.sealbreakClient = client(spy)
            $0.uuid = .incrementing
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(
            .saveTapped(share: share)
        ).finish()
        await store.skipReceivedActions()

        #expect(await spy.insertedCount == 0)
        #expect(store.state.notice.contains("Reset local Sealbreak data"))
    }
    @Test
    func replaceSharePreservesTargetBindingInDependency() async throws {
        let target = try profile()
        let spy = ClientSpy()
        let store = TestStore(initialState: ReplaceShareFeature.State(profile: target)) {
            ReplaceShareFeature()
        } withDependencies: {
            $0.sealbreakClient = client(spy)
            $0.uuid = .incrementing
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.saveTapped(share: share, recoveryConfirmed: false))
        #expect(store.state.notice.contains("Confirm recovery"))

        await store.send(.saveTapped(share: share, recoveryConfirmed: true)).finish()
        await store.receive(.saveSucceeded)
        await store.receive(.delegate(.saved))
        let replacedCount = await spy.replacedCount
        #expect(replacedCount == 1)
        #expect(store.state.notice.isEmpty)
    }

    @Test
    func privacyInterruptClearsSensitiveHomeStateAndCancelsDependency() async throws {
        let target = try profile()
        let spy = ClientSpy()
        var initial = HomeFeature.State(profile: target, status: status())
        initial.operation = .submittingShare
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
            $0.uuid = .incrementing
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.privacyInterrupted).finish()

        #expect(store.state.status == nil)
        #expect(store.state.confirmation == nil)
        #expect(store.state.replaceShare == nil)
        #expect(store.state.serverDetails == nil)
        #expect(store.state.notice.contains("Operation interrupted"))
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

    @Test
    func appLoadWithoutProfileEntersWelcome() async {
        let spy = ClientSpy()
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.sealbreakClient = client(spy)
            $0.uuid = .incrementing
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.task).finish()
        await store.skipReceivedActions()

        #expect(store.state.home == nil)
        #expect(store.state.setup == nil)
        #expect(store.state.welcome != nil)
        #expect(!store.state.isLoading)
    }

    @Test
    func appRoutesChildDelegatesBetweenSetupAndHome() async throws {
        let target = try profile()
        let checked = status(progress: 1)
        let spy = ClientSpy()
        await spy.setStatusQueue([.success(checked)])
        var initial = AppFeature.State()
        initial.isLoading = false
        initial.didLoad = true
        initial.setup = SetupFeature.State()
        let store = TestStore(initialState: initial) {
            AppFeature()
        } withDependencies: {
            $0.sealbreakClient = client(spy)
            $0.uuid = .incrementing
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(
            .setup(.delegate(.profileReady(target, notice: "Profile restored")))
        ).finish()
        await store.skipReceivedActions()
        #expect(store.state.setup == nil)
        #expect(store.state.home?.profile == target)
        #expect(store.state.home?.status == checked)

        await store.send(
            .home(
                .delegate(
                    .localDataRemoved(
                        notice: "Local data removed",
                        requiresLocalReset: false
                    )
                )
            )
        )
        #expect(store.state.home == nil)
        #expect(store.state.setup == nil)
        #expect(store.state.welcome?.notice == "Local data removed")
    }

    @Test
    func appRoutesPrivacyEventsToVisibleFeatures() async throws {
        let target = try profile()
        let refreshed = status(progress: 2)
        let homeSpy = ClientSpy()
        await homeSpy.setStatusQueue([.success(refreshed)])
        var homeInitial = AppFeature.State()
        homeInitial.isLoading = false
        homeInitial.didLoad = true
        homeInitial.home = HomeFeature.State(profile: target, status: status())
        let homeStore = TestStore(initialState: homeInitial) {
            AppFeature()
        } withDependencies: {
            $0.sealbreakClient = client(homeSpy)
            $0.uuid = .incrementing
        }
        homeStore.exhaustivity = .off(showSkippedAssertions: false)

        await homeStore.send(.privacy(.delegate(.interrupted))).finish()
        await homeStore.skipReceivedActions()
        #expect(homeStore.state.home?.status == nil)
        #expect(await homeSpy.cancelCalls == 1)

        await homeStore.send(.privacy(.delegate(.becameActive))).finish()
        await homeStore.skipReceivedActions()
        #expect(homeStore.state.home?.status == refreshed)

        let setupSpy = ClientSpy()
        var setupInitial = AppFeature.State()
        setupInitial.isLoading = false
        setupInitial.didLoad = true
        setupInitial.setup = SetupFeature.State()
        let setupStore = TestStore(initialState: setupInitial) {
            AppFeature()
        } withDependencies: {
            $0.sealbreakClient = client(setupSpy)
            $0.uuid = .incrementing
        }
        setupStore.exhaustivity = .off(showSkippedAssertions: false)

        await setupStore.send(.privacy(.delegate(.interrupted))).finish()
        await setupStore.skipReceivedActions()
        #expect(await setupSpy.cancelCalls == 0)
    }

    @Test
    func homeCancellationClearsStaleStatusAndExplainsUncertainOutcome() async throws {
        let target = try profile()
        let spy = ClientSpy()
        await spy.setWaitCancellation(true)
        let store = homeStore(profile: target, status: status(), spy: spy)

        await store.send(.refreshRequested).finish()
        await store.skipReceivedActions()

        #expect(store.state.operation == nil)
        #expect(store.state.status == nil)
        #expect(store.state.notice.contains("Operation cancelled"))
        #expect(store.state.notice.contains("may already have been processed"))
    }

    @Test
    func homeSynchronizesNavigationAndChildDelegates() async throws {
        let target = try profile()
        let refreshed = status(progress: 2)
        let spy = ClientSpy()
        await spy.setStatusQueue([.success(refreshed)])
        let store = homeStore(profile: target, status: status(), spy: spy)

        await store.send(.serverDetailsTapped)
        #expect(store.state.serverDetails?.status == status())

        await store.send(.serverDetails(.presented(.delegate(.refreshRequested)))).finish()
        await store.skipReceivedActions()
        #expect(store.state.status == refreshed)
        #expect(store.state.serverDetails?.status == refreshed)

        await store.send(.serverDetails(.presented(.delegate(.dismissRequested))))
        #expect(store.state.serverDetails == nil)

        await store.send(.replaceShareTapped)
        #expect(store.state.replaceShare?.profile == target)
        await store.send(.replaceShare(.presented(.delegate(.saved))))
        #expect(store.state.replaceShare == nil)
        #expect(store.state.status == refreshed)
        #expect(store.state.notice == "Status checked. Nothing is sent automatically.")

        await store.send(.replaceShareTapped)
        await store.send(.replaceShare(.presented(.delegate(.dismissRequested))))
        #expect(store.state.replaceShare == nil)
    }

    @Test
    func homeRemovesLocalDataAndClearsPresentedState() async throws {
        let target = try profile()
        let spy = ClientSpy()
        await spy.setLoadedProfile(target)
        await spy.setReadRecord(try record(target))
        let store = TestStore(initialState: HomeFeature.State(profile: target, status: status())) {
            HomeFeature()
        } withDependencies: {
            $0.sealbreakClient = client(spy)
            $0.uuid = .incrementing
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.serverDetailsTapped)
        await store.send(.replaceShareTapped)
        #expect(store.state.serverDetails?.profile == target)
        #expect(store.state.replaceShare?.profile == target)

        await store.send(.removeLocalDataTapped)
        #expect(store.state.confirmation == .removeLocalData)
        await store.send(.confirmRemoveLocalDataTapped).finish()
        await store.skipReceivedActions()

        #expect(store.state.operation == nil)
        #expect(store.state.status == nil)
        #expect(store.state.serverDetails == nil)
        #expect(store.state.replaceShare == nil)
        #expect(store.state.notice.contains("Local share removed"))
        #expect(await spy.removeLocalProfileCalls == 1)
        #expect(await spy.currentProfiles.isEmpty)
        #expect(await spy.currentReadRecord == nil)
    }

    @Test
    func homeSurfacesRemoveFailure() async throws {
        let target = try profile()
        let spy = ClientSpy()
        await spy.setRemoveError(AppFailure("remove failed"))
        let store = homeStore(profile: target, status: status(), spy: spy)

        await store.send(.removeLocalDataTapped)
        await store.send(.confirmRemoveLocalDataTapped).finish()
        await store.skipReceivedActions()
        #expect(store.state.operation == nil)
        #expect(store.state.notice == "remove failed")
    }

    @Test
    func setupChecksInstanceBeforeAdvancingToShare() async throws {
        let spy = ClientSpy()
        await spy.setDetectedProduct(.openBao)
        await spy.setDNSSECStatus(.secure)

        let store = TestStore(initialState: SetupFeature.State()) {
            SetupFeature()
        } withDependencies: {
            $0.sealbreakClient = client(spy)
            $0.uuid = .incrementing
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.instance(.addressChanged(origin)))
        #expect(store.state.instance.checkedProfile == nil)

        await store.send(.instance(.checkConnectionTapped)).finish()
        await store.skipReceivedActions()

        #expect(store.state.instance.dnssecStatus == .secure)
        #expect(store.state.instance.checkedProfile?.origin == origin)
        #expect(store.state.instance.checkedProfile?.product == .openBao)
        #expect(store.state.instance.canContinue)
        #expect(await spy.detectProductCalls == 1)
        #expect(await spy.dnssecCount == 1)

        await store.send(.instance(.continueTapped)).finish()
        await store.skipReceivedActions()

        #expect(store.state.step == .share)
        #expect(store.state.share?.profile.product == .openBao)
    }

    @Test
    func setupBlocksBogusDNSSECBeforeContactingServer() async {
        let spy = ClientSpy()
        await spy.setDNSSECStatus(.bogus)

        let store = TestStore(initialState: InstanceSetupFeature.State()) {
            InstanceSetupFeature()
        } withDependencies: {
            $0.sealbreakClient = client(spy)
            $0.uuid = .incrementing
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.addressChanged(origin))
        await store.send(.checkConnectionTapped).finish()
        await store.skipReceivedActions()

        #expect(!store.state.isCheckingConnection)
        #expect(store.state.dnssecStatus == .bogus)
        #expect(store.state.checkedProfile == nil)
        #expect(store.state.notice?.contains("DNSSEC validation failed") == true)
        #expect(!store.state.canContinue)
        #expect(await spy.detectProductCalls == 0)
    }

    @Test
    func setupEditingInstanceInvalidatesSuccessfulCheck() async {
        let spy = ClientSpy()
        await spy.setDNSSECStatus(.secure)

        let store = TestStore(initialState: InstanceSetupFeature.State()) {
            InstanceSetupFeature()
        } withDependencies: {
            $0.sealbreakClient = client(spy)
            $0.uuid = .incrementing
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.addressChanged(origin))
        await store.send(.checkConnectionTapped).finish()
        await store.skipReceivedActions()
        #expect(store.state.canContinue)

        await store.send(.addressChanged("https://other.example.com"))
        #expect(store.state.checkedProfile == nil)
        #expect(store.state.dnssecStatus == nil)
        #expect(store.state.notice == nil)
        #expect(!store.state.canContinue)
    }

    @Test
    func setupRejectsInvalidImportAndSurfacesDependencyFailure() async throws {
        let target = try profile()
        let spy = ClientSpy()
        let store = TestStore(
            initialState: ShareSetupFeature.State(profile: target)
        ) {
            ShareSetupFeature()
        } withDependencies: {
            $0.sealbreakClient = client(spy)
            $0.uuid = .incrementing
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(
            .saveTapped(share: "short")
        )
        #expect(store.state.operation == nil)
        #expect(store.state.notice.contains("share"))

        await spy.setProtectError(AppFailure("protect failed"))
        await store.send(
            .saveTapped(share: share)
        ).finish()
        await store.skipReceivedActions()
        #expect(store.state.operation == nil)
        #expect(store.state.notice == "protect failed")
    }

    @Test
    func setupPrivacyInterruptionKeepsProtectionStateUntilOutcomeArrives() async throws {
        let spy = ClientSpy()
        let target = try profile()
        var interruptedState = SetupFeature.State()
        interruptedState.step = .share
        interruptedState.share = ShareSetupFeature.State(profile: target)
        interruptedState.share?.operation = .protecting
        let interruptionStore = TestStore(initialState: interruptedState) {
            SetupFeature()
        } withDependencies: {
            $0.sealbreakClient = client(spy)
            $0.uuid = .incrementing
        }
        interruptionStore.exhaustivity = .off(showSkippedAssertions: false)

        await interruptionStore.send(.privacyInterrupted).finish()
        await interruptionStore.skipReceivedActions()
        #expect(interruptionStore.state.share?.operation == .protecting)
        #expect(await spy.cancelCalls == 1)
    }

    @Test
    func replaceShareRejectsInvalidInputAndSurfacesDependencyFailure() async throws {
        let target = try profile()
        let spy = ClientSpy()
        let store = TestStore(initialState: ReplaceShareFeature.State(profile: target)) {
            ReplaceShareFeature()
        } withDependencies: {
            $0.sealbreakClient = client(spy)
            $0.uuid = .incrementing
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.saveTapped(share: "short", recoveryConfirmed: true))
        #expect(!store.state.isBusy)
        #expect(store.state.notice.contains("share"))

        await spy.setReplaceError(AppFailure("replace failed"))
        await store.send(.saveTapped(share: share, recoveryConfirmed: true)).finish()
        await store.skipReceivedActions()
        #expect(!store.state.isBusy)
        #expect(store.state.activity.isEmpty)
        #expect(store.state.notice == "replace failed")
    }

    @Test
    func replaceShareCancellationDismissalAndPrivacyInterruptionAreSafe() async throws {
        let target = try profile()
        let spy = ClientSpy()
        await spy.setWaitCancellation(true)
        let cancellationStore = TestStore(initialState: ReplaceShareFeature.State(profile: target)) {
            ReplaceShareFeature()
        } withDependencies: {
            $0.sealbreakClient = client(spy)
            $0.uuid = .incrementing
        }
        cancellationStore.exhaustivity = .off(showSkippedAssertions: false)

        await cancellationStore.send(.saveTapped(share: share, recoveryConfirmed: true)).finish()
        await cancellationStore.skipReceivedActions()
        #expect(!cancellationStore.state.isBusy)
        #expect(cancellationStore.state.activity.isEmpty)
        #expect(cancellationStore.state.notice.contains("Operation cancelled"))

        await cancellationStore.send(.cancelTapped)
        await cancellationStore.receive(.delegate(.dismissRequested))

        var interruptedState = ReplaceShareFeature.State(profile: target)
        interruptedState.isBusy = true
        interruptedState.activity = "Waiting for Face ID…"
        let interruptionStore = TestStore(initialState: interruptedState) {
            ReplaceShareFeature()
        } withDependencies: {
            $0.sealbreakClient = client(spy)
            $0.uuid = .incrementing
        }
        interruptionStore.exhaustivity = .off(showSkippedAssertions: false)

        await interruptionStore.send(.privacyInterrupted).finish()
        #expect(!interruptionStore.state.isBusy)
        #expect(interruptionStore.state.activity.isEmpty)
        #expect(interruptionStore.state.notice.contains("Operation interrupted"))
        #expect(await spy.cancelCalls == 1)
    }

    @Test
    func appPrivacyInterruptionOnWelcomeDoesNotCancelSensitiveWork() async {
        let spy = ClientSpy()
        var initialState = AppFeature.State()
        initialState.isLoading = false
        initialState.welcome = WelcomeFeature.State()

        let store = TestStore(initialState: initialState) {
            AppFeature()
        } withDependencies: {
            $0.sealbreakClient = client(spy)
            $0.uuid = .incrementing
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.privacy(.delegate(.interrupted))).finish()

        #expect(store.state.welcome != nil)
        #expect(await spy.cancelCalls == 0)
    }

    @Test
    func appPrivacyInterruptionWithoutVisibleFeatureCancelsSensitiveWork() async {
        let spy = ClientSpy()
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.sealbreakClient = client(spy)
            $0.uuid = .incrementing
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.privacy(.delegate(.interrupted))).finish()

        #expect(await spy.cancelCalls == 1)
    }

    @Test
    func privacyConcealmentAndRepeatedCaptureChangesAreSafe() async {
        var state = PrivacyFeature.State()
        #expect(state.isConcealed)

        state.phase = .active
        #expect(!state.isConcealed)

        state.isCaptured = true
        #expect(state.isConcealed)

        state.isCaptured = false
        let store = TestStore(initialState: state) {
            PrivacyFeature()
        }
        await store.send(.captureChanged(false))
    }

    @Test
    func homeDismissesConfirmationAndRejectsUnsupportedPreflight() async throws {
        let target = try profile()
        let spy = ClientSpy()
        await spy.setStatusQueue([
            .success(status(type: "transit", threshold: 0, shares: 0, recoverySeal: true))
        ])
        let store = homeStore(profile: target, status: status(), spy: spy)

        await store.send(.unsealTapped)
        #expect(store.state.confirmation == .unseal)
        await store.send(.confirmationDismissed)
        #expect(store.state.confirmation == nil)

        await store.send(.unsealTapped)
        await store.send(.confirmUnsealTapped).finish()
        await store.skipReceivedActions()

        #expect(store.state.operation == nil)
        #expect(store.state.notice == "This target does not support manual Shamir unseal.")
        #expect(await spy.submittedCount == 0)
    }

    @Test
    func homeHandlesUnsealCancellationAndUnsupportedPostflight() async throws {
        let target = try profile()

        let cancellationSpy = ClientSpy()
        await cancellationSpy.setWaitCancellation(true)
        let cancellationStore = homeStore(profile: target, status: status(), spy: cancellationSpy)

        await cancellationStore.send(.unsealTapped)
        await cancellationStore.send(.confirmUnsealTapped).finish()
        await cancellationStore.skipReceivedActions()
        #expect(cancellationStore.state.operation == nil)
        #expect(cancellationStore.state.notice.contains("Operation cancelled"))

        let postflightSpy = ClientSpy()
        await postflightSpy.setReadRecord(try record(target))
        await postflightSpy.setStatusQueue([
            .success(status()),
            .success(status(type: "transit", threshold: 0, shares: 0, recoverySeal: true))
        ])
        let postflightStore = homeStore(profile: target, status: status(), spy: postflightSpy)

        await postflightStore.send(.unsealTapped)
        await postflightStore.send(.confirmUnsealTapped).finish()
        await postflightStore.skipReceivedActions()

        #expect(postflightStore.state.operation == nil)
        #expect(postflightStore.state.notice.contains("Unexpected seal configuration"))
        #expect(postflightStore.state.notice.contains("final outcome is unknown"))
        #expect(await postflightSpy.submittedCount == 1)
    }

    @Test
    func homeHandlesRemovalPersistenceFallbackAndCancellation() async throws {
        let target = try profile()
        let persistenceSpy = ClientSpy()
        await persistenceSpy.setLoadedProfile(target)
        await persistenceSpy.setReadRecord(try record(target))
        await persistenceSpy.setDeleteProfileError(AppFailure("delete profile failed"))
        let persistenceStore = homeStore(profile: target, status: status(), spy: persistenceSpy)

        await persistenceStore.send(.removeLocalDataTapped)
        await persistenceStore.send(.confirmRemoveLocalDataTapped).finish()
        await persistenceStore.skipReceivedActions()
        #expect(persistenceStore.state.notice.contains("Reset local Sealbreak data"))

        let cancellationSpy = ClientSpy()
        await cancellationSpy.setWaitCancellation(true)
        let cancellationStore = homeStore(profile: target, status: status(), spy: cancellationSpy)

        await cancellationStore.send(.removeLocalDataTapped)
        await cancellationStore.send(.confirmRemoveLocalDataTapped).finish()
        await cancellationStore.skipReceivedActions()
        #expect(cancellationStore.state.notice.contains("Operation cancelled"))
    }

    @Test
    func partialHomeRemovalRequiresResetAndPreventsSecondProfile() async throws {
        let first = try profile("First")
        let second = try ServerProfile(
            id: UUID(),
            name: "Second",
            address: "https://second.example.com"
        )
        let spy = ClientSpy()
        await spy.setLoadedProfile(first)
        await spy.setReadRecord(try record(first))
        await spy.setDeleteProfileError(AppFailure("delete profile failed"))

        var initialState = AppFeature.State()
        initialState.isLoading = false
        initialState.didLoad = true
        initialState.home = HomeFeature.State(profile: first, status: status())

        let appStore = TestStore(initialState: initialState) {
            AppFeature()
        } withDependencies: {
            $0.sealbreakClient = client(spy)
            $0.uuid = .incrementing
        }
        appStore.exhaustivity = .off(showSkippedAssertions: false)

        await appStore.send(.home(.removeLocalDataTapped))
        await appStore.send(.home(.confirmRemoveLocalDataTapped)).finish()
        await appStore.skipReceivedActions()

        #expect(appStore.state.home == nil)
        #expect(appStore.state.setup == nil)
        #expect(appStore.state.welcome?.requiresLocalReset == true)
        #expect(appStore.state.welcome?.notice?.contains("Reset local Sealbreak data") == true)
        #expect(await spy.currentProfiles == [first])
        #expect(await spy.currentStoredProfileState == .removing)
        #expect(await spy.currentReadRecord == nil)

        await appStore.send(.welcome(.setUpTapped))
        #expect(appStore.state.setup == nil)
        #expect(appStore.state.welcome?.requiresLocalReset == true)

        await appStore.send(.welcome(.delegate(.setUp)))
        #expect(appStore.state.setup == nil)
        #expect(appStore.state.welcome?.requiresLocalReset == true)

        let setupStore = TestStore(
            initialState: ShareSetupFeature.State(profile: second)
        ) {
            ShareSetupFeature()
        } withDependencies: {
            $0.sealbreakClient = client(spy)
            $0.uuid = .incrementing
        }
        setupStore.exhaustivity = .off(showSkippedAssertions: false)

        await setupStore.send(.saveTapped(share: share)).finish()
        await setupStore.skipReceivedActions()

        #expect(setupStore.state.operation == nil)
        #expect(setupStore.state.notice.contains("already exists"))
        #expect(await spy.currentProfiles == [first])
        #expect(await spy.insertedCount == 0)
    }

    @Test
    func setupHandlesImportCancellation() async throws {
        let target = try profile()
        let importSpy = ClientSpy()
        await importSpy.setWaitCancellation(true)
        let importStore = TestStore(
            initialState: ShareSetupFeature.State(profile: target)
        ) {
            ShareSetupFeature()
        } withDependencies: {
            $0.sealbreakClient = client(importSpy)
            $0.uuid = .incrementing
        }
        importStore.exhaustivity = .off(showSkippedAssertions: false)

        await importStore.send(
            .saveTapped(share: share)
        ).finish()
        await importStore.skipReceivedActions()
        #expect(importStore.state.operation == nil)
        #expect(importStore.state.notice.contains("Operation cancelled"))
        #expect(await importSpy.removeLocalProfileCalls == 0)
    }

}

private extension ClientSpy {
    func setLoadedProfile(_ value: ServerProfile?) {
        storedProfiles = value.map {
            [StoredProfile(profile: $0, state: .ready)]
        } ?? []
    }
    func setLoadedProfiles(_ value: [ServerProfile]) {
        storedProfiles = value.map {
            StoredProfile(profile: $0, state: .ready)
        }
    }
    func setLoadError(_ value: AppFailure?) { loadError = value }
    func setProtectOutcome(_ value: LocalPersistenceOutcome?) { protectOutcome = value }
    func setProtectError(_ value: AppFailure?) { protectError = value }
    func setRemoveOutcome(_ value: LocalPersistenceOutcome?) { removeOutcome = value }
    func setRemoveError(_ value: AppFailure?) { removeError = value }
    func setInsertProfileError(_ value: AppFailure?) { insertProfileError = value }
    func setDeleteProfileError(_ value: AppFailure?) { deleteProfileError = value }
    func setResetLocalDataError(_ value: AppFailure?) { resetLocalDataError = value }
    func setDetectedProduct(_ value: ServerProduct) { detectedProduct = value }
    func setDetectionError(_ value: AppFailure?) { detectionError = value }
    func setDNSSECStatus(_ value: DNSSECStatus) { configuredDNSSECStatus = value }
    func setStatusQueue(_ value: [Result<SealStatus, AppFailure>]) { statusQueue = value }
    func setReadRecord(_ value: ShareRecord?) { readRecord = value }
    func setReadError(_ value: AppFailure?) { readError = value }
    func setInsertError(_ value: AppFailure?) { insertError = value }
    func setReplaceError(_ value: AppFailure?) { replaceError = value }
    func setDeleteShareError(_ value: AppFailure?) { deleteShareError = value }
    func setSubmitError(_ value: AppFailure?) { submitError = value }
    func setWaitCancellation(_ value: Bool) { waitCancellation = value }

    var currentProfiles: [ServerProfile] { storedProfiles.map(\.profile) }
    var currentStoredProfileState: StoredProfileState? { storedProfiles.first?.state }
    var currentReadRecord: ShareRecord? { readRecord }
    var submittedCount: Int { submittedRecords.count }
    var insertedCount: Int { insertedRecords.count }
    var insertedBoundOrigins: [String] { insertedRecords.map(\.boundOrigin) }
    var dnssecCount: Int { dnssecCalls }
    var replacedCount: Int { replacedRecords.count }
    var savedProfilesCount: Int { savedProfiles.count }
}
