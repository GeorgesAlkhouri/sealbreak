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
        var verification: ShareVerification? = nil
        var verificationError: LocalizedStringResource? = nil
        var isSavingVerification = false
    }

    enum Action: Equatable {
        enum Delegate: Equatable {
            case refreshRequested
            case dismissRequested
            case verificationChanged(ShareVerification?)
        }

        case refreshTapped
        case doneTapped
        case verificationTapped
        case verificationSaved(Result<ShareVerification?, AppFailure>)
        case delegate(Delegate)
    }

    @Dependency(\.sealbreakClient) private var client

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .refreshTapped:
                return .send(.delegate(.refreshRequested))
            case .doneTapped:
                return .send(.delegate(.dismissRequested))
            case .verificationTapped:
                guard !state.isBusy, !state.isSavingVerification else { return .none }
                state.isSavingVerification = true
                state.verificationError = nil
                let newValue: ShareVerification? = state.verification == nil
                    ? ShareVerification(source: .manual, at: Date())
                    : nil
                let profileID = state.profile.id
                let client = self.client
                return .run { send in
                    do {
                        try await client.setVerification(profileID, newValue)
                        await send(.verificationSaved(.success(newValue)))
                    } catch {
                        await send(.verificationSaved(.failure(normalizedAppFailure(error))))
                    }
                }
            case .verificationSaved(.success(let verification)):
                state.isSavingVerification = false
                state.verification = verification
                return .send(.delegate(.verificationChanged(verification)))
            case .verificationSaved(.failure(let failure)):
                state.isSavingVerification = false
                state.verificationError = failure.resource
                return .none
            case .delegate:
                return .none
            }
        }
    }
}
