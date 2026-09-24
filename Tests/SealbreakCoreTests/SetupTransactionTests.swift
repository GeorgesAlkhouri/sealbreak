import ComposableArchitecture
import Foundation
import Testing
@testable import SealbreakCore

@MainActor
struct SetupTransactionTests {
    private let share = String(repeating: "a", count: 64)

    @Test
    func localSetupStateRequiresReadyProfile() throws {
        let profile = try ServerProfile(
            id: UUID(),
            name: "Server",
            address: "https://bao.example.com"
        )

        #expect(resolveLocalSetupState(profiles: []) == .empty)

        guard case .recoveryRequired = resolveLocalSetupState(
            profiles: [
                StoredProfile(
                    profile: profile,
                    state: .creating
                )
            ]
        ) else {
            Issue.record("Creating setup must require recovery.")
            return
        }

        #expect(
            resolveLocalSetupState(
                profiles: [
                    StoredProfile(
                        profile: profile,
                        state: .ready
                    )
                ]
            ) == .ready(profile)
        )

        guard case .recoveryRequired = resolveLocalSetupState(
            profiles: [
                StoredProfile(
                    profile: profile,
                    state: .removing
                )
            ]
        ) else {
            Issue.record("Removing profile must require recovery.")
            return
        }
    }

    @Test
    func multipleStoredProfilesRequireRecovery() throws {
        let first = try ServerProfile(
            id: UUID(),
            name: "First",
            address: "https://first.example.com"
        )
        let second = try ServerProfile(
            id: UUID(),
            name: "Second",
            address: "https://second.example.com"
        )

        guard case .recoveryRequired = resolveLocalSetupState(
            profiles: [
                StoredProfile(profile: first, state: .ready),
                StoredProfile(profile: second, state: .ready)
            ]
        ) else {
            Issue.record("Multiple local profiles must require recovery.")
            return
        }
    }

    @Test
    func privacyInterruptionLetsProtectionReportCancellation() async throws {
        let profile = try ServerProfile(
            id: UUID(),
            name: "Server",
            address: "https://bao.example.com"
        )
        let gate = ProtectionGate()

        var dependency = SealbreakClient.testValue
        dependency.protectNewProfile = { _, _, _ in
            try await gate.run()
        }
        dependency.cancelSensitiveOperation = {
            await gate.cancel()
        }

        let store = TestStore(
            initialState: ShareSetupFeature.State(profile: profile)
        ) {
            ShareSetupFeature()
        } withDependencies: {
            $0.sealbreakClient = dependency
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        let protection = await store.send(.saveTapped(share: share))
        await gate.waitUntilStarted()

        await store.send(.privacyInterrupted).finish()
        await protection.finish()
        await store.skipReceivedActions()

        #expect(store.state.operation == nil)
        #expect(String(localized: store.state.notice).contains("Operation cancelled"))
    }

    @Test
    func privacyInterruptionLetsRemovalReportCancellation() async throws {
        let profile = try ServerProfile(
            id: UUID(),
            name: "Server",
            address: "https://bao.example.com"
        )
        let gate = ProtectionGate()

        var dependency = SealbreakClient.testValue
        dependency.removeLocalProfile = { _, _ in
            try await gate.run()
        }
        dependency.cancelSensitiveOperation = {
            await gate.cancel()
        }

        let store = TestStore(
            initialState: HomeFeature.State(profile: profile)
        ) {
            HomeFeature()
        } withDependencies: {
            $0.sealbreakClient = dependency
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.removeLocalDataTapped)
        let removal = await store.send(.confirmRemoveLocalDataTapped)
        await gate.waitUntilStarted()

        await store.send(.privacyInterrupted).finish()
        #expect(store.state.operation == .removingLocalData)

        await removal.finish()
        await store.skipReceivedActions()

        #expect(store.state.operation == nil)
        #expect(String(localized: store.state.notice).contains("Operation cancelled"))
    }

    @Test
    func incompleteSetupStateRoutesAppToConfirmedReset() async {
        var dependency = SealbreakClient.testValue
        dependency.loadLocalSetupState = {
            .recoveryRequired(
                "Local setup did not finish cleanly. Reset local data to continue."
            )
        }

        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.sealbreakClient = dependency
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.task).finish()
        await store.skipReceivedActions()

        #expect(store.state.home == nil)
        #expect(store.state.setup == nil)
        #expect(store.state.welcome?.requiresLocalReset == true)
        #expect(store.state.welcome?.notice.map { String(localized: $0) }?.contains("did not finish cleanly") == true)
    }
}

private actor ProtectionGate {
    private var started = false
    private var continuation: CheckedContinuation<LocalPersistenceOutcome, any Error>?

    func run() async throws -> LocalPersistenceOutcome {
        started = true
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilStarted() async {
        while !started {
            await Task.yield()
        }
    }

    func cancel() {
        continuation?.resume(throwing: CancellationError())
        continuation = nil
    }
}
