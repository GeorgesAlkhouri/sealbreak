import ComposableArchitecture

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
            case localResetRequired(notice: String)
        }

        case saveTapped(share: String)
        case importResponse(Result<ProfileResult, AppFailure>)
        case localResetRequired(String)
        case operationCancelled
        case privacyInterrupted
        case delegate(Delegate)
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
                let profile = state.profile
                let client = self.client
                return .run { send in
                    var record = record
                    defer { record.share.removeAll(keepingCapacity: false) }

                    do {
                        let outcome = try await client.protectNewProfile(
                            profile,
                            record,
                            "Protect this share for \(record.boundOrigin)"
                        )

                        switch outcome {
                        case .protected:
                            await send(
                                .importResponse(
                                    .success(
                                        ProfileResult(
                                            profile: profile,
                                            notice: "Share protected on this iPhone. Check status to begin."
                                        )
                                    )
                                )
                            )

                        case .recoveryRequired(let notice):
                            await send(.localResetRequired(notice))
                        }
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

            case .localResetRequired(let notice):
                state.operation = nil
                state.notice = notice
                return .send(
                    .delegate(
                        .localResetRequired(notice: notice)
                    )
                )

            case .operationCancelled:
                state.operation = nil
                state.notice = "Operation cancelled. No new protected share was saved."
                return .none

            case .privacyInterrupted:
                guard state.isBusy else { return .none }
                let client = self.client
                return .run { _ in
                    await client.cancelSensitiveOperation()
                }

            case .delegate:
                return .none
            }
        }
    }
}
