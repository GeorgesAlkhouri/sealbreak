import ComposableArchitecture

@Reducer
package struct AppFeature {
    package init() {}
    @ObservableState
    package struct State: Equatable {
        package var privacy = PrivacyFeature.State()
        package var welcome: WelcomeFeature.State?
        package var home: HomeFeature.State?
        package var setup: SetupFeature.State?
        package var isLoading = true
        package var didLoad = false

        package init() {}
    }

    package enum Action: Equatable {
        case task
        case localSetupStateLoaded(Result<LocalSetupState, AppFailure>)
        case privacy(PrivacyFeature.Action)
        case welcome(WelcomeFeature.Action)
        case home(HomeFeature.Action)
        case setup(SetupFeature.Action)
    }

    @Dependency(\.sealbreakClient) private var client

    package var body: some ReducerOf<Self> {
        Scope(state: \.privacy, action: \.privacy) {
            PrivacyFeature()
        }

        Reduce { state, action in
            switch action {
            case .task:
                guard !state.didLoad else { return .none }
                state.didLoad = true
                state.isLoading = true
                return .run { send in
                    do {
                        let localSetupState = try await client.loadLocalSetupState()
                        await send(.localSetupStateLoaded(.success(localSetupState)))
                    } catch {
                        await send(
                            .localSetupStateLoaded(
                                .failure(normalizedAppFailure(error))
                            )
                        )
                    }
                }

            case .localSetupStateLoaded(.success(.empty)):
                state.isLoading = false
                state.home = nil
                state.setup = nil
                state.welcome = WelcomeFeature.State()
                return .none

            case .localSetupStateLoaded(.success(.ready(let profile))):
                state.isLoading = false
                state.welcome = nil
                state.setup = nil
                state.home = HomeFeature.State(profile: profile)
                return .send(.home(.refreshRequested))

            case .localSetupStateLoaded(.success(.recoveryRequired(let notice))):
                state.isLoading = false
                state.home = nil
                state.setup = nil
                state.welcome = WelcomeFeature.State(
                    feedback: .warning(notice),
                    requiresLocalReset: true
                )
                return .none

            case .localSetupStateLoaded(.failure):
                state.isLoading = false
                state.home = nil
                state.setup = nil
                state.welcome = WelcomeFeature.State(
                    feedback: .warning(
                        "Local Sealbreak configuration could not be read. Reset local data to continue, then set up again using your independent share copy."
                    ),
                    requiresLocalReset: true
                )
                return .none

            case .privacy(.delegate(.interrupted)):
                if state.home != nil {
                    return .send(.home(.privacyInterrupted))
                }
                if state.setup != nil {
                    return .send(.setup(.privacyInterrupted))
                }
                if state.welcome != nil {
                    return .none
                }
                return .run { _ in
                    await client.cancelSensitiveOperation()
                }

            case .privacy(.delegate(.becameActive)):
                guard state.home?.isBusy == false else { return .none }
                return state.home == nil ? .none : .send(.home(.refreshRequested))

            case .home(.delegate(.localDataRemoved(let feedback, let requiresLocalReset))):
                state.home = nil
                state.setup = nil
                state.welcome = WelcomeFeature.State(
                    feedback: feedback,
                    requiresLocalReset: requiresLocalReset
                )
                return .none

            case .welcome(.delegate(.setUp)):
                guard state.welcome?.requiresLocalReset != true else {
                    return .none
                }
                state.welcome = nil
                state.setup = SetupFeature.State()
                return .none

            case .setup(.delegate(.cancelled)):
                state.home = nil
                state.setup = nil
                state.welcome = WelcomeFeature.State()
                return .none

            case .setup(.delegate(.localResetRequired(let feedback))):
                state.home = nil
                state.setup = nil
                state.welcome = WelcomeFeature.State(
                    feedback: feedback,
                    requiresLocalReset: true
                )
                return .none

            case .setup(.delegate(.profileReady(let profile, let feedback))):
                state.welcome = nil
                state.setup = nil
                state.home = HomeFeature.State(profile: profile, feedback: feedback)
                return .send(.home(.refreshRequested))

            case .privacy, .welcome, .home, .setup:
                return .none
            }
        }
        .ifLet(\.welcome, action: \.welcome) {
            WelcomeFeature()
        }
        .ifLet(\.home, action: \.home) {
            HomeFeature()
        }
        .ifLet(\.setup, action: \.setup) {
            SetupFeature()
        }
    }
}
