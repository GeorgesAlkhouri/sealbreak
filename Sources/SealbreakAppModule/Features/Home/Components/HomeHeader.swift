import SwiftUI

enum HomeMenuAction {
    case refresh
    case serverDetails
    case replaceShare
    case removeLocalData
}

struct HomeHeader: View {
    let isBusy: Bool
    let onAction: (HomeMenuAction) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                shield
                brandText
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 8)
                HomeMenu(isBusy: isBusy, onAction: onAction)
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    shield
                    Spacer()
                    HomeMenu(isBusy: isBusy, onAction: onAction)
                }

                brandText
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: 345)
    }

    private var shield: some View {
        Image(systemName: "shield")
            .font(.system(size: 36, weight: .bold))
            .foregroundStyle(PapercutPalette.cream)
            .shadow(color: .black.opacity(0.35), radius: 4, y: 4)
            .accessibilityHidden(true)
    }

    private var brandText: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Sealbreak")
                .font(.title.bold())
                .foregroundStyle(PapercutPalette.cream)
                .fixedSize(horizontal: false, vertical: true)

            Text("SECURE ACCESS")
                .font(.caption2.weight(.medium))
                .tracking(2)
                .foregroundStyle(PapercutPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
