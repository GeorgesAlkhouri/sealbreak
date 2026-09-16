import ComposableArchitecture

@Reducer
struct AppFeature {
    @ObservableState
    struct State: Equatable {
        var privacy = PrivacyFeature.State()
        var home: HomeFeature.State?
        var setup: SetupFeature.State?
        var isLoading = true
        var didLoad = false
    }

    enum Action: Equatable {
        case task
        case profileLoaded(Result<ServerProfile?, AppFailure>)
        case privacy(PrivacyFeature.Action)
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
                        let profile = try await client.loadProfile()
                        await send(.profileLoaded(.success(profile)))
                    } catch {
                        await send(.profileLoaded(.failure(normalizedAppFailure(error))))
                    }
                }

            case .profileLoaded(.success(let profile)):
                state.isLoading = false
                if let profile {
                    state.setup = nil
                    state.home = HomeFeature.State(profile: profile)
                    return .send(.home(.refreshRequested))
                }
                state.home = nil
                state.setup = SetupFeature.State()
                return .none

            case .profileLoaded(.failure):
                state.isLoading = false
                state.home = nil
                state.setup = SetupFeature.State(
                    notice: "The display profile could not be read. Restore its protected copy from Keychain."
                )
                return .none

            case .privacy(.delegate(.interrupted)):
                if state.home != nil {
                    return .send(.home(.privacyInterrupted))
                }
                if state.setup != nil {
                    return .send(.setup(.privacyInterrupted))
                }
                return .run { _ in
                    await client.cancelSensitiveOperation()
                }

            case .privacy(.delegate(.becameActive)):
                guard state.home?.isBusy == false else { return .none }
                return state.home == nil ? .none : .send(.home(.refreshRequested))

            case .home(.delegate(.localDataRemoved(let notice))):
                state.home = nil
                state.setup = SetupFeature.State(notice: notice)
                return .none

            case .setup(.delegate(.profileReady(let profile, let notice))):
                state.setup = nil
                state.home = HomeFeature.State(profile: profile, notice: notice)
                return .send(.home(.refreshRequested))

            case .privacy, .home, .setup:
                return .none
            }
        }
        .ifLet(\.home, action: \.home) {
            HomeFeature()
        }
        .ifLet(\.setup, action: \.setup) {
            SetupFeature()
        }
    }
}
