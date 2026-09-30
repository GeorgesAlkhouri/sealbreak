import Foundation
import ComposableArchitecture
import Testing
@testable import SealbreakCore

@MainActor
struct SecurityRegressionTests {
    private let share = String(repeating: "a", count: 64)

    @Test
    func invalidPasteClearsPreviouslyValidShareDraft() throws {
        var draft = ""
        let replacement = String(repeating: "b", count: 64)

        try applySharePaste(share, to: &draft)
        #expect(draft == share)

        #expect(throws: AppFailure.self) {
            try applySharePaste("not-a-share", to: &draft)
        }
        #expect(draft.isEmpty)

        try applySharePaste(replacement, to: &draft)
        #expect(draft == replacement)
    }

    @Test
    func homeFailuresDiscardStaleStatusSoTheNoticeRemainsVisible() async throws {
        let profile = try ServerProfile(id: UUID(), name: "Server", address: "https://bao.example.com")
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
            $0.notice = failure.resource
        }
        #expect(
            HomeViewState(
                profile: unsealStore.state.profile,
                sealStatus: unsealStore.state.status,
                operation: unsealStore.state.operation,
                notice: unsealStore.state.notice
            ).notice == failure.resource
        )

        var removeState = HomeFeature.State(profile: profile, status: status)
        removeState.operation = .removingLocalData
        let removeStore = TestStore(initialState: removeState) {
            HomeFeature()
        }
        await removeStore.send(.removeLocalDataResponse(.failure(failure))) {
            $0.operation = nil
            $0.status = nil
            $0.notice = failure.resource
        }
    }

    @Test
    func replacementRejectsMismatchedStoredTargetBeforeAnyWrite() throws {
        let expected = try ServerProfile(id: UUID(), name: "Expected", address: "https://bao.example.com")
        let foreign = try ServerProfile(id: UUID(), name: "Foreign", address: "https://other.example.com")
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
    func replacementRejectsSameOriginWithDifferentProfileIdentity() throws {
        let expected = try ServerProfile(id: UUID(), name: "Expected", address: "https://bao.example.com")
        let sameOriginDifferentProfile = try ServerProfile(
            id: UUID(),
            name: "Other profile",
            address: "https://bao.example.com"
        )
        let replacement = try ShareRecord(profile: expected, input: share)
        let existing = try ShareRecord(profile: sameOriginDifferentProfile, input: share)
        var replaced = false

        #expect(expected.id != sameOriginDifferentProfile.id)
        #expect(expected.origin == sameOriginDifferentProfile.origin)
        #expect(throws: AppFailure.self) {
            try replaceShareIfBound(
                expectedProfile: expected,
                replacement: replacement,
                readExisting: { existing },
                beforeReplace: {},
                replace: { _ in replaced = true }
            )
        }
        #expect(!replaced)
    }

    @Test
    func replacementRejectsMismatchedReplacementAndWritesOnlyWhenBothBindingsMatch() throws {
        let expected = try ServerProfile(id: UUID(), name: "Expected", address: "https://bao.example.com")
        let foreign = try ServerProfile(id: UUID(), name: "Foreign", address: "https://other.example.com")
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
