import ComposableArchitecture
import Foundation
import SealbreakCore
import SwiftUI

public struct SealbreakRootView: View {
    private let store: StoreOf<AppFeature>

    public init() {
        store = Store(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.sealbreakClient = .live
        }
    }

    public var body: some View {
        PrivacyGate(store: privacyStore) {
            NavigationStack {
                if let homeStore = store.scope(state: \.home, action: \.home) {
                    HomeView(store: homeStore, privacyStore: privacyStore)
                } else if let setupStore = store.scope(state: \.setup, action: \.setup) {
                    SetupView(store: setupStore)
                } else if let welcomeStore = store.scope(state: \.welcome, action: \.welcome) {
                    WelcomeView(store: welcomeStore)
                } else {
                    ZStack {
                        PapercutPalette.sky.ignoresSafeArea()
                        ProgressView(LocalizedStringResource("Loading protected profile…", bundle: .module))
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

    private var privacyStore: StoreOf<PrivacyFeature> {
        store.scope(state: \.privacy, action: \.privacy)
    }
}
