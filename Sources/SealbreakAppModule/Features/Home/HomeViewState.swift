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
                return LocalizedStringResource("UNKNOWN", bundle: .module)
            case .sealed:
                return LocalizedStringResource("SEALED", bundle: .module)
            case .unsealed:
                return LocalizedStringResource("UNSEALED", bundle: .module)
            }
        }

        var primaryDetail: LocalizedStringResource {
            switch self {
            case .unknown:
                return LocalizedStringResource("Status unknown", bundle: .module)
            case .sealed(let progress, let threshold, _):
                return LocalizedStringResource("\(progress) of \(threshold) shares submitted", bundle: .module)
            case .unsealed:
                return LocalizedStringResource("Server is available", bundle: .module)
            }
        }

        var secondaryDetail: LocalizedStringResource {
            switch self {
            case .unknown:
                return LocalizedStringResource("Check status before sending", bundle: .module)
            case .sealed(_, _, let supportsUnseal):
                return supportsUnseal ? LocalizedStringResource("Shamir seal", bundle: .module) : LocalizedStringResource("Manual unseal unavailable", bundle: .module)
            case .unsealed:
                return LocalizedStringResource("Status checked", bundle: .module)
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
                return LocalizedStringResource("Check status", bundle: .module)
            case .unseal:
                return LocalizedStringResource("Unseal with Face ID", bundle: .module)
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
