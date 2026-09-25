import ComposableArchitecture
import Foundation

@Reducer
struct WelcomeFeature {
    @ObservableState
    struct State: Equatable {
        var notice: LocalizedStringResource?
        var requiresLocalReset: Bool
        var confirmReset = false
        var isResetting = false

        init(
            notice: LocalizedStringResource? = nil,
            requiresLocalReset: Bool = false
        ) {
            self.notice = notice
            self.requiresLocalReset = requiresLocalReset
        }
    }

    enum Action: Equatable {
        enum Delegate: Equatable {
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

    var body: some ReducerOf<Self> {
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
                state.notice = "Local Sealbreak data was reset. Set up again using your independent share copy."
                return .none

            case .resetResponse(.failure(let failure)):
                state.isResetting = false
                state.notice = failure.resource
                return .none

            case .delegate:
                return .none
            }
        }
    }
}
