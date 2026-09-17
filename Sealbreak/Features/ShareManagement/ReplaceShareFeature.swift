import ComposableArchitecture

@Reducer
struct ReplaceShareFeature {
    @ObservableState
    struct State: Equatable {
        var profile: ServerProfile
        var isBusy = false
        var activity = ""
        var notice = ""
    }

    enum Action: Equatable {
        enum Delegate: Equatable {
            case saved(notice: String)
            case dismissRequested
        }

        case saveTapped(share: String, recoveryConfirmed: Bool)
        case saveResponse(Result<String, AppFailure>)
        case operationCancelled
        case cancelTapped
        case privacyInterrupted
        case delegate(Delegate)
    }

    private enum CancelID: Hashable {
        case operation
    }

    @Dependency(\.sealbreakClient) private var client

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .saveTapped(let input, let recoveryConfirmed):
                guard !state.isBusy else { return .none }
                guard recoveryConfirmed else {
                    state.notice = "Confirm recovery for the replacement share before saving."
                    return .none
                }

                let replacement: ShareRecord
                do {
                    replacement = try ShareRecord(profile: state.profile, input: input)
                } catch {
                    state.notice = normalizedAppFailure(error).message
                    return .none
                }

                state.isBusy = true
                state.activity = "Waiting for Face ID…"
                let profile = state.profile
                let client = self.client
                return .run { send in
                    var replacement = replacement
                    defer { replacement.share.removeAll(keepingCapacity: false) }
                    do {
                        try await client.waitForForeground()
                        try await client.replaceShare(
                            profile,
                            replacement,
                            "Replace the local share for \(profile.origin)"
                        )
                        await send(
                            .saveResponse(
                                .success(
                                    "Local share replaced. This does not rotate OpenBao keys; server-side rekeying is a separate operation."
                                )
                            )
                        )
                    } catch is CancellationError {
                        await send(.operationCancelled)
                    } catch {
                        await send(.saveResponse(.failure(normalizedAppFailure(error))))
                    }
                }
                .cancellable(id: CancelID.operation)

            case .saveResponse(.success(let notice)):
                state.isBusy = false
                state.activity = ""
                state.notice = notice
                return .send(.delegate(.saved(notice: notice)))

            case .saveResponse(.failure(let failure)):
                state.isBusy = false
                state.activity = ""
                state.notice = failure.message
                return .none

            case .operationCancelled:
                state.isBusy = false
                state.activity = ""
                state.notice = "Operation cancelled. Refresh status before retrying; a submitted request may already have been processed."
                return .none

            case .cancelTapped:
                guard !state.isBusy else { return .none }
                return .send(.delegate(.dismissRequested))

            case .privacyInterrupted:
                let wasBusy = state.isBusy
                state.isBusy = false
                state.activity = ""
                if wasBusy {
                    state.notice = "Operation interrupted. Check status on return; an already submitted request cannot be recalled."
                }
                let client = self.client
                return .merge(
                    .cancel(id: CancelID.operation),
                    .run { _ in await client.cancelSensitiveOperation() }
                )

            case .delegate:
                return .none
            }
        }
    }
}
