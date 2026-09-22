import ComposableArchitecture

@Reducer
struct SetupFeature {
    @ObservableState
    struct State: Equatable {
        enum Step: Equatable {
            case instance
            case share
        }

        enum Operation: Equatable {
            case removingLocalData

            var activity: String {
                "Removing local data…"
            }
        }

        var step: Step = .instance
        var instance = InstanceSetupFeature.State()
        var share: ShareSetupFeature.State?
        var operation: Operation?
        var notice: String
        var confirmDelete = false

        init(
            notice: String = "Prototype: use disposable test shares until the security checks in issue #1 have been completed."
        ) {
            self.notice = notice
        }

        var isBusy: Bool {
            instance.isCheckingConnection || share?.isBusy == true || operation != nil
        }

        var activity: String {
            if instance.isCheckingConnection {
                return "Checking connection…"
            }
            if let share, share.isBusy {
                return share.activity
            }
            return operation?.activity ?? ""
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
        case removeLocalDataTapped
        case confirmRemoveLocalDataTapped
        case confirmationDismissed
        case removeResponse(Result<String, AppFailure>)
        case operationCancelled
        case privacyInterrupted
        case delegate(Delegate)
    }

    private enum CancelID: Hashable {
        case operation
    }

    @Dependency(\.sealbreakClient) private var client

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
                state.operation = nil
                state.confirmDelete = false
                state.share = nil
                let client = self.client
                return .merge(
                    .cancel(id: CancelID.operation),
                    .run { _ in await client.cancelSensitiveOperation() },
                    .send(.delegate(.cancelled))
                )

            case .removeLocalDataTapped:
                guard !state.isBusy else { return .none }
                state.confirmDelete = true
                return .none

            case .confirmationDismissed:
                state.confirmDelete = false
                return .none

            case .confirmRemoveLocalDataTapped:
                guard !state.isBusy else { return .none }
                guard let profileID = state.share?.profile.id else {
                    state.confirmDelete = false
                    state.notice = "No protected share is associated with this setup."
                    return .none
                }
                state.confirmDelete = false
                state.operation = .removingLocalData
                let client = self.client
                return .run { send in
                    do {
                        try await client.waitForForeground()
                        try await client.deleteShare(
                            profileID,
                            "Permanently remove Sealbreak’s local share; independent recovery will be required"
                        )
                        let notice: String
                        do {
                            try await client.deleteProfile(profileID)
                            notice = "Local share removed. Copies elsewhere remain valid; only server-side rekeying replaces the server’s Shamir shares."
                        } catch {
                            notice = "The Keychain share was removed, but its non-secret display file could not be removed. Restart may show stale metadata."
                        }
                        await send(.removeResponse(.success(notice)))
                    } catch is CancellationError {
                        await send(.operationCancelled)
                    } catch {
                        await send(.removeResponse(.failure(normalizedAppFailure(error))))
                    }
                }
                .cancellable(id: CancelID.operation)

            case .removeResponse(.success(let notice)):
                state.operation = nil
                state.notice = notice
                return .none

            case .removeResponse(.failure(let failure)):
                state.operation = nil
                state.notice = failure.message
                return .none

            case .operationCancelled:
                state.operation = nil
                state.notice = "Operation cancelled. Refresh status before retrying; a submitted request may already have been processed."
                return .none

            case .privacyInterrupted:
                if state.step == .share, state.share != nil {
                    return .send(.share(.privacyInterrupted))
                }

                if state.instance.isCheckingConnection {
                    return .send(.instance(.privacyInterrupted))
                }

                let wasBusy = state.operation != nil
                state.operation = nil
                state.confirmDelete = false
                if wasBusy {
                    state.notice = "Operation interrupted. Check status on return; an already submitted request cannot be recalled."
                }

                let client = self.client
                return .merge(
                    .cancel(id: CancelID.operation),
                    .run { _ in await client.cancelSensitiveOperation() }
                )

            case .instance, .share, .delegate:
                return .none
            }
        }
        .ifLet(\.share, action: \.share) {
            ShareSetupFeature()
        }
    }
}
