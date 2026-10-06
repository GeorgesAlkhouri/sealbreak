import ComposableArchitecture
import Foundation

@Reducer
package struct ReplaceShareFeature {
    @ObservableState
    package struct State: Equatable {
        var profile: ServerProfile
        package var isBusy = false
        package var activity: LocalizedStringResource?
        package var feedback: AppFeedback?
    }

    package enum Action: Equatable {
        package enum Delegate: Equatable {
            case saved
            case dismissRequested
        }

        case saveTapped(share: String)
        case pasteFailed(AppFailure)
        case saveSucceeded
        case saveFailed(AppFailure)
        case operationCancelled
        case cancelTapped
        case privacyInterrupted
        case delegate(Delegate)
    }

    private enum CancelID: Hashable {
        case operation
    }

    @Dependency(\.sealbreakClient) private var client

    package var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .saveTapped(let input):
                guard !state.isBusy else { return .none }

                let replacement: ShareRecord
                do {
                    replacement = try ShareRecord(profile: state.profile, input: input)
                } catch {
                    state.feedback = normalizedAppFailure(error).feedback
                    return .none
                }

                state.isBusy = true
                state.activity = LocalizedStringResource("Waiting for Face ID…", bundle: .module)
                let profile = state.profile
                let client = self.client
                return .run { send in
                    var replacement = replacement
                    defer { replacement.share.removeAll(keepingCapacity: false) }
                    do {
                        try await client.waitForForeground()
                        try await client.replaceShare(
                            profile,
                            replacement,
                            LocalizedStringResource("Replace the local share for \(profile.origin)", bundle: .module)
                        )
                        await send(.saveSucceeded)
                    } catch is CancellationError {
                        await send(.operationCancelled)
                    } catch {
                        await send(.saveFailed(normalizedAppFailure(error)))
                    }
                }
                .cancellable(id: CancelID.operation)

            case .pasteFailed(let failure):
                guard !state.isBusy else { return .none }
                state.feedback = failure.feedback
                return .none

            case .saveSucceeded:
                state.isBusy = false
                state.activity = nil
                state.feedback = nil
                return .send(.delegate(.saved))

            case .saveFailed(let failure):
                state.isBusy = false
                state.activity = nil
                state.feedback = failure.feedback
                return .none

            case .operationCancelled:
                state.isBusy = false
                state.activity = nil
                state.feedback = .warning(LocalizedStringResource("Operation cancelled. Refresh status before retrying; a submitted request may already have been processed.", bundle: .module))
                return .none

            case .cancelTapped:
                guard !state.isBusy else { return .none }
                return .send(.delegate(.dismissRequested))

            case .privacyInterrupted:
                let wasBusy = state.isBusy
                state.isBusy = false
                state.activity = nil
                if wasBusy {
                    state.feedback = .warning(LocalizedStringResource("Operation interrupted. Check status on return; an already submitted request cannot be recalled.", bundle: .module))
                }
                let client = self.client
                return .merge(
                    .cancel(id: CancelID.operation),
                    .run { _ in await client.cancelSensitiveOperation() }
                )

            case .delegate:
                return .none
            }
        }
    }
}
