import ComposableArchitecture
import Foundation

@Reducer
package struct SetupFeature {
    package init() {}
    @ObservableState
    package struct State: Equatable {
        package enum Step: Equatable {
            case instance
            case share
        }

        package var step: Step = .instance
        package var instance = InstanceSetupFeature.State()
        package var share: ShareSetupFeature.State?
        package var feedback: AppFeedback

        package init(
            feedback: AppFeedback = .info("Prototype: use disposable test shares until the security checks in issue #1 have been completed.")
        ) {
            self.feedback = feedback
        }

        package var isBusy: Bool {
            instance.isCheckingConnection || share?.isBusy == true
        }

        package var activity: LocalizedStringResource? {
            if instance.isCheckingConnection {
                return "Checking connection…"
            }
            if let share, share.isBusy {
                return share.activity
            }
            return nil
        }

        package var blocksSetupExit: Bool {
            share?.isBusy == true
        }
    }

    package enum Action: Equatable {
        package enum Delegate: Equatable {
            case cancelled
            case profileReady(ServerProfile, feedback: AppFeedback)
            case localResetRequired(feedback: AppFeedback)
        }

        case instance(InstanceSetupFeature.Action)
        case share(ShareSetupFeature.Action)
        case backTapped
        case cancelTapped
        case privacyInterrupted
        case delegate(Delegate)
    }

    package var body: some ReducerOf<Self> {
        Scope(state: \.instance, action: \.instance) {
            InstanceSetupFeature()
        }

        Reduce { state, action in
            switch action {
            case .instance(.delegate(.continueWithProfile(let profile))):
                state.step = .share
                state.share = ShareSetupFeature.State(
                    profile: profile,
                    feedback: state.feedback
                )
                return .none

            case .share(.delegate(.profileReady(let profile, let feedback))):
                state.feedback = feedback
                return .send(.delegate(.profileReady(profile, feedback: feedback)))

            case .share(.delegate(.localResetRequired(let feedback))):
                state.feedback = feedback
                return .send(.delegate(.localResetRequired(feedback: feedback)))

            case .backTapped:
                guard !state.blocksSetupExit else { return .none }
                state.share = nil
                state.step = .instance
                return .none

            case .cancelTapped:
                guard !state.blocksSetupExit else { return .none }
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
