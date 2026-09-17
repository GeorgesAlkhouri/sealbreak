import SwiftUI

struct UnsealButton: View {
    let state: HomeViewState.PrimaryAction
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: state.systemImage)
                    .font(.system(size: 26, weight: .medium))

                Text(state.title)
                    .font(.system(size: 20, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(PapercutPalette.cream)
            .frame(maxWidth: .infinity)
            .frame(height: 74)
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
        .disabled(!state.enabled)
        .opacity(state.enabled ? 1 : 0.58)
    }
}
