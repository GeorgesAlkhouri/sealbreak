import Foundation
import SealbreakCore

struct HomeViewState: Equatable {
    enum Status: Equatable {
        case unknown
        case sealed(progress: Int, threshold: Int, supportsUnseal: Bool)
        case unsealed

        var title: LocalizedStringResource {
            switch self {
            case .unknown:
                return "UNKNOWN"
            case .sealed:
                return "SEALED"
            case .unsealed:
                return "UNSEALED"
            }
        }

        var primaryDetail: LocalizedStringResource {
            switch self {
            case .unknown:
                return "Status unknown"
            case .sealed(let progress, let threshold, _):
                return "\(progress) of \(threshold) shares submitted"
            case .unsealed:
                return "Server is available"
            }
        }

        var secondaryDetail: LocalizedStringResource {
            switch self {
            case .unknown:
                return "Check status before sending"
            case .sealed(_, _, let supportsUnseal):
                return supportsUnseal ? "Shamir seal" : "Manual unseal unavailable"
            case .unsealed:
                return "Status checked"
            }
        }

        var progressFraction: Double {
            switch self {
            case .unknown:
                return 0
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
        case working(title: LocalizedStringResource)

        var title: LocalizedStringResource {
            switch self {
            case .checkStatus:
                return "Check status"
            case .unseal:
                return "Unseal with Face ID"
            case .working(let title):
                return title
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
    let feedback: AppFeedback?
    let isBusy: Bool

    init(
        profile: ServerProfile,
        sealStatus: SealStatus?,
        operation: HomeFeature.State.Operation?,
        feedback: AppFeedback
    ) {
        serverName = profile.name
        origin = Self.displayOrigin(profile.origin)
        isBusy = operation != nil

        if let sealStatus {
            if sealStatus.sealed {
                status = .sealed(
                    progress: sealStatus.progress,
                    threshold: sealStatus.t,
                    supportsUnseal: sealStatus.supportsUnseal
                )
            } else {
                status = .unsealed
            }
        } else {
            status = .unknown
        }

        if let operation {
            primaryAction = .working(title: operation.activity)
            self.feedback = nil
            return
        }

        guard let sealStatus else {
            primaryAction = .checkStatus(enabled: true)
            self.feedback = feedback
            return
        }

        primaryAction = sealStatus.sealed
            ? .unseal(enabled: sealStatus.supportsUnseal)
            : .checkStatus(enabled: true)
        switch feedback.level {
        case .warning, .error:
            self.feedback = feedback
        case .info, .success:
            self.feedback = nil
        }
    }

    private static func displayOrigin(_ origin: String) -> String {
        origin
            .replacingOccurrences(of: "https://", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
