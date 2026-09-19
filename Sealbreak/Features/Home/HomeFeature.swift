import ComposableArchitecture

@Reducer
struct HomeFeature {
    @ObservableState
    struct State: Equatable {
        enum Operation: Equatable {
            case checkingStatus
            case checkingTarget
            case waitingForFaceID
            case submittingShare
            case verifyingStatus
            case restoringProfile
            case removingLocalData

            var activity: String {
                switch self {
                case .checkingStatus:
                    return "Checking seal status…"
                case .checkingTarget:
                    return "Checking target…"
                case .waitingForFaceID:
                    return "Waiting for Face ID…"
                case .submittingShare:
                    return "Submitting one share…"
                case .verifyingStatus:
                    return "Verifying seal status…"
                case .restoringProfile:
                    return "Restoring local profile…"
                case .removingLocalData:
                    return "Removing local data…"
                }
            }
        }

        enum Confirmation: Equatable {
            case unseal
            case removeLocalData
        }

        var profile: ServerProfile
        var status: SealStatus?
        var operation: Operation?
        var notice: String
        var confirmation: Confirmation?
        @Presents var serverDetails: ServerDetailsFeature.State?
        @Presents var replaceShare: ReplaceShareFeature.State?

        init(
            profile: ServerProfile,
            status: SealStatus? = nil,
            notice: String = "Prototype: use disposable test shares until the security checks in issue #1 have been completed."
        ) {
            self.profile = profile
            self.status = status
            self.notice = notice
        }

        var isBusy: Bool { operation != nil }
        var activity: String { operation?.activity ?? "" }
        var canUnseal: Bool {
            !isBusy && status?.supportsUnseal == true && status?.sealed == true
        }
    }

    struct ProfileResult: Equatable, Sendable {
        let profile: ServerProfile
        let notice: String
    }

    enum Action: Equatable {
        enum Delegate: Equatable {
            case localDataRemoved(notice: String)
        }

        case refreshTapped
        case refreshRequested
        case refreshResponse(Result<SealStatus, AppFailure>)
        case unsealTapped
        case confirmUnsealTapped
        case confirmationDismissed
        case operationActivity(State.Operation)
        case unsealPreflightStatus(SealStatus)
        case unsealAlreadyUnsealed(SealStatus)
        case unsealCompleted(SealStatus)
        case unsealFailed(AppFailure)
        case operationCancelled
        case serverDetailsTapped
        case replaceShareTapped
        case restoreProfileTapped
        case restoreProfileResponse(Result<ProfileResult, AppFailure>)
        case removeLocalDataTapped
        case confirmRemoveLocalDataTapped
        case removeLocalDataResponse(Result<String, AppFailure>)
        case privacyInterrupted
        case serverDetails(PresentationAction<ServerDetailsFeature.Action>)
        case replaceShare(PresentationAction<ReplaceShareFeature.Action>)
        case delegate(Delegate)
    }

    private enum CancelID: Hashable {
        case operation
    }

    @Dependency(\.sealbreakClient) private var client

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .refreshTapped, .refreshRequested:
                guard !state.isBusy else { return .none }
                state.operation = .checkingStatus
                state.status = nil
                synchronizeServerDetails(&state)
                let profile = state.profile
                let client = self.client
                return .run { send in
                    do {
                        try await client.waitForForeground()
                        let status = try await client.status(profile)
                        await send(.refreshResponse(.success(status)))
                    } catch is CancellationError {
                        await send(.operationCancelled)
                    } catch {
                        await send(.refreshResponse(.failure(normalizedAppFailure(error))))
                    }
                }
                .cancellable(id: CancelID.operation)

            case .refreshResponse(.success(let status)):
                state.operation = nil
                state.status = status
                state.notice = status.supportsUnseal
                    ? "Status checked. Nothing is sent automatically."
                    : "Only initialized Shamir seals are supported. Initialization, auto-unseal, and seal migration are not supported."
                synchronizeServerDetails(&state)
                return .none

            case .refreshResponse(.failure(let failure)):
                state.operation = nil
                state.notice = failure.message
                synchronizeServerDetails(&state)
                return .none

            case .unsealTapped:
                guard state.canUnseal else { return .none }
                state.confirmation = .unseal
                return .none

