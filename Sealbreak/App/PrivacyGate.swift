import SwiftUI
import UIKit

@MainActor
struct PrivacyGate<Content: View>: View {
    @ObservedObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var captured = UIScreen.main.isCaptured

    private let content: Content

    init(model: AppModel, @ViewBuilder content: () -> Content) {
        self.model = model
        self.content = content()
    }

    private var concealed: Bool {
        scenePhase != .active || captured
    }

    var body: some View {
        ZStack {
            content
                .disabled(captured)

            if concealed {
                Color(.systemBackground)
                    .ignoresSafeArea()

                VStack(spacing: 12) {
                    Image(systemName: "lock.shield")
                        .font(.largeTitle)
                    Text(captured ? "Stop screen capture to continue" : "Sealbreak locked")
                }
                .accessibilityElement(children: .combine)
            }
        }
        .onAppear(perform: refreshIfNeeded)
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                model.cancelForPrivacy()
            }
            if phase == .active {
                refreshIfNeeded()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIScreen.capturedDidChangeNotification)) { _ in
            captured = UIScreen.main.isCaptured
            if captured {
                model.cancelForPrivacy()
            }
        }
    }

    private func refreshIfNeeded() {
        guard scenePhase == .active, model.profile != nil, !model.busy else { return }
        model.refresh()
    }
}
