import SwiftUI

struct SealStatusIndicator: View {
    let status: HomeViewState.Status

    var body: some View {
        ZStack {
            Circle()
                .stroke(PapercutPalette.ring, lineWidth: 18)

            Circle()
                .trim(from: 0, to: status.progressFraction)
                .stroke(
                    accent,
                    style: StrokeStyle(lineWidth: 18, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            Image(systemName: icon)
                .font(.system(size: 66, weight: .bold))
                .foregroundStyle(accent)
                .shadow(color: .black.opacity(0.38), radius: 6, y: 8)
        }
        .frame(width: 170, height: 170)
        .shadow(color: .black.opacity(0.30), radius: 6, y: 7)
        .accessibilityHidden(true)
    }

    var accent: Color {
        switch status {
        case .unknown:
            return PapercutPalette.secondaryText
        case .checking, .unsealing:
            return PapercutPalette.button
        case .sealed:
            return PapercutPalette.sealed
        case .unsealed:
            return PapercutPalette.unsealed
        }
    }

    private var icon: String {
        switch status {
        case .unknown:
            return "questionmark.circle"
        case .checking, .unsealing:
            return "lock"
        case .sealed:
            return "lock.fill"
        case .unsealed:
            return "lock.open.fill"
        }
    }
}
