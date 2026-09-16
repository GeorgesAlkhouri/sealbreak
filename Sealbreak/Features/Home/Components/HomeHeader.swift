import SwiftUI

enum HomeMenuAction {
    case refresh
    case serverDetails
    case replaceShare
    case restoreProfile
    case removeLocalData
}

struct HomeHeader: View {
    let isBusy: Bool
    let onAction: (HomeMenuAction) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "shield")
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(PapercutPalette.cream)
                .shadow(color: .black.opacity(0.35), radius: 4, y: 4)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: -1) {
                Text("Sealbreak")
                    .font(.system(size: 31, weight: .bold))
                    .foregroundStyle(PapercutPalette.cream)

                Text("S E C U R E   A C C E S S")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(PapercutPalette.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 8)

            HomeMenu(isBusy: isBusy, onAction: onAction)
        }
        .frame(maxWidth: 345)
    }
}
