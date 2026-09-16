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
            case .unknown: "UNKNOWN"
            case .checking: "CHECKING"
            case .sealed: "SEALED"
            case .unsealing: "UNSEALING"
            case .unsealed: "UNSEALED"
            }
        }

        var primaryDetail: String {
            switch self {
            case .unknown:
                "Status unknown"
            case .checking(let activity), .unsealing(let activity):
                activity.isEmpty ? "Working…" : activity
            case .sealed(let progress, let threshold, _):
                "\(progress) of \(threshold) shares submitted"
            case .unsealed:
                "OpenBao is available"
            }
        }

        var secondaryDetail: String {
            switch self {
            case .unknown:
                "Check status before sending"
            case .checking, .unsealing:
                "Please keep the app open"
            case .sealed(_, _, let supportsUnseal):
                supportsUnseal ? "Shamir seal" : "Manual unseal unavailable"
            case .unsealed:
                "Status checked"
            }
        }

        var progressFraction: Double {
            switch self {
            case .unknown:
                0.20
            case .checking, .unsealing:
                0.66
            case .sealed(let progress, let threshold, _):
                guard threshold > 0 else { return 0 }
                return min(1, max(0, Double(progress) / Double(threshold)))
            case .unsealed:
                1
            }
        }
    }

    enum PrimaryAction: Equatable {
        case checkStatus(enabled: Bool)
        case unseal(enabled: Bool)
        case working(title: String)

        var title: String {
            switch self {
            case .checkStatus: "Check status"
            case .unseal: "Unseal with Face ID"
            case .working(let title): title.isEmpty ? "Working…" : title
            }
        }

        var systemImage: String {
            switch self {
            case .checkStatus: "arrow.clockwise"
            case .unseal: "faceid"
            case .working: "hourglass"
            }
        }

        var enabled: Bool {
            switch self {
            case .checkStatus(let enabled), .unseal(let enabled): enabled
            case .working: false
            }
        }
    }

    let serverName: String
    let origin: String
    let status: Status
    let primaryAction: PrimaryAction
    let notice: String?
    let isBusy: Bool

    @MainActor
    init(model: AppModel) {
        let profile = model.profile
        serverName = profile?.name ?? "OpenBao"
        origin = Self.displayOrigin(profile?.origin ?? "")
        isBusy = model.busy

        if model.busy {
            let activity = model.activity
            let lower = activity.lowercased()
            let unsealing = lower.contains("submitting")
                || lower.contains("verifying")
                || lower.contains("face id")
                || lower.contains("target")
            status = unsealing ? .unsealing(activity: activity) : .checking(activity: activity)
            primaryAction = .working(title: activity)
            notice = nil
            return
        }

        guard let sealStatus = model.status else {
            status = .unknown
            primaryAction = .checkStatus(enabled: profile != nil)
            notice = model.notice
            return
        }

        if sealStatus.sealed {
            status = .sealed(
                progress: sealStatus.progress,
                threshold: sealStatus.t,
                supportsUnseal: sealStatus.supportsUnseal
            )
            primaryAction = .unseal(enabled: model.canUnseal)
        } else {
            status = .unsealed
            primaryAction = .checkStatus(enabled: true)
        }
        notice = nil
    }

    private static func displayOrigin(_ origin: String) -> String {
        origin
            .replacingOccurrences(of: "https://", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
