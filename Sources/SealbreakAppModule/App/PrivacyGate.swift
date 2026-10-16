import ComposableArchitecture
import Foundation
import SealbreakCore
import SwiftUI
import UIKit

extension View {
    func privacyProtected(_ isConcealed: Bool) -> some View {
        opacity(isConcealed ? 0 : 1)
            .allowsHitTesting(!isConcealed)
            .accessibilityHidden(isConcealed)
    }
}

struct PrivacyGate<Content: View>: View {
    @Environment(\.isSceneCaptured) private var isSceneCaptured
    @Environment(\.scenePhase) private var scenePhase
    @State private var shield: PrivacyShieldWindow?
    let store: StoreOf<PrivacyFeature>
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .privacyProtected(privacyState.isConcealed)
            .onChange(of: privacyState, initial: true) { _, state in
                updateShield(state)
                store.send(.phaseChanged(state.phase))
                store.send(.captureChanged(state.isCaptured))
            }
            .onDisappear {
                shield?.isHidden = true
                shield = nil
            }
    }

    private var privacyState: PrivacyFeature.State {
        var state = PrivacyFeature.State()
        switch scenePhase {
        case .active: state.phase = .active
        case .background: state.phase = .background
        default: state.phase = .inactive
        }
        state.isCaptured = isSceneCaptured
        return state
    }

    private func updateShield(_ state: PrivacyFeature.State) {
        guard state.isConcealed else { shield?.isHidden = true; return }
        // Sealbreak explicitly supports one app scene (Info.plist).
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        if shield == nil {
            let window = PrivacyShieldWindow(windowScene: scene)
            window.backgroundColor = .systemBackground
            window.rootViewController = UIHostingController(rootView: PrivacyScreen(isCaptured: state.isCaptured))
            window.rootViewController?.view.accessibilityViewIsModal = true
            shield = window
        }
        guard let shield else { return }
        shield.overrideUserInterfaceStyle = scene.keyWindow?.overrideUserInterfaceStyle ?? .unspecified
        (shield.rootViewController as? UIHostingController<PrivacyScreen>)?.rootView = PrivacyScreen(isCaptured: state.isCaptured)
        let highestLevel = scene.windows.filter { $0 !== shield }.map(\.windowLevel.rawValue).max() ?? 0
        shield.windowLevel = UIWindow.Level(rawValue: max(UIWindow.Level.alert.rawValue, highestLevel) + 1)
        shield.frame = scene.effectiveGeometry.coordinateSpace.bounds
        shield.isHidden = false
        shield.rootViewController?.view.layoutIfNeeded()
    }
}

private struct PrivacyScreen: View {
    let isCaptured: Bool

    var body: some View {
        Color(.systemBackground)
            .ignoresSafeArea()
            .overlay {
                VStack(spacing: 12) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 42))
                    Text(isCaptured ? LocalizedStringResource("Screen capture blocked", bundle: .module) : LocalizedStringResource("Sealbreak locked", bundle: .module))
                        .font(.headline)
                }
            }
    }
}

final class PrivacyShieldWindow: UIWindow {
    override var canBecomeKey: Bool { false }
}