            case .confirmationDismissed:
                state.confirmation = nil
                return .none

            case .confirmUnsealTapped:
                guard state.canUnseal else { return .none }
                state.confirmation = nil
                state.operation = .checkingTarget
                state.status = nil
                synchronizeServerDetails(&state)
                let target = state.profile
                let client = self.client
                return .run { send in
                    var submissionStarted = false
                    do {
                        try await client.waitForForeground()
                        let before = try await client.status(target)
                        await send(.unsealPreflightStatus(before))

                        guard before.supportsUnseal else {
                            throw AppFailure("This target does not support manual Shamir unseal.")
                        }
                        guard before.sealed else {
                            await send(.unsealAlreadyUnsealed(before))
                            return
                        }

                        await send(.operationActivity(.waitingForFaceID))
                        var record = try await client.readShare(
                            "Send one Shamir share to \(target.origin)"
                        )
                        defer { record.share.removeAll(keepingCapacity: false) }
                        guard record.profile == target else {
                            throw AppFailure("Target binding mismatch. Nothing was sent. Restore the protected profile; changing the display file cannot retarget a share.")
                        }

                        try await client.requireForeground()
                        await send(.operationActivity(.submittingShare))
                        submissionStarted = true
                        try await client.submit(record)
                        record.share.removeAll(keepingCapacity: false)

                        await send(.operationActivity(.verifyingStatus))
                        let after = try await client.status(target)
                        guard after.supportsUnseal else {
                            throw AppFailure("Unexpected seal configuration after submission.")
                        }
                        await send(.unsealCompleted(after))
                    } catch is CancellationError {
                        await send(.operationCancelled)
                    } catch {
                        if submissionStarted {
                            let detail = (error as? AppFailure)?.message ?? "Request failed."
                            await send(
                                .unsealFailed(
                                    AppFailure(
                                        "\(detail) The final outcome is unknown. Check status before another attempt; a request already received cannot be undone."
                                    )
                                )
                            )
                        } else {
                            await send(.unsealFailed(normalizedAppFailure(error)))
                        }
                    }
                }
                .cancellable(id: CancelID.operation)

            case .operationActivity(let operation):
                state.operation = operation
                if operation == .submittingShare {
                    state.status = nil
                }
                synchronizeServerDetails(&state)
                return .none

            case .unsealPreflightStatus(let status):
                state.status = status
                synchronizeServerDetails(&state)
                return .none

            case .unsealAlreadyUnsealed(let status):
                state.operation = nil
                state.status = status
                state.notice = "Already unsealed. No share was read or sent."
                synchronizeServerDetails(&state)
                return .none

            case .unsealCompleted(let status):
                state.operation = nil
                state.status = status
                state.notice = status.sealed
                    ? "Submission completed; still sealed. Progress: \(status.progress)/\(status.t). Other holders must submit their own shares to this same node."
                    : "Verified: this endpoint now reports unsealed. This does not prove which operator completed the quorum."
                synchronizeServerDetails(&state)
                return .none

            case .operationCancelled:
                state.operation = nil
                state.status = nil
                state.notice = "Operation cancelled. Refresh status before retrying; a submitted request may already have been processed."
                synchronizeServerDetails(&state)
                return .none

            case .serverDetailsTapped:
                state.serverDetails = ServerDetailsFeature.State(
                    profile: state.profile,
                    status: state.status,
                    isBusy: state.isBusy,
                    activity: state.activity,
                    notice: state.notice
                )
                return .none

            case .replaceShareTapped:
                guard !state.isBusy else { return .none }
                state.replaceShare = ReplaceShareFeature.State(profile: state.profile)
                return .none

