import Foundation

package enum StoredProfileState: String, Codable, Equatable {
    case creating
    case ready
    case removing
}

package struct StoredProfile: Codable, Equatable {
    package let profile: ServerProfile
    package var state: StoredProfileState

    package init(profile: ServerProfile, state: StoredProfileState) {
        self.profile = profile
        self.state = state
    }
}
