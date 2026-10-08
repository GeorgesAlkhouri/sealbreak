import ComposableArchitecture
import Foundation
import Testing
@testable import SealbreakCore

@Suite(.timeLimit(.minutes(1)))
@MainActor
struct PrivacyReducerIntegrationTests {
    @Test
    func inactiveKeepsAuthorizedFragmentInPresentedStateUntilRealInterruption() async throws {
        let profile = try profile()
        let probe = PrivacyClientProbe()
        defer { probe.close() }
        let fragment = ShareComparisonFragment(validatedShare: PrivacyRootFixture.share)
        let clock = TestClock()
        var client = PrivacyRootFixture.client(probe)
        client.readShareFragment = { _, _ in fragment }
        let store = TestStore(initialState: initialState(profile)) { AppFeature() } withDependencies: {
            $0.sealbreakClient = client
            $0.continuousClock = clock
        }

        await store.send(.home(.serverDetailsTapped)) {
            $0.home?.serverDetails = ServerDetailsFeature.State(profile: profile, status: PrivacyRootFixture.status, isBusy: false, activity: nil)
        }
        await store.send(.home(.serverDetails(.presented(.shareFragmentTapped)))) {
            $0.home?.serverDetails?.isRevealingShare = true
        }
        await store.receive(.home(.serverDetails(.presented(.shareFragmentLoaded(fragment))))) {
            $0.home?.serverDetails?.isRevealingShare = false
            $0.home?.serverDetails?.shareFragment = fragment
        }
        await store.send(.privacy(.phaseChanged(.inactive))) { $0.privacy.phase = .inactive }
        #expect(store.state.privacy.isConcealed)
        #expect(store.state.home?.serverDetails?.shareFragment == fragment)
        await store.send(.privacy(.phaseChanged(.background))) { $0.privacy.phase = .background }
        await store.receive(.privacy(.delegate(.interrupted)))
        await store.receive(.home(.privacyInterrupted)) {
            $0.home?.status = nil
            $0.home?.serverDetails = nil
        }
        await clock.advance(by: .seconds(20))
        await store.finish()
        #expect(probe.cancelCount == 1)
        #expect(probe.forbiddenCalls.isEmpty)
    }

    @Test(arguments: PrivacySheet.allCases, PrivacyInterruption.allCases)
    func interruptionDismissesPendingChildAndLateAuthorizationCannotRestoreIt(sheet: PrivacySheet, interruption: PrivacyInterruption) async throws {
        let profile = try profile()
        let probe = PrivacyClientProbe()
        defer { probe.close() }
        let clock = TestClock()
        let store = TestStore(initialState: initialState(profile)) { AppFeature() } withDependencies: {
            $0.sealbreakClient = PrivacyRootFixture.client(probe)
            $0.continuousClock = clock
        }
        if sheet == .details {
            await store.send(.home(.serverDetailsTapped)) {
                $0.home?.serverDetails = ServerDetailsFeature.State(profile: profile, status: PrivacyRootFixture.status, isBusy: false, activity: nil)
            }
            await store.send(.home(.serverDetails(.presented(.shareFragmentTapped)))) {
                $0.home?.serverDetails?.isRevealingShare = true
            }
        } else {
            await store.send(.home(.replaceShareTapped)) {
                $0.home?.replaceShare = ReplaceShareFeature.State(profile: profile)
            }
            await store.send(.home(.replaceShare(.presented(.saveTapped(share: PrivacyRootFixture.share))))) {
                $0.home?.replaceShare?.isBusy = true
                $0.home?.replaceShare?.activity = LocalizedStringResource("Waiting for Face ID…", bundle: .module)
            }
        }
        try await waitUntil { sheet == .details ? probe.pendingCount == 1 : probe.pendingReplacementCount == 1 }

        if interruption == .background {
            await store.send(.privacy(.phaseChanged(.background))) { $0.privacy.phase = .background }
        } else {
            await store.send(.privacy(.captureChanged(true))) { $0.privacy.isCaptured = true }
        }
        await store.receive(.privacy(.delegate(.interrupted)))
        await store.receive(.home(.privacyInterrupted)) {
            $0.home?.status = nil
            $0.home?.serverDetails = nil
            $0.home?.replaceShare = nil
        }
        try await waitUntil { probe.cancelCount == 1 && (sheet == .details ? probe.fragmentWasCancelled : probe.replacementWasCancelled) }
        if sheet == .details {
            probe.succeed(ShareComparisonFragment(validatedShare: PrivacyRootFixture.share))
        } else {
            probe.completeReplacement()
        }
        await clock.advance(by: .seconds(20))
        await store.finish()
        #expect(store.state.home?.serverDetails == nil)
        #expect(store.state.home?.replaceShare == nil)
        #expect(probe.forbiddenCalls.isEmpty)
    }

    private func initialState(_ profile: ServerProfile) -> AppFeature.State {
        var state = AppFeature.State()
        state.didLoad = true
        state.isLoading = false
        state.privacy.phase = .active
        state.home = HomeFeature.State(profile: profile, status: PrivacyRootFixture.status)
        return state
    }

    private func profile() throws -> ServerProfile {
        try ServerProfile(id: UUID(), name: "Synthetic", address: "https://bao.example.com", product: .openBao)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition() {
            try #require(ContinuousClock.now < deadline, "Controlled dependency was not reached.")
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
