import ComposableArchitecture

@Reducer
struct AppFeature {
    @ObservableState
    struct State: Equatable {
        var privacy = PrivacyFeature.State()
        var welcome: WelcomeFeature.State?
        var home: HomeFeature.State?
        var setup: SetupFeature.State?
        var isLoading = true
        var didLoad = false
    }

    enum Action: Equatable {
        case task
        case profilesLoaded(Result<[ServerProfile], AppFailure>)
        case privacy(PrivacyFeature.Action)
        case welcome(WelcomeFeature.Action)
        case home(HomeFeature.Action)
        case setup(SetupFeature.Action)
    }

    @Dependency(\.sealbreakClient) private var client

    var body: some ReducerOf<Self> {
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
                        let profiles = try await client.loadProfiles()
                        await send(.profilesLoaded(.success(profiles)))
                    } catch {
                        await send(.profilesLoaded(.failure(normalizedAppFailure(error))))
                    }
                }

            case .profilesLoaded(.success(let profiles)):
                state.isLoading = false
                guard profiles.count <= 1 else {
                    state.home = nil
                    state.setup = nil
                    state.welcome = WelcomeFeature.State(
                        notice: "This Sealbreak version supports one configured server profile."
                    )
                    return .none
                }
                if let profile = profiles.first {
                    state.welcome = nil
                    state.setup = nil
                    state.home = HomeFeature.State(profile: profile)
                    return .send(.home(.refreshRequested))
                }
                state.home = nil
                state.setup = nil
                state.welcome = WelcomeFeature.State()
                return .none

            case .profilesLoaded(.failure):
                state.isLoading = false
                state.home = nil
                state.setup = nil
                state.welcome = WelcomeFeature.State(
                    notice: "The display profile could not be read. Set up Sealbreak again using your independent share copy."
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

            case .home(.delegate(.localDataRemoved(let notice))):
                state.home = nil
                state.setup = nil
                state.welcome = WelcomeFeature.State(notice: notice)
                return .none

            case .welcome(.delegate(.setUp)):
                state.welcome = nil
                state.setup = SetupFeature.State()
                return .none

            case .setup(.delegate(.cancelled)):
                state.home = nil
                state.setup = nil
                state.welcome = WelcomeFeature.State()
                return .none

            case .setup(.delegate(.profileReady(let profile, let notice))):
                state.welcome = nil
                state.setup = nil
                state.home = HomeFeature.State(profile: profile, notice: notice)
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
