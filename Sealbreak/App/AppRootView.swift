import ComposableArchitecture
import SwiftUI

struct AppRootView: View {
    let store: StoreOf<AppFeature>

    var body: some View {
        PrivacyGate(store: store.scope(state: \.privacy, action: \.privacy)) {
            NavigationStack {
                if let homeStore = store.scope(state: \.home, action: \.home) {
                    HomeView(store: homeStore)
                } else if let setupStore = store.scope(state: \.setup, action: \.setup) {
                    SetupView(store: setupStore)
                } else {
                    ZStack {
                        PapercutPalette.sky.ignoresSafeArea()
                        ProgressView("Loading protected profile…")
                            .tint(PapercutPalette.cream)
                            .foregroundStyle(PapercutPalette.cream)
                    }
                }
            }
        }
        .task {
            await store.send(.task).finish()
        }
    }
}
