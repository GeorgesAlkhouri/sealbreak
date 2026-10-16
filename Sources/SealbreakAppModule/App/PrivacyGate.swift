import ComposableArchitecture
import Foundation
import SealbreakCore
import SwiftUI
import UIKit

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
                PrivacyScreen(isCaptured: store.isCaptured)
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
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
                    Text(concealmentTitle)
                        .font(.headline)
                }
            }
    }

    private var concealmentTitle: LocalizedStringResource {
        isCaptured ? LocalizedStringResource("Screen capture blocked", bundle: .module) : LocalizedStringResource("Sealbreak locked", bundle: .module)
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
        .background(
            PrivacyWindow(isConcealed: presentationState.isConcealed, isCaptured: isSceneCaptured)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        )
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

    private var presentationState: PrivacyFeature.State {
        var state = PrivacyFeature.State()
        state.phase = Self.phase(scenePhase)
        state.isCaptured = isSceneCaptured
        return state
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

// Native menus and dialogs are presented above SwiftUI's view-level covers.
// Keep one opaque shield in the same scene, above all of its existing windows.
private struct PrivacyWindow: UIViewRepresentable {
    let isConcealed: Bool
    let isCaptured: Bool

    func makeUIView(context: Context) -> AnchorView { AnchorView() }

    func updateUIView(_ view: AnchorView, context: Context) {
        view.isConcealed = isConcealed
        view.isCaptured = isCaptured
        view.updateShield()
    }

    static func dismantleUIView(_ view: AnchorView, coordinator: ()) {
        view.removeShield()
    }

    final class AnchorView: UIView {
        var isConcealed = false
        var isCaptured = false
        private var shield: UIWindow?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            updateShield()
        }

        func updateShield() {
            guard let scene = window?.windowScene else {
                removeShield()
                return
            }
            guard isConcealed else {
                shield?.isHidden = true
                return
            }
            if shield?.windowScene !== scene {
                removeShield()
                let shield = PrivacyShieldWindow(windowScene: scene)
                shield.backgroundColor = .systemBackground
                shield.rootViewController = UIHostingController(rootView: PrivacyScreen(isCaptured: isCaptured))
                shield.rootViewController?.view.accessibilityViewIsModal = true
                self.shield = shield
            }
            guard let shield else { return }
            shield.overrideUserInterfaceStyle = window?.overrideUserInterfaceStyle ?? .unspecified
            (shield.rootViewController as? UIHostingController<PrivacyScreen>)?.rootView = PrivacyScreen(isCaptured: isCaptured)
            let highestLevel = scene.windows.filter { $0 !== shield }.map(\.windowLevel.rawValue).max() ?? 0
            shield.windowLevel = UIWindow.Level(rawValue: max(UIWindow.Level.alert.rawValue, highestLevel) + 1)
            shield.frame = scene.effectiveGeometry.coordinateSpace.bounds
            // Show without becoming key or animating, before iOS snapshots the scene.
            shield.isHidden = false
            shield.rootViewController?.view.layoutIfNeeded()
        }

        func removeShield() {
            shield?.isHidden = true
            shield?.rootViewController = nil
            shield = nil
        }
    }
}

final class PrivacyShieldWindow: UIWindow {
    override var canBecomeKey: Bool { false }
}
