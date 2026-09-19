import ComposableArchitecture
import Foundation
import Testing
@testable import SealbreakCore

private actor ClientSpy {
    var loadedProfile: ServerProfile?
    var loadError: AppFailure?
    var saveProfileError: AppFailure?
    var deleteProfileError: AppFailure?
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
        if waitCancellation { throw CancellationError() }
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
        detectProduct: { _ in try await spy.detectProduct() },
        dnssecStatus: { _ in await spy.dnssecStatus() },
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

    private func profile(
        _ name: String = "Server",
        product: ServerProduct = .generic
    ) throws -> ServerProfile {
        try ServerProfile(name: name, address: origin, product: product)
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

        #expect(store.state.welcome == nil)
        #expect(store.state.setup == nil)
        #expect(store.state.home?.profile == target)
        #expect(store.state.home?.status == checked)
        #expect(store.state.home?.notice == "Status checked. Nothing is sent automatically.")
    }

    @Test
    func appLoadFailureEntersWelcome() async {
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
        #expect(store.state.setup == nil)
        #expect(store.state.welcome?.notice?.contains("could not be read") == true)
    }

    @Test
    func welcomeRoutesPrimaryAndRestoreIntent() async {
        let store = TestStore(initialState: WelcomeFeature.State()) {
            WelcomeFeature()
        }

        await store.send(.setUpTapped)
        await store.receive(.delegate(.setUp))
        await store.send(.restoreTapped)
        await store.receive(.delegate(.restore))
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
    func appWelcomeRestoreUsesExistingKeychainFlow() async throws {
        let target = try profile(product: .openBao)
        let checked = status()
        let spy = ClientSpy()
        await spy.setReadRecord(try record(target))
        await spy.setStatusQueue([.success(checked)])

        var initialState = AppFeature.State()
        initialState.isLoading = false
        initialState.welcome = WelcomeFeature.State()

        let store = TestStore(initialState: initialState) {
            AppFeature()
        } withDependencies: {
            $0.sealbreakClient = client(spy)
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.welcome(.delegate(.restore))).finish()
        await store.skipReceivedActions()

        #expect(store.state.welcome == nil)
        #expect(store.state.setup == nil)
        #expect(store.state.home?.profile == target)
        #expect(store.state.home?.status == checked)
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
    func setupImportProtectsShareWithoutRecoveryConfirmation() async throws {
        let target = try profile(product: .vault)
        let spy = ClientSpy()
        let store = TestStore(
            initialState: ShareSetupFeature.State(profile: target)
        ) {
            ShareSetupFeature()
        } withDependencies: {
            $0.sealbreakClient = client(spy)
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.saveTapped(share: share)).finish()
        let savedNotice = "Share protected on this iPhone. Check status to begin."
        await store.receive(.importResponse(.success(.init(profile: target, notice: savedNotice))))
        await store.receive(.delegate(.profileReady(target, notice: savedNotice)))

        #expect(store.state.operation == nil)
        #expect(store.state.notice.contains("Share protected"))
        #expect(await spy.insertedCount == 1)
        #expect(await spy.insertedProducts == [.vault])
        #expect(await spy.savedProfilesCount == 1)
    }

    @Test
    func shareImportPreviewShowsOnlyBoundedFragments() {
        let input = String(repeating: "0123456789abcdef", count: 4)

        #expect(
            ShareImportPreview.masked(input)
                == "0123 •••• •••• cdef"
        )
        #expect(ShareImportPreview.masked("short") == nil)
        #expect(ShareImportPreview.masked(input) != input)
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
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.addressChanged(origin))
        await store.send(.checkConnectionTapped).finish()
        await store.skipReceivedActions()

        #expect(store.state.checkedProfile?.product == .generic)
        #expect(store.state.canContinue)
        #expect(await spy.detectProductCalls == 1)
    }

    @Test
    func setupImportPreservesShareWhenDisplayProfileSaveFails() async throws {
        let target = try profile()
        let spy = ClientSpy()
        await spy.setSaveProfileError(AppFailure("save failed"))
        let store = TestStore(
            initialState: ShareSetupFeature.State(profile: target)
        ) {
            ShareSetupFeature()
        } withDependencies: {
            $0.sealbreakClient = client(spy)
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(
            .saveTapped(share: share)
        ).finish()
        let fallbackNotice =
            "Protected share exists, but display metadata could not be saved. Use Restore profile from Keychain on the next launch."
        await store.receive(.importResponse(.success(.init(profile: target, notice: fallbackNotice))))
        await store.receive(.delegate(.profileReady(target, notice: fallbackNotice)))

        #expect(await spy.insertedCount == 1)
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
            "Local share replaced. This does not rotate server keys; server-side rekeying is a separate operation."
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
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(
            .setup(.delegate(.profileReady(target, notice: "Profile restored")))
        ).finish()
        await store.skipReceivedActions()
        #expect(store.state.setup == nil)
        #expect(store.state.home?.profile == target)
        #expect(store.state.home?.status == checked)

        await store.send(.home(.delegate(.localDataRemoved(notice: "Local data removed"))))
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
        }
        setupStore.exhaustivity = .off(showSkippedAssertions: false)

        await setupStore.send(.privacy(.delegate(.interrupted))).finish()
        await setupStore.skipReceivedActions()
        #expect(await setupSpy.cancelCalls == 1)
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
        await store.send(.replaceShare(.presented(.delegate(.saved(notice: "Share replaced")))))
        #expect(store.state.replaceShare == nil)
        #expect(store.state.status == nil)
        #expect(store.state.notice == "Share replaced")

        await store.send(.replaceShareTapped)
        await store.send(.replaceShare(.presented(.delegate(.dismissRequested))))
        #expect(store.state.replaceShare == nil)
    }

    @Test
    func homeRestoresProfileAndRemovesLocalData() async throws {
        let original = try profile("Original")
        let restored = try profile("Restored")
        let spy = ClientSpy()
        await spy.setReadRecord(try record(restored))
        let store = TestStore(initialState: HomeFeature.State(profile: original, status: status())) {
            HomeFeature()
        } withDependencies: {
            $0.sealbreakClient = client(spy)
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.restoreProfileTapped).finish()
        await store.skipReceivedActions()
        #expect(store.state.profile == restored)
        #expect(store.state.status == nil)
        #expect(store.state.notice.contains("Protected target restored"))

        await store.send(.serverDetailsTapped)
        await store.send(.replaceShareTapped)
        #expect(store.state.serverDetails?.profile == restored)
        #expect(store.state.replaceShare?.profile == restored)

        await store.send(.removeLocalDataTapped)
        #expect(store.state.confirmation == .removeLocalData)
        await store.send(.confirmRemoveLocalDataTapped).finish()
        await store.skipReceivedActions()

        #expect(store.state.operation == nil)
        #expect(store.state.status == nil)
        #expect(store.state.serverDetails == nil)
        #expect(store.state.replaceShare == nil)
        #expect(store.state.notice.contains("Local share removed"))
        #expect(await spy.deleteShareCalls == 1)
        #expect(await spy.deleteProfileCalls == 1)
    }

    @Test
    func homeSurfacesRestoreAndRemoveFailures() async throws {
        let target = try profile()
        let spy = ClientSpy()
        await spy.setReadError(AppFailure("restore failed"))
        let store = homeStore(profile: target, status: status(), spy: spy)

        await store.send(.restoreProfileTapped).finish()
        await store.skipReceivedActions()
        #expect(store.state.operation == nil)
        #expect(store.state.notice == "restore failed")

        await spy.setReadError(nil)
        await spy.setDeleteShareError(AppFailure("delete failed"))
        await store.send(.removeLocalDataTapped)
        await store.send(.confirmRemoveLocalDataTapped).finish()
        await store.skipReceivedActions()
        #expect(store.state.operation == nil)
        #expect(store.state.notice == "delete failed")
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
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(
            .saveTapped(share: "short")
        )
        #expect(store.state.operation == nil)
        #expect(store.state.notice.contains("share"))

        await spy.setInsertError(AppFailure("insert failed"))
        await store.send(
            .saveTapped(share: share)
        ).finish()
        await store.skipReceivedActions()
        #expect(store.state.operation == nil)
        #expect(store.state.notice == "insert failed")
    }

    @Test
    func setupCancellationAndPrivacyInterruptionClearSensitiveState() async throws {
        let spy = ClientSpy()
        await spy.setWaitCancellation(true)
        let cancellationStore = TestStore(initialState: SetupFeature.State()) {
            SetupFeature()
        } withDependencies: {
            $0.sealbreakClient = client(spy)
        }
        cancellationStore.exhaustivity = .off(showSkippedAssertions: false)

        await cancellationStore.send(.restoreProfileTapped).finish()
        await cancellationStore.skipReceivedActions()
        #expect(cancellationStore.state.operation == nil)
        #expect(cancellationStore.state.notice.contains("Operation cancelled"))

        let target = try profile()
        var interruptedState = SetupFeature.State()
        interruptedState.step = .share
        interruptedState.share = ShareSetupFeature.State(profile: target)
        interruptedState.share?.operation = .protecting
        let interruptionStore = TestStore(initialState: interruptedState) {
            SetupFeature()
        } withDependencies: {
            $0.sealbreakClient = client(spy)
        }
        interruptionStore.exhaustivity = .off(showSkippedAssertions: false)

        await interruptionStore.send(.privacyInterrupted).finish()
        await interruptionStore.skipReceivedActions()
        #expect(interruptionStore.state.share?.operation == nil)
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
    func homeHandlesPersistenceFallbacksAndCancellation() async throws {
        let target = try profile()
        let persistenceSpy = ClientSpy()
        await persistenceSpy.setReadRecord(try record(target))
        await persistenceSpy.setSaveProfileError(AppFailure("save failed"))
        let persistenceStore = homeStore(profile: target, status: status(), spy: persistenceSpy)

        await persistenceStore.send(.restoreProfileTapped).finish()
        await persistenceStore.skipReceivedActions()
        #expect(persistenceStore.state.notice.contains("display metadata could not be saved"))

        await persistenceSpy.setDeleteProfileError(AppFailure("delete profile failed"))
        await persistenceStore.send(.removeLocalDataTapped)
        await persistenceStore.send(.confirmRemoveLocalDataTapped).finish()
        await persistenceStore.skipReceivedActions()
        #expect(persistenceStore.state.notice.contains("display file could not be removed"))

        let cancellationSpy = ClientSpy()
        await cancellationSpy.setWaitCancellation(true)
        let cancellationStore = homeStore(profile: target, status: status(), spy: cancellationSpy)

        await cancellationStore.send(.restoreProfileTapped).finish()
        await cancellationStore.skipReceivedActions()
        #expect(cancellationStore.state.notice.contains("Operation cancelled"))

        await cancellationStore.send(.removeLocalDataTapped)
        await cancellationStore.send(.confirmRemoveLocalDataTapped).finish()
        await cancellationStore.skipReceivedActions()
        #expect(cancellationStore.state.notice.contains("Operation cancelled"))
    }

    @Test
    func setupOperationActivityMapsEveryState() throws {
        var state = SetupFeature.State()
        state.operation = .restoring
        #expect(state.activity == "Restoring local profile…")
        #expect(state.isBusy)

        state.operation = .removingLocalData
        #expect(state.activity == "Removing local data…")

        state.operation = nil
        state.instance.isCheckingConnection = true
        #expect(state.activity == "Checking connection…")

        state.instance.isCheckingConnection = false
        state.step = .share
        state.share = ShareSetupFeature.State(profile: try profile())
        state.share?.operation = .protecting
        #expect(state.activity == "Protecting share…")

        state.share?.operation = nil
        #expect(state.activity.isEmpty)
    }

    @Test
    func setupHandlesImportCancellationAndRestoreOutcomes() async throws {
        let target = try profile()
        let importSpy = ClientSpy()
        await importSpy.setWaitCancellation(true)
        let importStore = TestStore(
            initialState: ShareSetupFeature.State(profile: target)
        ) {
            ShareSetupFeature()
        } withDependencies: {
            $0.sealbreakClient = client(importSpy)
        }
        importStore.exhaustivity = .off(showSkippedAssertions: false)

        await importStore.send(
            .saveTapped(share: share)
        ).finish()
        await importStore.skipReceivedActions()
        #expect(importStore.state.operation == nil)
        #expect(importStore.state.notice.contains("Operation cancelled"))

        let fallbackSpy = ClientSpy()
        await fallbackSpy.setReadRecord(try record(target))
        await fallbackSpy.setSaveProfileError(AppFailure("save failed"))
        let fallbackStore = TestStore(initialState: SetupFeature.State()) {
            SetupFeature()
        } withDependencies: {
            $0.sealbreakClient = client(fallbackSpy)
        }
        fallbackStore.exhaustivity = .off(showSkippedAssertions: false)

        await fallbackStore.send(.restoreProfileTapped).finish()
        await fallbackStore.skipReceivedActions()
        #expect(fallbackStore.state.notice.contains("display metadata could not be saved"))

        let failureSpy = ClientSpy()
        await failureSpy.setReadError(AppFailure("restore failed"))
        let failureStore = TestStore(initialState: SetupFeature.State()) {
            SetupFeature()
        } withDependencies: {
            $0.sealbreakClient = client(failureSpy)
        }
        failureStore.exhaustivity = .off(showSkippedAssertions: false)

        await failureStore.send(.restoreProfileTapped).finish()
        await failureStore.skipReceivedActions()
        #expect(failureStore.state.operation == nil)
        #expect(failureStore.state.notice == "restore failed")
    }
    @Test
    func setupHandlesConfirmationAndRemoveOutcomes() async throws {
        let successSpy = ClientSpy()
        let successStore = TestStore(initialState: SetupFeature.State()) {
            SetupFeature()
        } withDependencies: {
            $0.sealbreakClient = client(successSpy)
        }
        successStore.exhaustivity = .off(showSkippedAssertions: false)

        await successStore.send(.removeLocalDataTapped)
        #expect(successStore.state.confirmDelete)
        await successStore.send(.confirmationDismissed)
        #expect(!successStore.state.confirmDelete)

        await successStore.send(.removeLocalDataTapped)
        await successStore.send(.confirmRemoveLocalDataTapped).finish()
        await successStore.skipReceivedActions()
        #expect(successStore.state.notice.contains("Local share removed"))

        let cancellationSpy = ClientSpy()
        await cancellationSpy.setWaitCancellation(true)
        let cancellationStore = TestStore(initialState: SetupFeature.State()) {
            SetupFeature()
        } withDependencies: {
            $0.sealbreakClient = client(cancellationSpy)
        }
        cancellationStore.exhaustivity = .off(showSkippedAssertions: false)

        await cancellationStore.send(.removeLocalDataTapped)
        await cancellationStore.send(.confirmRemoveLocalDataTapped).finish()
        await cancellationStore.skipReceivedActions()
        #expect(cancellationStore.state.operation == nil)
        #expect(cancellationStore.state.notice.contains("Operation cancelled"))

        let failureSpy = ClientSpy()
        await failureSpy.setDeleteShareError(AppFailure("delete failed"))
        let failureStore = TestStore(initialState: SetupFeature.State()) {
            SetupFeature()
        } withDependencies: {
            $0.sealbreakClient = client(failureSpy)
        }
        failureStore.exhaustivity = .off(showSkippedAssertions: false)

        await failureStore.send(.removeLocalDataTapped)
        await failureStore.send(.confirmRemoveLocalDataTapped).finish()
        await failureStore.skipReceivedActions()
        #expect(failureStore.state.operation == nil)
        #expect(failureStore.state.notice == "delete failed")
    }
}

private extension ClientSpy {
    func setLoadedProfile(_ value: ServerProfile?) { loadedProfile = value }
    func setLoadError(_ value: AppFailure?) { loadError = value }
    func setSaveProfileError(_ value: AppFailure?) { saveProfileError = value }
    func setDeleteProfileError(_ value: AppFailure?) { deleteProfileError = value }
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

    var submittedCount: Int { submittedRecords.count }
    var insertedCount: Int { insertedRecords.count }
    var insertedProducts: [ServerProduct] { insertedRecords.map { $0.profile.product } }
    var dnssecCount: Int { dnssecCalls }
    var replacedCount: Int { replacedRecords.count }
    var savedProfilesCount: Int { savedProfiles.count }
}
