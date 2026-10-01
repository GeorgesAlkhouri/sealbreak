import ComposableArchitecture
import Foundation

@Reducer
struct ShareSetupFeature {
    @ObservableState
    struct State: Equatable {
        enum Operation: Equatable {
            case protecting

            var activity: LocalizedStringResource {
                "Protecting share…"
            }
        }

        let profile: ServerProfile
        var operation: Operation?
        var feedback: AppFeedback

        init(
            profile: ServerProfile,
            feedback: AppFeedback = .info("Prototype: use disposable test shares until the security checks in issue #1 have been completed.")
        ) {
            self.profile = profile
            self.feedback = feedback
        }

        var isBusy: Bool { operation != nil }
        var activity: LocalizedStringResource? { operation?.activity }
    }

    struct ProfileResult: Equatable, Sendable {
        let profile: ServerProfile
        let feedback: AppFeedback
    }

    enum Action: Equatable {
        enum Delegate: Equatable {
            case profileReady(ServerProfile, feedback: AppFeedback)
            case localResetRequired(feedback: AppFeedback)
        }

        case saveTapped(share: String)
        case importResponse(Result<ProfileResult, AppFailure>)
        case localResetRequired(AppFeedback)
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
                    state.feedback = normalizedAppFailure(error).feedback
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
                        case .completed:
                            await send(
                                .importResponse(
                                    .success(
                                        ProfileResult(
                                            profile: profile,
                                            feedback: .success("Share protected on this iPhone. Check status to begin.")
                                        )
                                    )
                                )
                            )

                        case .recoveryRequired(let notice):
                            await send(.localResetRequired(.warning(notice)))
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
                state.feedback = result.feedback
                return .send(
                    .delegate(
                        .profileReady(
                            result.profile,
                            feedback: result.feedback
                        )
                    )
                )

            case .importResponse(.failure(let failure)):
                state.operation = nil
                state.feedback = failure.feedback
                return .none

            case .localResetRequired(let feedback):
                state.operation = nil
                state.feedback = feedback
                return .send(
                    .delegate(
                        .localResetRequired(feedback: feedback)
                    )
                )

            case .operationCancelled:
                state.operation = nil
                state.feedback = .warning("Operation cancelled. No new protected share was saved.")
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
