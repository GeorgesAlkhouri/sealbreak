import SwiftUI
import UIKit

struct SensitiveDraftGuard: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase

    let preserveDuringSensitiveOperation: Bool
    let clear: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: scenePhase) { _, phase in
                if phase == .background, !preserveDuringSensitiveOperation {
                    clear()
                }
            }
            .onChange(of: preserveDuringSensitiveOperation) { _, isPreserving in
                if !isPreserving, scenePhase == .background {
                    clear()
                }
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: UIScreen.capturedDidChangeNotification
                )
            ) { _ in
                if UIScreen.main.isCaptured {
                    clear()
                }
            }
    }
}

extension View {
    func clearSensitiveDraftOnPrivacyChange(
        preserveDuringSensitiveOperation: Bool = false,
        _ clear: @escaping () -> Void
    ) -> some View {
        modifier(
            SensitiveDraftGuard(
                preserveDuringSensitiveOperation: preserveDuringSensitiveOperation,
                clear: clear
            )
        )
    }
}
