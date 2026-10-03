import Foundation

package func resolveLocalSetupState(
    profiles: [StoredProfile]
) -> LocalSetupState {
    guard profiles.count <= 1 else {
        return .recoveryRequired(
            LocalizedStringResource("Local Sealbreak data contains multiple server profiles, but this app version supports one. Reset local data to continue.", bundle: .module)
        )
    }

    guard let entry = profiles.first else {
        return .empty
    }

    switch entry.state {
    case .creating:
        return .recoveryRequired(
            LocalizedStringResource("Local Sealbreak setup did not finish cleanly. Reset local data to continue, then set up again using your independent share copy.", bundle: .module)
        )

    case .ready:
        return .ready(entry.profile)

    case .removing:
        return .recoveryRequired(
            LocalizedStringResource("Local Sealbreak removal did not finish cleanly. Reset local data to continue.", bundle: .module)
        )
    }
}

package func createLocalProfileTransaction(
    beginProfile: () throws -> Void,
    insertShare: () throws -> Void,
    commitProfile: () throws -> Void
) -> LocalPersistenceOutcome {
    do {
        try beginProfile()
        try insertShare()
        try commitProfile()
        return .completed
    } catch {
        return .recoveryRequired(
            LocalizedStringResource("Local setup could not be completed safely. Reset local Sealbreak data before continuing.", bundle: .module)
        )
    }
}

package func removeLocalProfileTransaction(
    beginRemoval: () throws -> Void,
    deleteShare: () throws -> Void,
    deleteProfile: () throws -> Void
) -> LocalPersistenceOutcome {
    do {
        try beginRemoval()
        try deleteShare()
        try deleteProfile()
        return .completed
    } catch {
        return .recoveryRequired(
            LocalizedStringResource("Local removal could not be completed safely. Reset local Sealbreak data before continuing.", bundle: .module)
        )
    }
}

package func resetLocalStorage(
    prepareReset: () throws -> Void,
    deleteShares: () throws -> Void,
    resetProfiles: () throws -> Void
) throws {
    try prepareReset()
    try deleteShares()
    try resetProfiles()
}
