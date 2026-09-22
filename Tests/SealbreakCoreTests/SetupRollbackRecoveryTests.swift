import ComposableArchitecture
import Foundation
import Testing
@testable import SealbreakCore

@MainActor
struct SetupRollbackRecoveryTests {
    @Test
    func failedShareInsertAndFailedRollbackRequireConfirmedReset() async throws {
        let profile = try ServerProfile(
            id: UUID(),
            name: "Server",
            address: "https://bao.example.com"
        )
        let spy = RollbackFailureSpy()

        var dependency = SealbreakClient.testValue
        dependency.loadProfiles = {
            await spy.loadProfiles()
        }
        dependency.insertProfile = { profile in
            try await spy.insertProfile(profile)
        }
        dependency.insertShare = { _, _ in
            try await spy.insertShare()
        }
        dependency.deleteProfile = { profileID in
            try await spy.deleteProfile(profileID)
        }
        dependency.resetLocalData = {
            try await spy.resetLocalData()
        }
        dependency.waitForForeground = {}

        var initialState = AppFeature.State()
        initialState.isLoading = false
        initialState.didLoad = true

        var setupState = SetupFeature.State()
        setupState.step = .share
        setupState.share = ShareSetupFeature.State(profile: profile)
        initialState.setup = setupState

        let store = TestStore(initialState: initialState) {
            AppFeature()
        } withDependencies: {
            $0.sealbreakClient = dependency
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(
            .setup(
                .share(
                    .saveTapped(
                        share: String(repeating: "a", count: 64)
                    )
                )
            )
        ).finish()
        await store.skipReceivedActions()

        #expect(await spy.insertProfileCalls == 1)
        #expect(await spy.insertShareCalls == 1)
        #expect(await spy.deleteProfileCalls == 1)
        #expect(await spy.currentProfiles == [profile])

        #expect(store.state.setup == nil)
        #expect(store.state.home == nil)
        #expect(store.state.welcome?.requiresLocalReset == true)
        #expect(
            store.state.welcome?.notice?.contains(
                "temporary local profile could not be removed"
            ) == true
        )

        await store.send(.welcome(.setUpTapped))

        #expect(store.state.setup == nil)
        #expect(store.state.welcome?.requiresLocalReset == true)
        #expect(await spy.insertProfileCalls == 1)
        #expect(await spy.currentProfiles == [profile])

        await store.send(.welcome(.resetLocalDataTapped))
        #expect(store.state.welcome?.confirmReset == true)

        await store.send(.welcome(.confirmResetLocalDataTapped)).finish()
        await store.skipReceivedActions()

        #expect(await spy.resetLocalDataCalls == 1)
        #expect(await spy.currentProfiles == [])
        #expect(store.state.welcome?.requiresLocalReset == false)
        #expect(store.state.welcome?.confirmReset == false)
        #expect(store.state.welcome?.notice?.contains("was reset") == true)
    }
}

private actor RollbackFailureSpy {
    private var profiles: [ServerProfile] = []

    private(set) var insertProfileCalls = 0
    private(set) var insertShareCalls = 0
    private(set) var deleteProfileCalls = 0
    private(set) var resetLocalDataCalls = 0

    var currentProfiles: [ServerProfile] {
        profiles
    }

    func loadProfiles() -> [ServerProfile] {
        profiles
    }

    func insertProfile(_ profile: ServerProfile) throws {
        insertProfileCalls += 1
        guard profiles.isEmpty else {
            throw AppFailure("A local server profile already exists.")
        }
        profiles.append(profile)
    }

    func insertShare() throws {
        insertShareCalls += 1
        throw AppFailure("share insert failed")
    }

    func deleteProfile(_ profileID: UUID) throws {
        deleteProfileCalls += 1
        guard profiles.contains(where: { $0.id == profileID }) else {
            throw AppFailure("Profile not found.")
        }
        throw AppFailure("rollback failed")
    }

    func resetLocalData() throws {
        resetLocalDataCalls += 1
        profiles.removeAll()
    }
}
