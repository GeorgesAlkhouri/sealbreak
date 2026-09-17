import Foundation

struct HomeViewState: Equatable {
    enum Status: Equatable {
        case unknown
        case checking(activity: String)
        case sealed(progress: Int, threshold: Int, supportsUnseal: Bool)
        case unsealing(activity: String)
        case unsealed

        var title: String {
            switch self {
            case .unknown:
                return "UNKNOWN"
            case .checking:
                return "CHECKING"
            case .sealed:
                return "SEALED"
            case .unsealing:
                return "UNSEALING"
            case .unsealed:
                return "UNSEALED"
            }
        }

        var primaryDetail: String {
            switch self {
            case .unknown:
                return "Status unknown"
            case .checking(let activity), .unsealing(let activity):
                return activity.isEmpty ? "Working…" : activity
            case .sealed(let progress, let threshold, _):
                return "\(progress) of \(threshold) shares submitted"
            case .unsealed:
                return "OpenBao is available"
            }
        }

        var secondaryDetail: String {
            switch self {
            case .unknown:
                return "Check status before sending"
            case .checking, .unsealing:
                return "Please keep the app open"
            case .sealed(_, _, let supportsUnseal):
                return supportsUnseal ? "Shamir seal" : "Manual unseal unavailable"
            case .unsealed:
                return "Status checked"
            }
        }

        var progressFraction: Double {
            switch self {
            case .unknown:
                return 0.20
            case .checking, .unsealing:
                return 0.66
            case .sealed(let progress, let threshold, _):
                guard threshold > 0 else { return 0 }
                return min(1, max(0, Double(progress) / Double(threshold)))
            case .unsealed:
                return 1
            }
        }
    }

    enum PrimaryAction: Equatable {
        case checkStatus(enabled: Bool)
        case unseal(enabled: Bool)
        case working(title: String)

        var title: String {
            switch self {
            case .checkStatus:
                return "Check status"
            case .unseal:
                return "Unseal with Face ID"
            case .working(let title):
                return title.isEmpty ? "Working…" : title
            }
        }

        var systemImage: String {
            switch self {
            case .checkStatus:
                return "arrow.clockwise"
            case .unseal:
                return "faceid"
            case .working:
                return "hourglass"
            }
        }

        var enabled: Bool {
            switch self {
            case .checkStatus(let enabled), .unseal(let enabled):
                return enabled
            case .working:
                return false
            }
        }
    }

    let serverName: String
    let origin: String
    let status: Status
    let primaryAction: PrimaryAction
    let notice: String?
    let isBusy: Bool

    init(
        profile: ServerProfile,
        sealStatus: SealStatus?,
        operation: HomeFeature.State.Operation?,
        notice: String
    ) {
        serverName = profile.name
        origin = Self.displayOrigin(profile.origin)
        isBusy = operation != nil

        if let operation {
            let activity = operation.activity
            switch operation {
            case .checkingTarget, .waitingForFaceID, .submittingShare, .verifyingStatus:
                status = .unsealing(activity: activity)
            case .checkingStatus, .restoringProfile, .removingLocalData:
                status = .checking(activity: activity)
            }
            primaryAction = .working(title: activity)
            self.notice = nil
            return
        }

        guard let sealStatus else {
            status = .unknown
            primaryAction = .checkStatus(enabled: true)
            self.notice = notice
            return
        }

        if sealStatus.sealed {
            status = .sealed(
                progress: sealStatus.progress,
                threshold: sealStatus.t,
                supportsUnseal: sealStatus.supportsUnseal
            )
            primaryAction = .unseal(enabled: sealStatus.supportsUnseal)
        } else {
            status = .unsealed
            primaryAction = .checkStatus(enabled: true)
        }
        self.notice = nil
    }

    private static func displayOrigin(_ origin: String) -> String {
        origin
            .replacingOccurrences(of: "https://", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
