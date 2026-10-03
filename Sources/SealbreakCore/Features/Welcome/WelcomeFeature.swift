import ComposableArchitecture
import Foundation

@Reducer
package struct WelcomeFeature {
    package init() {}

    @ObservableState
    package struct State: Equatable {
        package var feedback: AppFeedback?
        package var requiresLocalReset: Bool
        package var confirmReset = false
        package var isResetting = false

        package init(
            feedback: AppFeedback? = nil,
            requiresLocalReset: Bool = false
        ) {
            self.feedback = feedback
            self.requiresLocalReset = requiresLocalReset
        }
    }

    package enum Action: Equatable {
        package enum Delegate: Equatable {
            case setUp
        }

        case setUpTapped
        case resetLocalDataTapped
        case resetConfirmationDismissed
        case confirmResetLocalDataTapped
        case resetResponse(Result<Bool, AppFailure>)
        case delegate(Delegate)
    }

    @Dependency(\.sealbreakClient) private var client

    package var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .setUpTapped:
                guard !state.requiresLocalReset, !state.isResetting else {
                    return .none
                }
                return .send(.delegate(.setUp))

            case .resetLocalDataTapped:
                guard state.requiresLocalReset, !state.isResetting else {
                    return .none
                }
                state.confirmReset = true
                return .none

            case .resetConfirmationDismissed:
                state.confirmReset = false
                return .none

            case .confirmResetLocalDataTapped:
                guard state.requiresLocalReset, !state.isResetting else {
                    return .none
                }
                state.confirmReset = false
                state.isResetting = true
                let client = self.client
                return .run { send in
                    do {
                        try await client.resetLocalData()
                        await send(.resetResponse(.success(true)))
                    } catch {
                        await send(
                            .resetResponse(
                                .failure(normalizedAppFailure(error))
                            )
                        )
                    }
                }

            case .resetResponse(.success):
                state.isResetting = false
                state.requiresLocalReset = false
                state.feedback = .success(LocalizedStringResource("Local Sealbreak data was reset. Set up again using your independent share copy.", bundle: .module))
                return .none

            case .resetResponse(.failure(let failure)):
                state.isResetting = false
                state.feedback = failure.feedback
                return .none

            case .delegate:
                return .none
            }
        }
    }
}
