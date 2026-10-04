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
        } withDependencies: {
            $0.uuid = .incrementing
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
        #expect(
            store.state.addressValidationError.map {
                String(localized: $0).contains("HTTPS origin")
            } == true
        )
        #expect(store.state.feedback == nil)
        #expect(!store.state.isCheckingConnection)
        #expect(store.state.checkedProfile == nil)

        await store.send(.addressChanged(origin))
        await store.send(.nameChanged(String(repeating: "a", count: 41)))
        await store.send(.checkConnectionTapped)
        #expect(
            store.state.nameValidationError.map {
                String(localized: $0).contains("1–40 characters")
            } == true
        )
        #expect(store.state.addressValidationError == nil)
        #expect(store.state.feedback == nil)
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

        #expect(store.state.feedback == .error("dnssec failed"))
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

        #expect(store.state.feedback == .error(LocalizedStringResource("Connection check cancelled.", bundle: .module)))
        #expect(!store.state.isCheckingConnection)
    }

    @Test
    func instanceStatusFailureSkipsProductDetection() async {
        let statusCalls = CallCounter()
        let detectionCalls = CallCounter()
        var dependency = SealbreakClient.testValue
        dependency.dnssecStatus = { _ in .secure }
        dependency.status = { _ in
            await statusCalls.increment()
            throw AppFailure("server unavailable")
        }
        dependency.detectProduct = { _ in
            await detectionCalls.increment()
            return .generic
        }

        let store = instanceStore(dependency)
        await store.send(.addressChanged(origin))
        await store.send(.checkConnectionTapped).finish()
        await store.skipReceivedActions()

        #expect(store.state.feedback == .error("server unavailable"))
        #expect(await statusCalls.count == 1)
        #expect(await detectionCalls.count == 0)
        #expect(store.state.checkedProfile == nil)
        #expect(!store.state.canContinue)
    }

    @Test
    func instanceDirectActionsCoverPrivacyCancellationAndContinueGuard() async throws {
        var state = InstanceSetupFeature.State()
        state.address = origin
        state.checkedProfile = try profile()
        state.dnssecStatus = .secure
        state.feedback = .info("old")
        state.isCheckingConnection = true

        let store = TestStore(initialState: state) {
            InstanceSetupFeature()
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.privacyInterrupted)
        #expect(!store.state.isCheckingConnection)
        #expect(store.state.checkedProfile == nil)
        #expect(store.state.feedback == .warning(LocalizedStringResource("Connection check interrupted. Try again.", bundle: .module)))

        await store.send(.privacyInterrupted)
        #expect(store.state.feedback == .warning(LocalizedStringResource("Connection check interrupted. Try again.", bundle: .module)))

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
        state.feedback = .success("checked")

        let store = TestStore(initialState: state) {
            InstanceSetupFeature()
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.nameChanged("Server"))
        #expect(store.state.checkedProfile != nil)

        await store.send(.nameChanged("Renamed"))
        #expect(store.state.checkedProfile == nil)
        #expect(store.state.dnssecStatus == nil)
        #expect(store.state.nameValidationError == nil)
        #expect(store.state.addressValidationError == nil)
        #expect(store.state.feedback == nil)
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
    func setupCancelRemainsAvailableDuringConnectionCheck() async {
        var state = SetupFeature.State()
        state.instance.isCheckingConnection = true

        let store = setupStore(state, dependency: .testValue)

        #expect(!store.state.blocksSetupExit)
        await store.send(.cancelTapped)
        await store.receive(.delegate(.cancelled))
    }

    @Test
    func setupCancelClearsIdleShareAndDelegates() async throws {
        var state = SetupFeature.State()
        state.step = .share
        state.share = ShareSetupFeature.State(profile: try profile())

        let store = setupStore(state, dependency: .testValue)

        await store.send(.cancelTapped)
        #expect(store.state.share == nil)
        await store.receive(.delegate(.cancelled))
    }

    @Test
    func setupForwardsShareCompletionAndRecovery() async throws {
        let target = try profile()
        var state = SetupFeature.State()
        state.step = .share
        state.share = ShareSetupFeature.State(profile: target)

        let store = setupStore(state, dependency: .testValue)
        let feedback = AppFeedback.success("saved")

        await store.send(
            .share(.delegate(.profileReady(target, feedback: feedback)))
        )
        await store.receive(.delegate(.profileReady(target, feedback: feedback)))
        #expect(store.state.feedback == feedback)

        let recovery = AppFeedback.warning("reset required")
        await store.send(
            .share(.delegate(.localResetRequired(feedback: recovery)))
        )
        await store.receive(.delegate(.localResetRequired(feedback: recovery)))
        #expect(store.state.feedback == recovery)
    }

    @Test
    func setupPrivacyRoutesOnlyToActiveChild() async throws {
        let target = try profile()

        var instanceState = SetupFeature.State()
        instanceState.instance.isCheckingConnection = true
        let instanceStore = setupStore(instanceState, dependency: .testValue)

        await instanceStore.send(.privacyInterrupted).finish()
        await instanceStore.skipReceivedActions()
        #expect(!instanceStore.state.instance.isCheckingConnection)
        #expect(instanceStore.state.instance.feedback == .warning(LocalizedStringResource("Connection check interrupted. Try again.", bundle: .module)))

        let counter = CallCounter()
        var dependency = SealbreakClient.testValue
        dependency.cancelSensitiveOperation = {
            await counter.increment()
        }

        var shareState = SetupFeature.State()
        shareState.step = .share
        shareState.share = ShareSetupFeature.State(profile: target)
        shareState.share?.operation = .protecting
        let shareStore = setupStore(shareState, dependency: dependency)

        await shareStore.send(.privacyInterrupted).finish()
        await shareStore.skipReceivedActions()
        #expect(shareStore.state.share?.operation == .protecting)
        #expect(await counter.count == 1)
    }

    @Test
    func setupBlocksDiscardWhileShareProtectionIsRunning() async throws {
        var state = SetupFeature.State()
        state.step = .share
        state.share = ShareSetupFeature.State(profile: try profile())
        state.share?.operation = .protecting

        let store = setupStore(state, dependency: .testValue)

        await store.send(.cancelTapped)

        #expect(store.state.step == .share)
        #expect(store.state.share?.operation == .protecting)
    }

    @Test
    func setupActivityMapsOnlyReachableOperations() throws {
        var state = SetupFeature.State()

        state.instance.isCheckingConnection = true
        #expect(state.activity == LocalizedStringResource("Checking connection…", bundle: .module))
        #expect(state.isBusy)
        #expect(!state.blocksSetupExit)

        state.instance.isCheckingConnection = false
        state.step = .share
        state.share = ShareSetupFeature.State(profile: try profile())
        state.share?.operation = .protecting
        #expect(state.activity == LocalizedStringResource("Protecting share…", bundle: .module))
        #expect(state.isBusy)
        #expect(state.blocksSetupExit)

        state.share?.operation = nil
        #expect(state.activity == nil)
        #expect(!state.isBusy)
    }

    private func instanceStore(
        _ dependency: SealbreakClient
    ) -> TestStore<InstanceSetupFeature.State, InstanceSetupFeature.Action> {
        let store = TestStore(initialState: InstanceSetupFeature.State()) {
            InstanceSetupFeature()
        } withDependencies: {
            $0.sealbreakClient = dependency
            $0.uuid = .incrementing
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
        try ServerProfile(id: UUID(), name: "Server", address: origin)
    }
}

private actor CallCounter {
    private(set) var count = 0

    func increment() {
        count += 1
    }
}
