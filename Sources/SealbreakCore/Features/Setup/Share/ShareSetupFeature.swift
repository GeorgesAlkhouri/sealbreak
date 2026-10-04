import ComposableArchitecture
import Foundation

@Reducer
package struct ShareSetupFeature {
    @ObservableState
    package struct State: Equatable {
        enum Operation: Equatable {
            case protecting

            var activity: LocalizedStringResource {
                LocalizedStringResource("Protecting share…", bundle: .module)
            }
        }

        package let profile: ServerProfile
        var operation: Operation?
        package var feedback: AppFeedback?

        package init(
            profile: ServerProfile,
            feedback: AppFeedback? = nil
        ) {
            self.profile = profile
            self.feedback = feedback
        }

        package var isBusy: Bool { operation != nil }
        package var activity: LocalizedStringResource? { operation?.activity }
    }

    package struct ProfileResult: Equatable, Sendable {
        let profile: ServerProfile
        let feedback: AppFeedback
    }

    package enum Action: Equatable {
        package enum Delegate: Equatable {
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

    package var body: some ReducerOf<Self> {
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
                            LocalizedStringResource("Protect this share for \(record.boundOrigin)", bundle: .module)
                        )

                        switch outcome {
                        case .completed:
                            await send(
                                .importResponse(
                                    .success(
                                        ProfileResult(
                                            profile: profile,
                                            feedback: .success(LocalizedStringResource("Share protected on this iPhone. Check status to begin.", bundle: .module))
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
                state.feedback = .warning(LocalizedStringResource("Operation cancelled. No new protected share was saved.", bundle: .module))
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
