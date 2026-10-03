import Foundation
import SwiftUI

struct HomeMenu: View {
    let isBusy: Bool
    let onAction: (HomeMenuAction) -> Void

    var body: some View {
        Menu {
            Button(LocalizedStringResource("Check status", bundle: .module), systemImage: "arrow.clockwise") {
                onAction(.refresh)
            }
            .disabled(isBusy)

            Button(LocalizedStringResource("Server details", bundle: .module), systemImage: "info.circle") {
                onAction(.serverDetails)
            }

            Button(LocalizedStringResource("Replace local share", bundle: .module), systemImage: "key.horizontal") {
                onAction(.replaceShare)
            }
            .disabled(isBusy)

            Divider()

            Button(LocalizedStringResource("Remove local data", bundle: .module), systemImage: "trash", role: .destructive) {
                onAction(.removeLocalData)
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
        .accessibilityLabel(LocalizedStringResource("More options", bundle: .module))
    }
}
