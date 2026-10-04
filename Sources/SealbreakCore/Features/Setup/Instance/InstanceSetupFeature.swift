import ComposableArchitecture
import Foundation

@Reducer
package struct InstanceSetupFeature {
    @ObservableState
    package struct State: Equatable {
        package var name = "Server"
        package var address = ""
        package var checkedProfile: ServerProfile?
        package var dnssecStatus: DNSSECStatus?
        package var nameValidationError: LocalizedStringResource?
        package var addressValidationError: LocalizedStringResource?
        package var feedback: AppFeedback?
        package var isCheckingConnection = false

        package var canCheckConnection: Bool {
            !isCheckingConnection
                && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        package var canContinue: Bool {
            checkedProfile != nil && !isCheckingConnection
        }

        package var hasDraft: Bool {
            name != "Server"
                || !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || checkedProfile != nil
        }

        mutating func invalidateConnectionCheck() {
            checkedProfile = nil
            dnssecStatus = nil
            nameValidationError = nil
            addressValidationError = nil
            feedback = nil
        }
    }

    package enum Action: Equatable {
        package enum Delegate: Equatable {
            case continueWithProfile(ServerProfile)
        }

        case nameChanged(String)
        case addressChanged(String)
        case checkConnectionTapped
        case dnssecResolved(DNSSECStatus)
        case connectionResponse(Result<ServerProfile, AppFailure>)
        case continueTapped
        case privacyInterrupted
        case cancelCheck
        case delegate(Delegate)
    }

    private enum CancelID: Hashable {
        case connectionCheck
    }

    @Dependency(\.sealbreakClient) private var client
    @Dependency(\.uuid) private var uuid

    package var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .nameChanged(let name):
                guard state.name != name else { return .none }
                state.name = name
                state.invalidateConnectionCheck()
                return .none

            case .addressChanged(let address):
                guard state.address != address else { return .none }
                state.address = address
                state.invalidateConnectionCheck()
                return .none

            case .checkConnectionTapped:
                guard state.canCheckConnection else { return .none }

                do {
                    _ = try ServerProfile.canonicalOrigin(state.address)
                } catch {
                    state.invalidateConnectionCheck()
                    state.addressValidationError = normalizedAppFailure(error).feedback.text
                    return .none
                }

                let profile: ServerProfile
                do {
                    profile = try ServerProfile(id: uuid(), name: state.name, address: state.address)
                } catch {
                    state.invalidateConnectionCheck()
                    state.nameValidationError = normalizedAppFailure(error).feedback.text
                    return .none
                }

                state.checkedProfile = nil
                state.dnssecStatus = nil
                state.feedback = nil
                state.isCheckingConnection = true

                let client = self.client
                return .run { send in
                    // ServerProfile guarantees a canonical HTTPS origin with a host.
                    let host = URL(string: profile.origin)!.host!

                    do {
                        let dnssecStatus = try await client.dnssecStatus(host)
                        await send(.dnssecResolved(dnssecStatus))

                        guard dnssecStatus != .bogus else {
                            await send(
                                .connectionResponse(
                                    .failure(
                                        AppFailure(
                                            LocalizedStringResource("DNSSEC validation failed for this host. Fix its DNSSEC configuration before continuing.", bundle: .module)
                                        )
                                    )
                                )
                            )
                            return
                        }

                        try Task.checkCancellation()

                        _ = try await client.status(profile)

                        let product: ServerProduct
                        do {
                            product = try await client.detectProduct(profile)
                        } catch is AppFailure {
                            product = .generic
                        }

                        let checkedProfile = try ServerProfile(
                            id: profile.id,
                            name: profile.name,
                            address: profile.origin,
                            product: product
                        )
                        await send(.connectionResponse(.success(checkedProfile)))
                    } catch is CancellationError {
                        await send(.connectionResponse(.failure(AppFailure(LocalizedStringResource("Connection check cancelled.", bundle: .module)))))
                    } catch {
                        await send(
                            .connectionResponse(
                                .failure(normalizedAppFailure(error))
                            )
                        )
                    }
                }
                .cancellable(id: CancelID.connectionCheck)

            case .dnssecResolved(let status):
                state.dnssecStatus = status
                return .none

            case .connectionResponse(.success(let profile)):
                state.isCheckingConnection = false
                state.checkedProfile = profile
                state.feedback = nil
                return .none

            case .connectionResponse(.failure(let failure)):
                state.isCheckingConnection = false
                state.checkedProfile = nil
                state.feedback = failure.feedback
                return .none

            case .continueTapped:
                guard let profile = state.checkedProfile,
                      state.canContinue else {
                    return .none
                }
                return .send(.delegate(.continueWithProfile(profile)))

            case .privacyInterrupted:
                let wasChecking = state.isCheckingConnection
                state.isCheckingConnection = false
                state.checkedProfile = nil
                if wasChecking {
                    state.feedback = .warning(LocalizedStringResource("Connection check interrupted. Try again.", bundle: .module))
                }
                return .cancel(id: CancelID.connectionCheck)

            case .cancelCheck:
                state.isCheckingConnection = false
                return .cancel(id: CancelID.connectionCheck)

            case .delegate:
                return .none
            }
        }
    }
}
