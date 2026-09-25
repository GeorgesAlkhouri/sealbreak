import ComposableArchitecture
import Foundation

@Reducer
struct ServerDetailsFeature {
    @ObservableState
    struct State: Equatable {
        var profile: ServerProfile
        var status: SealStatus?
        var isBusy: Bool
        var activity: LocalizedStringResource?
        var notice: LocalizedStringResource
    }

    enum Action: Equatable {
        enum Delegate: Equatable {
            case refreshRequested
            case dismissRequested
        }

        case refreshTapped
        case doneTapped
        case delegate(Delegate)
    }

    var body: some ReducerOf<Self> {
        Reduce { _, action in
            switch action {
            case .refreshTapped:
                return .send(.delegate(.refreshRequested))
            case .doneTapped:
                return .send(.delegate(.dismissRequested))
            case .delegate:
                return .none
            }
        }
    }
}
