import ComposableArchitecture

@Reducer
package struct PrivacyFeature {
    package init() {}
    @ObservableState
    package struct State: Equatable {
        package enum Phase: Equatable {
            case active
            case inactive
            case background
        }

        package var phase: Phase = .inactive
        package var isCaptured = false

        package var isConcealed: Bool {
            phase != .active || isCaptured
        }
    }

    package enum Action: Equatable {
        package enum Delegate: Equatable {
            case becameActive
            case interrupted
        }

        case phaseChanged(State.Phase)
        case captureChanged(Bool)
        case delegate(Delegate)
    }

    package var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .phaseChanged(let phase):
                let previous = state.phase
                state.phase = phase

                if phase == .background, previous != .background {
                    return .send(.delegate(.interrupted))
                }
                if phase == .active, previous != .active {
                    return .send(.delegate(.becameActive))
                }
                return .none

            case .captureChanged(let captured):
                let wasCaptured = state.isCaptured
                state.isCaptured = captured
                if captured, !wasCaptured {
                    return .send(.delegate(.interrupted))
                }
                return .none

            case .delegate:
                return .none
            }
        }
    }
}