            case .restoreProfileTapped:
                guard !state.isBusy else { return .none }
                state.operation = .restoringProfile
                synchronizeServerDetails(&state)
                let client = self.client
                return .run { send in
                    do {
                        try await client.waitForForeground()
                        var record = try await client.readShare(
                            "Restore the server profile from the protected Keychain record"
                        )
                        defer { record.share.removeAll(keepingCapacity: false) }
                        let profile = record.profile
                        let notice: String
                        do {
                            try await client.saveProfile(profile)
                            notice = "Protected target restored. No share was transmitted or exported."
                        } catch {
                            notice = "Protected share exists, but display metadata could not be saved. Use Restore profile from Keychain on the next launch."
                        }
                        await send(
                            .restoreProfileResponse(
                                .success(ProfileResult(profile: profile, notice: notice))
                            )
                        )
                    } catch is CancellationError {
                        await send(.operationCancelled)
                    } catch {
                        await send(.restoreProfileResponse(.failure(normalizedAppFailure(error))))
                    }
                }
                .cancellable(id: CancelID.operation)

            case .restoreProfileResponse(.success(let result)):
                state.operation = nil
                state.profile = result.profile
                state.status = nil
                state.notice = result.notice
                synchronizeServerDetails(&state)
                return .none

            case .removeLocalDataTapped:
                guard !state.isBusy else { return .none }
                state.confirmation = .removeLocalData
                return .none

            case .confirmRemoveLocalDataTapped:
                guard !state.isBusy else { return .none }
                state.confirmation = nil
                state.operation = .removingLocalData
                synchronizeServerDetails(&state)
                let client = self.client
                return .run { send in
                    do {
                        try await client.waitForForeground()
                        try await client.deleteShare(
                            "Permanently remove Sealbreak’s local share; independent recovery will be required"
                        )
                        let notice: String
                        do {
                            try await client.deleteProfile()
                            notice = "Local share removed. Copies elsewhere remain valid; only server-side rekeying replaces the server’s Shamir shares."
                        } catch {
                            notice = "The Keychain share was removed, but its non-secret display file could not be removed. Restart may show stale metadata."
                        }
                        await send(.removeLocalDataResponse(.success(notice)))
                    } catch is CancellationError {
                        await send(.operationCancelled)
                    } catch {
                        await send(.removeLocalDataResponse(.failure(normalizedAppFailure(error))))
                    }
                }
                .cancellable(id: CancelID.operation)

            case .removeLocalDataResponse(.success(let notice)):
                state.operation = nil
                state.status = nil
                state.notice = notice
                state.serverDetails = nil
                state.replaceShare = nil
                return .send(.delegate(.localDataRemoved(notice: notice)))

            case .unsealFailed(let failure),
                 .restoreProfileResponse(.failure(let failure)),
                 .removeLocalDataResponse(.failure(let failure)):
                state.operation = nil
                state.status = nil
                state.notice = failure.message
                synchronizeServerDetails(&state)
                return .none

            case .privacyInterrupted:
                let wasBusy = state.isBusy
                state.operation = nil
                state.status = nil
                state.confirmation = nil
                state.replaceShare = nil
                state.serverDetails = nil
                if wasBusy {
                    state.notice = "Operation interrupted. Check status on return; an already submitted request cannot be recalled."
                }
                let client = self.client
                return .merge(
                    .cancel(id: CancelID.operation),
                    .run { _ in await client.cancelSensitiveOperation() }
                )

            case .serverDetails(.presented(.delegate(.refreshRequested))):
                return .send(.refreshRequested)

            case .serverDetails(.presented(.delegate(.dismissRequested))):
                state.serverDetails = nil
                return .none

            case .replaceShare(.presented(.delegate(.saved(let notice)))):
                state.replaceShare = nil
                state.status = nil
                state.notice = notice
                synchronizeServerDetails(&state)
                return .none

            case .replaceShare(.presented(.delegate(.dismissRequested))):
                state.replaceShare = nil
                return .none

            case .serverDetails, .replaceShare, .delegate:
                return .none
            }
        }
        .ifLet(\.$serverDetails, action: \.serverDetails) {
            ServerDetailsFeature()
        }
        .ifLet(\.$replaceShare, action: \.replaceShare) {
            ReplaceShareFeature()
        }
    }

    private func synchronizeServerDetails(_ state: inout State) {
        guard state.serverDetails != nil else { return }

        let profile = state.profile
        let status = state.status
        let isBusy = state.isBusy
        let activity = state.activity
        let notice = state.notice

        state.serverDetails = ServerDetailsFeature.State(
            profile: profile,
            status: status,
            isBusy: isBusy,
            activity: activity,
            notice: notice
        )
    }
}
