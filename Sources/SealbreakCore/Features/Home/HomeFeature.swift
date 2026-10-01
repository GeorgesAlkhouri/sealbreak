import ComposableArchitecture
import Foundation

@Reducer
package struct HomeFeature {
    package init() {}

    @ObservableState
    package struct State: Equatable {
        package enum Operation: Equatable {
            case checkingStatus
            case checkingTarget
            case waitingForFaceID
            case submittingShare
            case verifyingStatus
            case removingLocalData

            var activity: LocalizedStringResource {
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
                case .removingLocalData:
                    return "Removing local data…"
                }
            }
        }

        package enum Confirmation: Equatable {
            case unseal
            case removeLocalData
        }

        package var profile: ServerProfile
        package var status: SealStatus?
        package var operation: Operation?
        package var feedback: AppFeedback
        package var confirmation: Confirmation?
        @Presents package var serverDetails: ServerDetailsFeature.State?
        @Presents package var replaceShare: ReplaceShareFeature.State?

        package init(
            profile: ServerProfile,
            status: SealStatus? = nil,
            feedback: AppFeedback = .info("Prototype: use disposable test shares until the security checks in issue #1 have been completed.")
        ) {
            self.profile = profile
            self.status = status
            self.feedback = feedback
        }

        var isBusy: Bool { operation != nil }
        var activity: LocalizedStringResource? { operation?.activity }
        var canUnseal: Bool {
            !isBusy && status?.supportsUnseal == true && status?.sealed == true
        }
    }

    package enum Action: Equatable {
        package enum Delegate: Equatable {
            case localDataRemoved(feedback: AppFeedback, requiresLocalReset: Bool)
        }

        case refreshTapped
        case refreshRequested
        case refreshResponse(Result<SealStatus, AppFailure>)
        case unsealTapped
        case confirmUnsealTapped
        case confirmationDismissed
        case operationActivity(State.Operation)
        case unsealPreflightStatus(SealStatus)
        case unsealPreflightFailed(AppFailure)
        case unsealAlreadyUnsealed(SealStatus)
        case unsealCompleted(SealStatus)
        case unsealFailed(AppFailure)
        case unsealOutcomeUnknown(AppFeedback)
        case operationCancelled
        case serverDetailsTapped
        case replaceShareTapped
        case removeLocalDataTapped
        case confirmRemoveLocalDataTapped
        case removeLocalDataResponse(Result<LocalPersistenceOutcome, AppFailure>)
        case privacyInterrupted
        case serverDetails(PresentationAction<ServerDetailsFeature.Action>)
        case replaceShare(PresentationAction<ReplaceShareFeature.Action>)
        case delegate(Delegate)
    }

    private enum CancelID: Hashable {
        case operation
    }

    @Dependency(\.sealbreakClient) private var client

    package var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .refreshTapped, .refreshRequested:
                guard !state.isBusy else { return .none }
                state.operation = .checkingStatus
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
                state.feedback = status.supportsUnseal
                    ? .success("Status checked. Nothing is sent automatically.")
                    : .warning("Only initialized Shamir seals are supported. Initialization, auto-unseal, and seal migration are not supported.")
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
                synchronizeServerDetails(&state)
                let target = state.profile
                let client = self.client
                return .run { send in
                    var preflightCompleted = false
                    var submissionStarted = false
                    do {
                        try await client.waitForForeground()
                        let before = try await client.status(target)
                        preflightCompleted = true
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
                            target.id,
                            "Send one Shamir share to \(target.origin)"
                        )
                        defer { record.share.removeAll(keepingCapacity: false) }
                        guard record.profileID == target.id,
                              record.boundOrigin == target.origin else {
                            throw AppFailure("Target binding mismatch. Nothing was sent. Reconfigure the local share for this server before retrying.")
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
                            let detailResource: LocalizedStringResource =
                                (error as? AppFailure)?.feedback.text ?? "Request failed."
                            let detail = String(localized: detailResource)
                            await send(
                                .unsealOutcomeUnknown(
                                    .warning(
                                        "\(detail) The final outcome is unknown. Check status before another attempt; a request already received cannot be undone."
                                    )
                                )
                            )
                        } else if preflightCompleted {
                            await send(.unsealFailed(normalizedAppFailure(error)))
                        } else {
                            await send(.unsealPreflightFailed(normalizedAppFailure(error)))
                        }
                    }
                }
                .cancellable(id: CancelID.operation)

            case .operationActivity(let operation):
                state.operation = operation
                synchronizeServerDetails(&state)
                return .none

            case .unsealPreflightStatus(let status):
                state.status = status
                synchronizeServerDetails(&state)
                return .none

            case .unsealAlreadyUnsealed(let status):
                state.operation = nil
                state.status = status
                state.feedback = .info("Already unsealed. No share was read or sent.")
                synchronizeServerDetails(&state)
                return .none

            case .unsealCompleted(let status):
                state.operation = nil
                state.status = status
                let feedbackText: LocalizedStringResource = status.sealed
                    ? "Submission completed; still sealed. Progress: \(status.progress)/\(status.t). Other holders must submit their own shares to this same node."
                    : "Verified: this endpoint now reports unsealed. This does not prove which operator completed the quorum."
                state.feedback = .success(feedbackText)
                synchronizeServerDetails(&state)
                return .none

            case .operationCancelled:
                state.operation = nil
                state.status = nil
                state.feedback = .warning(
                    "Operation cancelled. Refresh status before retrying; a submitted request may already have been processed."
                )
                synchronizeServerDetails(&state)
                return .none

            case .serverDetailsTapped:
                state.serverDetails = ServerDetailsFeature.State(
                    profile: state.profile,
                    status: state.status,
                    isBusy: state.isBusy,
                    activity: state.activity
                )
                return .none

            case .replaceShareTapped:
                guard !state.isBusy else { return .none }
                state.replaceShare = ReplaceShareFeature.State(profile: state.profile)
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
                let profileID = state.profile.id
                let client = self.client
                return .run { send in
                    do {
                        let outcome = try await client.removeLocalProfile(
                            profileID,
                            "Permanently remove Sealbreak’s local share; independent recovery will be required"
                        )
                        await send(.removeLocalDataResponse(.success(outcome)))
                    } catch is CancellationError {
                        await send(.operationCancelled)
                    } catch {
                        await send(.removeLocalDataResponse(.failure(normalizedAppFailure(error))))
                    }
                }
                .cancellable(id: CancelID.operation)

            case .removeLocalDataResponse(.success(.completed)):
                let feedback = AppFeedback.success(
                    "Local share removed. Copies elsewhere remain valid; only server-side rekeying replaces the server’s Shamir shares."
                )
                state.operation = nil
                state.status = nil
                state.feedback = feedback
                state.serverDetails = nil
                state.replaceShare = nil
                return .send(
                    .delegate(
                        .localDataRemoved(
                            feedback: feedback,
                            requiresLocalReset: false
                        )
                    )
                )

            case .removeLocalDataResponse(.success(.recoveryRequired(let notice))):
                let feedback = AppFeedback.warning(notice)
                state.operation = nil
                state.status = nil
                state.feedback = feedback
                state.serverDetails = nil
                state.replaceShare = nil
                return .send(
                    .delegate(
                        .localDataRemoved(
                            feedback: feedback,
                            requiresLocalReset: true
                        )
                    )
                )

            case .refreshResponse(.failure(let failure)),
                 .unsealPreflightFailed(let failure),
                 .removeLocalDataResponse(.failure(let failure)):
                state.operation = nil
                state.status = nil
                state.feedback = failure.feedback
                synchronizeServerDetails(&state)
                return .none

            case .unsealFailed(let failure):
                state.operation = nil
                state.feedback = failure.feedback
                synchronizeServerDetails(&state)
                return .none

            case .unsealOutcomeUnknown(let feedback):
                state.operation = nil
                state.status = nil
                state.feedback = feedback
                synchronizeServerDetails(&state)
                return .none

            case .privacyInterrupted:
                state.status = nil
                state.confirmation = nil
                state.replaceShare = nil
                state.serverDetails = nil

                let client = self.client
                if state.operation == .removingLocalData {
                    return .run { _ in
                        await client.cancelSensitiveOperation()
                    }
                }

                let wasBusy = state.isBusy
                state.operation = nil
                if wasBusy {
                    state.feedback = .warning(
                        "Operation interrupted. Check status on return; an already submitted request cannot be recalled."
                    )
                }
                return .merge(
                    .cancel(id: CancelID.operation),
                    .run { _ in await client.cancelSensitiveOperation() }
                )

            case .serverDetails(.presented(.delegate(.refreshRequested))):
                return .send(.refreshRequested)

            case .serverDetails(.presented(.delegate(.dismissRequested))):
                state.serverDetails = nil
                return .none

            case .replaceShare(.presented(.delegate(.saved))):
                state.replaceShare = nil
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
        guard var details = state.serverDetails else { return }

        details.profile = state.profile
        details.status = state.status
        details.isBusy = state.isBusy
        details.activity = state.activity
        state.serverDetails = details
    }
}
