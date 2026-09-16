import SwiftUI
import UIKit

struct SensitiveDraftGuard: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    let clear: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: scenePhase) { _, phase in
                if phase != .active {
                    clear()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIScreen.capturedDidChangeNotification)) { _ in
                if UIScreen.main.isCaptured {
                    clear()
                }
            }
    }
}

extension View {
    func clearSensitiveDraftOnPrivacyChange(_ clear: @escaping () -> Void) -> some View {
        modifier(SensitiveDraftGuard(clear: clear))
    }
}
