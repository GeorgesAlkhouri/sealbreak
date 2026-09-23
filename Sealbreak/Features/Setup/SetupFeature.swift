import ComposableArchitecture

@Reducer
struct SetupFeature {
    @ObservableState
    struct State: Equatable {
        enum Step: Equatable {
            case instance
            case share
        }

        var step: Step = .instance
        var instance = InstanceSetupFeature.State()
        var share: ShareSetupFeature.State?
        var notice: String

        init(
            notice: String = "Prototype: use disposable test shares until the security checks in issue #1 have been completed."
        ) {
            self.notice = notice
        }

        var isBusy: Bool {
            instance.isCheckingConnection || share?.isBusy == true
        }

        var activity: String {
            if instance.isCheckingConnection {
                return "Checking connection…"
            }
            if let share, share.isBusy {
                return share.activity
            }
            return ""
        }
    }

    enum Action: Equatable {
        enum Delegate: Equatable {
            case cancelled
            case profileReady(ServerProfile, notice: String)
            case localResetRequired(notice: String)
        }

        case instance(InstanceSetupFeature.Action)
        case share(ShareSetupFeature.Action)
        case backTapped
        case cancelTapped
        case privacyInterrupted
        case delegate(Delegate)
    }

    var body: some ReducerOf<Self> {
        Scope(state: \.instance, action: \.instance) {
            InstanceSetupFeature()
        }

        Reduce { state, action in
            switch action {
            case .instance(.delegate(.continueWithProfile(let profile))):
                state.step = .share
                state.share = ShareSetupFeature.State(
                    profile: profile,
                    notice: state.notice
                )
                return .none

            case .share(.delegate(.profileReady(let profile, let notice))):
                state.notice = notice
                return .send(.delegate(.profileReady(profile, notice: notice)))

            case .share(.delegate(.localResetRequired(let notice))):
                state.notice = notice
                return .send(.delegate(.localResetRequired(notice: notice)))

            case .backTapped:
                guard state.share?.isBusy != true else { return .none }
                state.share = nil
                state.step = .instance
                return .none

            case .cancelTapped:
                guard state.share?.isBusy != true else { return .none }
                state.share = nil
                return .send(.delegate(.cancelled))

            case .privacyInterrupted:
                if state.share != nil {
                    return .send(.share(.privacyInterrupted))
                }
                if state.instance.isCheckingConnection {
                    return .send(.instance(.privacyInterrupted))
                }
                return .none

            case .instance, .share, .delegate:
                return .none
            }
        }
        .ifLet(\.share, action: \.share) {
            ShareSetupFeature()
        }
    }
}
