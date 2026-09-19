import SwiftUI
import UIKit

struct SensitiveDraftGuard: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase

    let clearsOnBackground: Bool
    let clear: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: scenePhase) { _, phase in
                if clearsOnBackground, phase == .background {
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
        clearsOnBackground: Bool = true,
        _ clear: @escaping () -> Void
    ) -> some View {
        modifier(
            SensitiveDraftGuard(
                clearsOnBackground: clearsOnBackground,
                clear: clear
            )
        )
    }
}
