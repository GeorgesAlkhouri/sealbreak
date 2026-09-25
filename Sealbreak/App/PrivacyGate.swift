import ComposableArchitecture
import Foundation
import SwiftUI

struct PrivacyCover<Content: View>: View {
    let store: StoreOf<PrivacyFeature>
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            content()
                .opacity(store.isConcealed ? 0 : 1)
                .blur(radius: store.isConcealed ? 22 : 0)
                .allowsHitTesting(!store.isConcealed)
                .accessibilityHidden(store.isConcealed)

            if store.isConcealed {
                Color(.systemBackground)
                    .ignoresSafeArea()
                    .overlay {
                        VStack(spacing: 12) {
                            Image(systemName: "lock.shield.fill")
                                .font(.system(size: 42))
                            Text(concealmentTitle)
                                .font(.headline)
                        }
                    }
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
    }

    private var concealmentTitle: LocalizedStringResource {
        store.isCaptured ? "Screen capture blocked" : "Sealbreak locked"
    }
}

struct PrivacyGate<Content: View>: View {
    @Environment(\.isSceneCaptured) private var isSceneCaptured
    @Environment(\.scenePhase) private var scenePhase

    let store: StoreOf<PrivacyFeature>
    @ViewBuilder let content: () -> Content

    var body: some View {
        PrivacyCover(store: store) {
            content()
        }
        .onAppear {
            store.send(.phaseChanged(Self.phase(scenePhase)))
            store.send(.captureChanged(isSceneCaptured))
        }
        .onChange(of: scenePhase) { _, phase in
            store.send(.phaseChanged(Self.phase(phase)))
        }
        .onChange(of: isSceneCaptured) { _, isCaptured in
            store.send(.captureChanged(isCaptured))
        }
    }

    private static func phase(_ phase: ScenePhase) -> PrivacyFeature.State.Phase {
        switch phase {
        case .active:
            return .active
        case .inactive:
            return .inactive
        case .background:
            return .background
        @unknown default:
            return .inactive
        }
    }
}
