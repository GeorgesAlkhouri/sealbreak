import SwiftUI

struct SensitiveDraftGuard: ViewModifier {
    @Environment(\.isSceneCaptured) private var isSceneCaptured
    @Environment(\.scenePhase) private var scenePhase
    let clear: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: scenePhase) { _, phase in
                if phase != .active {
                    clear()
                }
            }
            .onAppear {
                if isSceneCaptured {
                    clear()
                }
            }
            .onChange(of: isSceneCaptured) { _, isCaptured in
                if isCaptured {
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
