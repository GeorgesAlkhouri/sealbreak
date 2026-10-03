import ComposableArchitecture
import Foundation

@Reducer
package struct ServerDetailsFeature {
    @ObservableState
    package struct State: Equatable {
        package var profile: ServerProfile
        package var status: SealStatus?
        package var isBusy: Bool
        var activity: LocalizedStringResource?
        package var shareFragment: ShareComparisonFragment? = nil
        package var isRevealingShare = false
    }

    package enum Action: Equatable {
        package enum Delegate: Equatable {
            case refreshRequested
            case dismissRequested
        }

        case refreshTapped
        case doneTapped
        case shareFragmentTapped
        case shareFragmentLoaded(ShareComparisonFragment)
        case shareFragmentLoadFailed
        case shareFragmentExpired
        case delegate(Delegate)
    }

    private enum CancelID: Hashable {
        case shareFragmentExpiry
    }

    @Dependency(\.continuousClock) private var clock
    @Dependency(\.sealbreakClient) private var client

    package var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .refreshTapped:
                return .send(.delegate(.refreshRequested))

            case .doneTapped:
                return .send(.delegate(.dismissRequested))

            case .shareFragmentTapped:
                if state.shareFragment != nil {
                    state.shareFragment = nil
                    return .cancel(id: CancelID.shareFragmentExpiry)
                }

                guard !state.isBusy, !state.isRevealingShare else {
                    return .none
                }

                state.isRevealingShare = true
                let profileID = state.profile.id
                let client = self.client
                return .run { send in
                    do {
                        let fragment = try await client.readShareFragment(
                            profileID,
                            LocalizedStringResource("Show stored share fragment", bundle: .module)
                        )
                        await send(.shareFragmentLoaded(fragment))
                    } catch {
                        await send(.shareFragmentLoadFailed)
                    }
                }

            case .shareFragmentLoaded(let fragment):
                state.isRevealingShare = false
                state.shareFragment = fragment
                let clock = self.clock
                return .run { send in
                    try await clock.sleep(for: .seconds(20))
                    await send(.shareFragmentExpired)
                }
                .cancellable(id: CancelID.shareFragmentExpiry, cancelInFlight: true)

            case .shareFragmentLoadFailed:
                state.isRevealingShare = false
                return .none

            case .shareFragmentExpired:
                state.shareFragment = nil
                return .none

            case .delegate:
                return .none
            }
        }
    }
}
