import SealbreakCore
import SwiftUI

struct UnsealButton: View {
    let state: HomeViewState.PrimaryAction
    let action: () -> Void

    @ScaledMetric(relativeTo: .headline) private var actionHeight: CGFloat = 74

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: state.systemImage)
                    .font(.system(size: 26, weight: .medium))
                    .frame(width: 30, height: 30)

                Text(state.title)
                    .font(.headline.weight(.bold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(PapercutPalette.cream)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            // Keep the control's bounds stable when the activity label changes.
            // Scale the fixed height with Dynamic Type for accessibility.
            .frame(height: actionHeight)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(PapercutPalette.buttonBack)
                        .offset(x: 2, y: 6)

                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(PapercutPalette.button)
                }
            }
            .shadow(color: .black.opacity(0.38), radius: 10, y: 10)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(state.title))
        .accessibilityIdentifier("home-primary-action")
        // Avoid inherited status animations moving the icon or label independently
        // of the button background when the action switches to or from working.
        .transaction { $0.animation = nil }
        .disabled(!state.enabled)
        .opacity(state.enabled ? 1 : 0.58)
    }
}
