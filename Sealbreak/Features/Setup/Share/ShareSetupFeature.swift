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

    struct ProfileResult: Equatable, Sendable {
        let profile: ServerProfile
        let notice: String
    }

    enum Action: Equatable {
        enum Delegate: Equatable {
            case profileReady(ServerProfile, notice: String)
        }

        case saveTapped(share: String)
        case importResponse(Result<ProfileResult, AppFailure>)
        case operationCancelled
        case privacyInterrupted
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
                                .success(
                                    ProfileResult(
                                        profile: profile,
                                        notice: notice
                                    )
                                )
                            )
                        )
                    } catch is CancellationError {
                        await send(.operationCancelled)
                    } catch {
                        await send(
                            .importResponse(
                                .failure(normalizedAppFailure(error))
                            )
                        )
                    }
                }
                .cancellable(id: CancelID.importShare)

            case .importResponse(.success(let result)):
                state.operation = nil
                state.notice = result.notice
                return .send(
                    .delegate(
                        .profileReady(
                            result.profile,
                            notice: result.notice
                        )
                    )
                )

            case .importResponse(.failure(let failure)):
                state.operation = nil
                state.notice = failure.message
                return .none

            case .operationCancelled:
                state.operation = nil
                state.notice = "Operation cancelled. No new protected share was saved."
                return .none

            case .privacyInterrupted:
                let wasBusy = state.isBusy
                state.operation = nil
                if wasBusy {
                    state.notice = "Operation interrupted. No new protected share should be assumed saved."
                }

                let client = self.client
                return .merge(
                    .cancel(id: CancelID.importShare),
                    .run { _ in
                        await client.cancelSensitiveOperation()
                    }
                )

            case .delegate:
                return .none
            }
        }
    }
}
