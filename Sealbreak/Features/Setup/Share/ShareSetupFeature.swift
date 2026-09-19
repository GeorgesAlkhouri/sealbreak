import ComposableArchitecture

struct ShareImportPreview: Equatable, Sendable {
    static let visibleCharacterCount = 4

    static func masked(_ input: String) -> String? {
        guard let share = try? ShareRecord.validateShare(input) else {
            return nil
        }

        let characters = Array(share)
        let visible = visibleCharacterCount
        guard characters.count > visible * 2 else {
            return nil
        }

        let prefix = String(characters.prefix(visible))
        let suffix = String(characters.suffix(visible))
        return "\(prefix) •••• •••• \(suffix)"
    }
}

@Reducer
struct ShareSetupFeature {
    struct ProfileResult: Equatable, Sendable {
        let profile: ServerProfile
        let notice: String
    }

    @ObservableState
    struct State: Equatable {
        enum Operation: Equatable {
            case protecting

            var activity: String {
                "Protecting share…"
            }
        }

        let profile: ServerProfile
        var operation: Operation?
        var notice: String
        var backgroundedDuringProtection = false
        var draftClearGeneration = 0
        var pendingCompletion: ProfileResult?

        init(
            profile: ServerProfile,
            notice: String = "Prototype: use disposable test shares until the security checks in issue #1 have been completed."
        ) {
            self.profile = profile
            self.notice = notice
        }

        var isBusy: Bool { operation != nil }
        var activity: String { operation?.activity ?? "" }
    }

    enum Action: Equatable {
        enum Delegate: Equatable {
            case profileReady(ServerProfile, notice: String)
        }

        case saveTapped(share: String)
        case importResponse(Result<ProfileResult, AppFailure>)
        case biometricFailure(BiometricAuthorizationFailure)
        case operationCancelled
        case privacyInterrupted(SensitiveInterruption)
        case becameActive
        case draftCleared
        case delegate(Delegate)
    }

    private enum CancelID: Hashable {
        case importShare
    }

    @Dependency(\.sealbreakClient) private var client

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .saveTapped(let input):
                guard !state.isBusy else { return .none }

                let record: ShareRecord
                do {
                    record = try ShareRecord(profile: state.profile, input: input)
                } catch {
                    state.notice = normalizedAppFailure(error).message
                    return .none
                }

                state.operation = .protecting
                state.backgroundedDuringProtection = false
                state.pendingCompletion = nil

                let client = self.client
                return .run { send in
                    var record = record
                    defer { record.share.removeAll(keepingCapacity: false) }
                    do {
                        try await client.waitForForeground()
                        try await client.insertShare(
                            record,
                            "Protect this share for \(record.profile.origin)"
                        )

                        let profile = record.profile
                        let notice: String
                        do {
                            try await client.saveProfile(profile)
                            notice = "Share protected on this iPhone. Check status to begin."
                        } catch {
                            notice = "Protected share exists, but display metadata could not be saved. Use Restore profile from Keychain on the next launch."
                        }
                        await send(
                            .importResponse(
                                .success(ProfileResult(profile: profile, notice: notice))
                            )
                        )
                    } catch let failure as BiometricAuthorizationFailure {
                        await send(.biometricFailure(failure))
                    } catch is CancellationError {
                        await send(.operationCancelled)
                    } catch {
                        await send(.importResponse(.failure(normalizedAppFailure(error))))
                    }
                }
                .cancellable(id: CancelID.importShare)

            case .importResponse(.success(let result)):
                state.operation = nil
                state.backgroundedDuringProtection = false
                state.notice = result.notice
                state.pendingCompletion = result
                state.draftClearGeneration += 1
                return .none

            case .importResponse(.failure(let failure)):
                let shouldDiscardDraft = state.backgroundedDuringProtection
                state.operation = nil
                state.backgroundedDuringProtection = false
                state.notice = failure.message
                if shouldDiscardDraft {
                    state.draftClearGeneration += 1
                }
                return .none

            case .biometricFailure(let failure):
                state.operation = nil
                state.backgroundedDuringProtection = false
                state.notice = failure.message
                if failure.discardsSensitiveDraft {
                    state.draftClearGeneration += 1
                }
                return .none

            case .operationCancelled:
                let shouldDiscardDraft = state.backgroundedDuringProtection
                state.operation = nil
                state.backgroundedDuringProtection = false
                state.notice = "Operation cancelled. No new protected share was saved."
                if shouldDiscardDraft {
                    state.draftClearGeneration += 1
                }
                return .none

            case .privacyInterrupted(.background):
                if state.isBusy {
                    state.backgroundedDuringProtection = true
                    return .none
                }

                state.draftClearGeneration += 1
                let client = self.client
                return .run { _ in
                    await client.cancelSensitiveOperation()
                }

            case .privacyInterrupted(.screenCapture):
                state.operation = nil
                state.backgroundedDuringProtection = false
                state.draftClearGeneration += 1

                let client = self.client
                return .merge(
                    .cancel(id: CancelID.importShare),
                    .run { _ in await client.cancelSensitiveOperation() }
                )

            case .becameActive:
                state.backgroundedDuringProtection = false
                return .none

            case .draftCleared:
                guard let completion = state.pendingCompletion else {
                    return .none
                }

                state.pendingCompletion = nil
                return .send(
                    .delegate(
                        .profileReady(
                            completion.profile,
                            notice: completion.notice
                        )
                    )
                )

            case .delegate:
                return .none
            }
        }
    }
}
