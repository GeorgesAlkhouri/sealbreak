import SwiftUI

struct HomeMenu: View {
    let isBusy: Bool
    let onAction: (HomeAction) -> Void

    var body: some View {
        Menu {
            Button("Check status", systemImage: "arrow.clockwise") {
                onAction(.refreshTapped)
            }
            .disabled(isBusy)

            Button("Server details", systemImage: "info.circle") {
                onAction(.serverDetailsTapped)
            }

            Button("Replace local share", systemImage: "key.horizontal") {
                onAction(.replaceShareTapped)
            }
            .disabled(isBusy)

            Button("Restore profile from Keychain", systemImage: "arrow.uturn.backward") {
                onAction(.restoreProfileTapped)
            }
            .disabled(isBusy)

            Divider()

            Button("Remove local data", systemImage: "trash", role: .destructive) {
                onAction(.removeLocalDataTapped)
            }
            .disabled(isBusy)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(PapercutPalette.cream)
                .frame(width: 44, height: 44)
                .background(PapercutPalette.menu)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.30), radius: 9, y: 8)
        }
        .accessibilityLabel("More options")
    }
}
