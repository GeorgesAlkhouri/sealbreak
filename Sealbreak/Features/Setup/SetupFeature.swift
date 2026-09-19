import ComposableArchitecture

@Reducer
struct SetupFeature {
    @ObservableState
    struct State: Equatable {
        enum Operation: Equatable {
            case importing
            case restoring
            case removingLocalData

            var activity: String {
                switch self {
                case .importing:
                    return "Importing share…"
                case .restoring:
                    return "Restoring local profile…"
                case .removingLocalData:
                    return "Removing local data…"
                }
            }
        }

        var operation: Operation?
        var notice: String
        var confirmDelete = false

        init(
            notice: String = "Prototype: use disposable test shares until the security checks in issue #1 have been completed."
        ) {
            self.notice = notice
        }

        var isBusy: Bool { operation != nil }
        var activity: String { operation?.activity ?? "" }
    }

    struct ProfileResult: Equatable, Sendable {
        let profile: ServerProfile
        let notice: String
    }

    enum Action: Equatable {
        enum Delegate: Equatable {
            case profileReady(ServerProfile, notice: String)
        }

        case saveTapped(name: String, address: String, share: String, recoveryConfirmed: Bool)
        case importResponse(Result<ProfileResult, AppFailure>)
        case restoreProfileTapped
        case restoreResponse(Result<ProfileResult, AppFailure>)
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
        Reduce { state, action in
            switch action {
            case .saveTapped(let name, let address, let input, let recoveryConfirmed):
                guard !state.isBusy else { return .none }
                guard recoveryConfirmed else {
                    state.notice = "Confirm an independent recovery copy before importing."
                    return .none
                }

                let record: ShareRecord
                do {
                    record = try ShareRecord(
                        profile: ServerProfile(name: name, address: address),
                        input: input
                    )
                } catch {
                    state.notice = normalizedAppFailure(error).message
                    return .none
                }

                state.operation = .importing
                let client = self.client
                return .run { send in
                    var record = record
                    defer { record.share.removeAll(keepingCapacity: false) }
                    do {
                        try await client.waitForForeground()

                        let product: ServerProduct
                        do {
                            product = try await client.detectProduct(record.profile)
                        } catch is AppFailure {
                            product = .generic
                        }

                        record = try ShareRecord(
                            profile: ServerProfile(
                                name: record.profile.name,
                                address: record.profile.origin,
                                product: product
                            ),
                            input: record.share
                        )

                        try await client.insertShare(
                            record,
                            "Protect this share for \(record.profile.origin)"
                        )

                        let profile = record.profile
                        let notice: String
                        do {
                            try await client.saveProfile(profile)
                            notice = "Share saved with device-bound biometric protection. Check status to begin."
                        } catch {
                            notice = "Protected share exists, but display metadata could not be saved. Use Restore profile from Keychain on the next launch."
                        }
                        await send(.importResponse(.success(ProfileResult(profile: profile, notice: notice))))
                    } catch is CancellationError {
                        await send(.operationCancelled)
                    } catch {
                        await send(.importResponse(.failure(normalizedAppFailure(error))))
                    }
                }
                .cancellable(id: CancelID.operation)

            case .restoreProfileTapped:
                guard !state.isBusy else { return .none }
                state.operation = .restoring
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
                        await send(.restoreResponse(.success(ProfileResult(profile: profile, notice: notice))))
                    } catch is CancellationError {
                        await send(.operationCancelled)
                    } catch {
                        await send(.restoreResponse(.failure(normalizedAppFailure(error))))
                    }
                }
                .cancellable(id: CancelID.operation)

            case .importResponse(.success(let result)),
                 .restoreResponse(.success(let result)):
                state.operation = nil
                state.notice = result.notice
                return .send(.delegate(.profileReady(result.profile, notice: result.notice)))

            case .removeLocalDataTapped:
                guard !state.isBusy else { return .none }
                state.confirmDelete = true
                return .none

            case .confirmationDismissed:
                state.confirmDelete = false
                return .none

            case .confirmRemoveLocalDataTapped:
                guard !state.isBusy else { return .none }
                state.confirmDelete = false
                state.operation = .removingLocalData
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

            case .importResponse(.failure(let failure)),
                 .restoreResponse(.failure(let failure)),
                 .removeResponse(.failure(let failure)):
                state.operation = nil
                state.notice = failure.message
                return .none

            case .operationCancelled:
                state.operation = nil
                state.notice = "Operation cancelled. Refresh status before retrying; a submitted request may already have been processed."
                return .none

            case .privacyInterrupted:
                let wasBusy = state.isBusy
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

            case .delegate:
                return .none
            }
        }
    }
}
