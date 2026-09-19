import ComposableArchitecture
import Foundation

@Reducer
struct InstanceSetupFeature {
    @ObservableState
    struct State: Equatable {
        var name = "Server"
        var address = ""
        var checkedProfile: ServerProfile?
        var dnssecStatus: DNSSECStatus?
        var notice: String?
        var isCheckingConnection = false

        var canCheckConnection: Bool {
            !isCheckingConnection
                && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        var canContinue: Bool {
            checkedProfile != nil && !isCheckingConnection
        }

        var hasDraft: Bool {
            name != "Server"
                || !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || checkedProfile != nil
        }

        mutating func invalidateConnectionCheck() {
            checkedProfile = nil
            dnssecStatus = nil
            notice = nil
        }
    }

    enum Action: Equatable {
        enum Delegate: Equatable {
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

    var body: some ReducerOf<Self> {
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

                let profile: ServerProfile
                do {
                    profile = try ServerProfile(name: state.name, address: state.address)
                } catch {
                    state.invalidateConnectionCheck()
                    state.notice = normalizedAppFailure(error).message
                    return .none
                }

                state.checkedProfile = nil
                state.dnssecStatus = nil
                state.notice = nil
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
                                            "DNSSEC validation failed for this host. Fix its DNSSEC configuration before continuing."
                                        )
                                    )
                                )
                            )
                            return
                        }

                        try Task.checkCancellation()

                        let product: ServerProduct
                        do {
                            product = try await client.detectProduct(profile)
                        } catch is AppFailure {
                            _ = try await client.status(profile)
                            product = .generic
                        }

                        let checkedProfile = try ServerProfile(
                            name: profile.name,
                            address: profile.origin,
                            product: product
                        )
                        await send(.connectionResponse(.success(checkedProfile)))
                    } catch is CancellationError {
                        await send(.connectionResponse(.failure(AppFailure("Connection check cancelled."))))
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
                state.notice = nil
                return .none

            case .connectionResponse(.failure(let failure)):
                state.isCheckingConnection = false
                state.checkedProfile = nil
                state.notice = failure.message
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
                    state.notice = "Connection check interrupted. Try again."
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
