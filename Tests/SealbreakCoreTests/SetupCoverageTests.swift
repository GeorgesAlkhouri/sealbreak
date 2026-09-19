import ComposableArchitecture
import Foundation
import Testing
@testable import SealbreakCore

@MainActor
struct SetupCoverageTests {
    private let origin = "https://bao.example.com"

    @Test
    func instanceStateAndValidationBranches() async {
        let store = TestStore(initialState: InstanceSetupFeature.State()) {
            InstanceSetupFeature()
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        #expect(!store.state.canCheckConnection)
        #expect(!store.state.canContinue)
        #expect(!store.state.hasDraft)

        await store.send(.checkConnectionTapped)
        #expect(!store.state.isCheckingConnection)

        await store.send(.nameChanged("Server"))
        #expect(!store.state.hasDraft)

        await store.send(.nameChanged(""))
        #expect(store.state.hasDraft)
        await store.send(.addressChanged(origin))
        #expect(!store.state.canCheckConnection)

        await store.send(.nameChanged("Production"))
        #expect(store.state.canCheckConnection)

        await store.send(.addressChanged(origin))
        #expect(store.state.canCheckConnection)

        await store.send(.addressChanged("http://not-https.example.com"))
        await store.send(.checkConnectionTapped)
        #expect(store.state.notice?.contains("HTTPS origin") == true)
        #expect(!store.state.isCheckingConnection)
        #expect(store.state.checkedProfile == nil)
    }

    @Test
    func instanceDNSSECFailureIsSurfaced() async {
        var dependency = SealbreakClient.testValue
        dependency.dnssecStatus = { _ in
            throw AppFailure("dnssec failed")
        }

        let store = instanceStore(dependency)
        await store.send(.addressChanged(origin))
        await store.send(.checkConnectionTapped).finish()
        await store.skipReceivedActions()

        #expect(store.state.notice == "dnssec failed")
        #expect(!store.state.isCheckingConnection)
        #expect(store.state.checkedProfile == nil)
    }

    @Test
    func instanceCancellationIsSurfaced() async {
        var dependency = SealbreakClient.testValue
        dependency.dnssecStatus = { _ in
            throw CancellationError()
        }

        let store = instanceStore(dependency)
        await store.send(.addressChanged(origin))
        await store.send(.checkConnectionTapped).finish()
        await store.skipReceivedActions()

        #expect(store.state.notice == "Connection check cancelled.")
        #expect(!store.state.isCheckingConnection)
    }

    @Test
    func instanceGenericFallbackRequiresReachableServer() async {
        var dependency = SealbreakClient.testValue
        dependency.dnssecStatus = { _ in .secure }
        dependency.detectProduct = { _ in
            throw AppFailure("product metadata unavailable")
        }
        dependency.status = { _ in
            throw AppFailure("server unavailable")
        }

        let store = instanceStore(dependency)
        await store.send(.addressChanged(origin))
        await store.send(.checkConnectionTapped).finish()
        await store.skipReceivedActions()

        #expect(store.state.notice == "server unavailable")
        #expect(store.state.checkedProfile == nil)
        #expect(!store.state.canContinue)
    }

    @Test
    func instanceDirectActionsCoverPrivacyCancellationAndContinueGuard() async throws {
        var state = InstanceSetupFeature.State()
        state.address = origin
        state.checkedProfile = try profile()
        state.dnssecStatus = .secure
        state.notice = "old"
        state.isCheckingConnection = true

        let store = TestStore(initialState: state) {
            InstanceSetupFeature()
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.privacyInterrupted)
        #expect(!store.state.isCheckingConnection)
        #expect(store.state.checkedProfile == nil)
        #expect(store.state.notice == "Connection check interrupted. Try again.")

        await store.send(.privacyInterrupted)
        #expect(store.state.notice == "Connection check interrupted. Try again.")

        var cancelState = InstanceSetupFeature.State()
        cancelState.isCheckingConnection = true
        let cancelStore = TestStore(initialState: cancelState) {
            InstanceSetupFeature()
        }
        cancelStore.exhaustivity = .off(showSkippedAssertions: false)

        await cancelStore.send(.cancelCheck)
        #expect(!cancelStore.state.isCheckingConnection)

        await store.send(.continueTapped)
        #expect(store.state.checkedProfile == nil)
    }

    @Test
    func instanceNameEditInvalidatesSuccessfulCheck() async throws {
        var state = InstanceSetupFeature.State()
        state.name = "Server"
        state.address = origin
        state.checkedProfile = try profile()
        state.dnssecStatus = .secure
        state.notice = "checked"

        let store = TestStore(initialState: state) {
            InstanceSetupFeature()
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.nameChanged("Server"))
        #expect(store.state.checkedProfile != nil)

        await store.send(.nameChanged("Renamed"))
        #expect(store.state.checkedProfile == nil)
        #expect(store.state.dnssecStatus == nil)
        #expect(store.state.notice == nil)
    }

    @Test
    func setupBackNavigationCoversIdleAndBusyShare() async throws {
        let target = try profile()

        var idleState = SetupFeature.State()
        idleState.step = .share
        idleState.share = ShareSetupFeature.State(profile: target)
        let idleStore = setupStore(idleState, dependency: .testValue)

        await idleStore.send(.backTapped)
        #expect(idleStore.state.step == .instance)
        #expect(idleStore.state.share == nil)

        var busyState = SetupFeature.State()
        busyState.step = .share
        busyState.share = ShareSetupFeature.State(profile: target)
        busyState.share?.operation = .protecting
        let busyStore = setupStore(busyState, dependency: .testValue)

        await busyStore.send(.backTapped)
        #expect(busyStore.state.step == .share)
        #expect(busyStore.state.share?.operation == .protecting)
    }

    @Test
    func setupCancelClearsWorkflowAndCancelsSensitiveOperation() async throws {
        let counter = CallCounter()
        var dependency = SealbreakClient.testValue
        dependency.cancelSensitiveOperation = {
            await counter.increment()
        }

        var state = SetupFeature.State()
        state.operation = .restoring
        state.confirmDelete = true
        state.step = .share
        state.share = ShareSetupFeature.State(profile: try profile())

        let store = setupStore(state, dependency: dependency)
        await store.send(.cancelTapped).finish()
        await store.skipReceivedActions()

        #expect(store.state.operation == nil)
        #expect(!store.state.confirmDelete)
        #expect(store.state.share == nil)
        #expect(await counter.count == 1)
    }

    @Test
    func setupForwardsShareCompletion() async throws {
        let target = try profile()
        var state = SetupFeature.State()
        state.step = .share
        state.share = ShareSetupFeature.State(profile: target)

        let store = setupStore(state, dependency: .testValue)
        let notice = "saved"

        await store.send(
            .share(.delegate(.profileReady(target, notice: notice)))
        )
        await store.receive(.delegate(.profileReady(target, notice: notice)))
        #expect(store.state.notice == notice)
    }

    @Test
    func setupPrivacyRoutesToInstanceShareAndOwnOperation() async throws {
        let target = try profile()

        var instanceState = SetupFeature.State()
        instanceState.instance.isCheckingConnection = true
        let instanceStore = setupStore(instanceState, dependency: .testValue)

        await instanceStore.send(.privacyInterrupted(.background)).finish()
        await instanceStore.skipReceivedActions()
        #expect(!instanceStore.state.instance.isCheckingConnection)
        #expect(instanceStore.state.instance.notice == "Connection check interrupted. Try again.")

        let shareCounter = CallCounter()
        var shareDependency = SealbreakClient.testValue
        shareDependency.cancelSensitiveOperation = {
            await shareCounter.increment()
        }
        var shareState = SetupFeature.State()
        shareState.step = .share
        shareState.share = ShareSetupFeature.State(profile: target)
        shareState.share?.operation = .protecting
        let shareStore = setupStore(shareState, dependency: shareDependency)

        await shareStore.send(.privacyInterrupted(.background)).finish()
        await shareStore.skipReceivedActions()
        #expect(shareStore.state.share?.operation == .protecting)
        #expect(shareStore.state.share?.backgroundedDuringProtection == true)
        #expect(await shareCounter.count == 0)

        await shareStore.send(.privacyInterrupted(.screenCapture)).finish()
        await shareStore.skipReceivedActions()
        #expect(shareStore.state.share?.operation == nil)
        #expect(shareStore.state.share?.draftClearGeneration == 1)
        #expect(await shareCounter.count == 1)

        let ownCounter = CallCounter()
        var ownDependency = SealbreakClient.testValue
        ownDependency.cancelSensitiveOperation = {
            await ownCounter.increment()
        }
        var ownState = SetupFeature.State()
        ownState.operation = .removingLocalData
        ownState.confirmDelete = true
        let ownStore = setupStore(ownState, dependency: ownDependency)

        await ownStore.send(.privacyInterrupted(.background)).finish()
        #expect(ownStore.state.operation == nil)
        #expect(!ownStore.state.confirmDelete)
        #expect(ownStore.state.notice.contains("Operation interrupted"))
        #expect(await ownCounter.count == 1)
    }

    @Test
    func setupBusyStateBlocksRestoreAndRemove() async {
        var state = SetupFeature.State()
        state.instance.isCheckingConnection = true
        let store = setupStore(state, dependency: .testValue)

        await store.send(.restoreProfileTapped)
        #expect(store.state.operation == nil)

        await store.send(.removeLocalDataTapped)
        #expect(!store.state.confirmDelete)

        await store.send(.confirmRemoveLocalDataTapped)
        #expect(store.state.operation == nil)
    }

    private func instanceStore(
        _ dependency: SealbreakClient
    ) -> TestStore<InstanceSetupFeature.State, InstanceSetupFeature.Action> {
        let store = TestStore(initialState: InstanceSetupFeature.State()) {
            InstanceSetupFeature()
        } withDependencies: {
            $0.sealbreakClient = dependency
        }
        store.exhaustivity = .off(showSkippedAssertions: false)
        return store
    }

    private func setupStore(
        _ state: SetupFeature.State,
        dependency: SealbreakClient
    ) -> TestStore<SetupFeature.State, SetupFeature.Action> {
        let store = TestStore(initialState: state) {
            SetupFeature()
        } withDependencies: {
            $0.sealbreakClient = dependency
        }
        store.exhaustivity = .off(showSkippedAssertions: false)
        return store
    }

    private func profile() throws -> ServerProfile {
        try ServerProfile(name: "Server", address: origin)
    }
}

private actor CallCounter {
    private(set) var count = 0

    func increment() {
        count += 1
    }
}
