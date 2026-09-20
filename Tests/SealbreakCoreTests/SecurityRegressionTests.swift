import ComposableArchitecture
import Testing
@testable import SealbreakCore

@MainActor
struct SecurityRegressionTests {
    private let share = String(repeating: "a", count: 64)

    @Test
    func homeFailuresDiscardStaleStatusSoTheNoticeRemainsVisible() async throws {
        let profile = try ServerProfile(name: "Server", address: "https://bao.example.com")
        let status = SealStatus(
            type: "shamir",
            initialized: true,
            sealed: true,
            t: 3,
            n: 5,
            progress: 1,
            migration: false,
            recoverySeal: false
        )
        let failure = AppFailure("Protected share could not be read.")

        var unsealState = HomeFeature.State(profile: profile, status: status)
        unsealState.operation = .waitingForFaceID
        let unsealStore = TestStore(initialState: unsealState) {
            HomeFeature()
        }
        await unsealStore.send(.unsealFailed(failure)) {
            $0.operation = nil
            $0.status = nil
            $0.notice = failure.message
        }
        #expect(
            HomeViewState(
                profile: unsealStore.state.profile,
                sealStatus: unsealStore.state.status,
                operation: unsealStore.state.operation,
                notice: unsealStore.state.notice
            ).notice == failure.message
        )

        var removeState = HomeFeature.State(profile: profile, status: status)
        removeState.operation = .removingLocalData
        let removeStore = TestStore(initialState: removeState) {
            HomeFeature()
        }
        await removeStore.send(.removeLocalDataResponse(.failure(failure))) {
            $0.operation = nil
            $0.status = nil
            $0.notice = failure.message
        }
    }

    @Test
    func replacementRejectsMismatchedStoredTargetBeforeAnyWrite() throws {
        let expected = try ServerProfile(name: "Expected", address: "https://bao.example.com")
        let foreign = try ServerProfile(name: "Foreign", address: "https://other.example.com")
        let replacement = try ShareRecord(profile: expected, input: share)
        let existing = try ShareRecord(profile: foreign, input: share)
        var checkedForeground = false
        var replaced = false

        #expect(throws: AppFailure.self) {
            try replaceShareIfBound(
                expectedProfile: expected,
                replacement: replacement,
                readExisting: { existing },
                beforeReplace: { checkedForeground = true },
                replace: { _ in replaced = true }
            )
        }

        #expect(!checkedForeground)
        #expect(!replaced)
    }

    @Test
    func replacementRejectsMismatchedReplacementAndWritesOnlyWhenBothBindingsMatch() throws {
        let expected = try ServerProfile(name: "Expected", address: "https://bao.example.com")
        let foreign = try ServerProfile(name: "Foreign", address: "https://other.example.com")
        let existing = try ShareRecord(profile: expected, input: share)
        let foreignReplacement = try ShareRecord(profile: foreign, input: share)
        var replaced = false

        #expect(throws: AppFailure.self) {
            try replaceShareIfBound(
                expectedProfile: expected,
                replacement: foreignReplacement,
                readExisting: { existing },
                beforeReplace: {},
                replace: { _ in replaced = true }
            )
        }
        #expect(!replaced)

        let validReplacement = try ShareRecord(profile: expected, input: share)
        var checkedForeground = false
        try replaceShareIfBound(
            expectedProfile: expected,
            replacement: validReplacement,
            readExisting: { existing },
            beforeReplace: { checkedForeground = true },
            replace: { _ in replaced = true }
        )

        #expect(checkedForeground)
        #expect(replaced)
    }
}
