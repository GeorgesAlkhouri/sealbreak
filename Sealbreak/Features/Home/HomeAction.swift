enum HomeAction: Equatable {
    case refreshTapped
    case unsealTapped
    case serverDetailsTapped
    case replaceShareTapped
    case restoreProfileTapped
    case removeLocalDataTapped
}

enum HomeDestination: String, Identifiable {
    case serverDetails
    case replaceShare

    var id: String { rawValue }
}

enum HomeConfirmation: Equatable {
    case unseal
    case removeLocalData
}
