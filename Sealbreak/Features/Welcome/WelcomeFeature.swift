import ComposableArchitecture

@Reducer
struct WelcomeFeature {
    @ObservableState
    struct State: Equatable {
        var notice: String?

        init(notice: String? = nil) {
            self.notice = notice
        }
    }

    enum Action: Equatable {
        enum Delegate: Equatable {
            case setUp
        }

        case setUpTapped
        case delegate(Delegate)
    }

    var body: some ReducerOf<Self> {
        Reduce { _, action in
            switch action {
            case .setUpTapped:
                return .send(.delegate(.setUp))

            case .delegate:
                return .none
            }
        }
    }
}
