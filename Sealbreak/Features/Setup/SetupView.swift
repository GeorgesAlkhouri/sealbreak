import ComposableArchitecture
import Foundation
import SwiftUI

struct SetupView: View {
    let store: StoreOf<SetupFeature>

    @State private var confirmCancel = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                PapercutBackground()

                VStack(spacing: 0) {
                    header
                        .padding(.top, max(8, proxy.safeAreaInsets.top + 2))
                        .padding(.horizontal, 24)

                    progressIndicator
                        .padding(.top, 20)
                        .padding(.horizontal, 30)

                    switch store.step {
                    case .instance:
                        InstanceSetupView(
                            store: store.scope(
                                state: \.instance,
                                action: \.instance
                            )
                        )

                    case .share:
                        if let shareStore = store.scope(
                            state: \.share,
                            action: \.share
                        ) {
                            ShareSetupView(store: shareStore)
                        }
                    }
                }
            }
        }
        .background(PapercutPalette.sky)
        .toolbar(.hidden, for: .navigationBar)
        .confirmationDialog(
            "Discard setup?",
            isPresented: $confirmCancel,
            titleVisibility: .visible
        ) {
            Button("Discard setup", role: .destructive) {
                store.send(.cancelTapped)
            }
            .disabled(store.blocksSetupExit)

            Button("Keep setting up", role: .cancel) {
                // The cancel role dismisses the confirmation dialog without changing setup state.
            }
        } message: {
            Text("Your current setup entries will not be saved.")
        }
    }

    private var header: some View {
        HStack {
            Group {
                if store.step == .share {
                    Button {
                        store.send(.backTapped)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .bold))
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Back")
                    .disabled(store.blocksSetupExit)
                } else {
                    Color.clear
                        .frame(width: 44, height: 44)
                }
            }
            .foregroundStyle(PapercutPalette.cream)

            Spacer()

            Text("Setup")
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(PapercutPalette.cream)

            Spacer()

            Button("Cancel") {
                if hasDraft {
                    confirmCancel = true
                } else {
                    store.send(.cancelTapped)
                }
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(PapercutPalette.secondaryText)
            .frame(minWidth: 44, minHeight: 44)
            .disabled(store.blocksSetupExit)
        }
    }

    private var progressIndicator: some View {
        HStack(spacing: 10) {
            progressStep(
                number: 1,
                title: "Instance",
                active: store.step == .instance,
                complete: store.step == .share
            )

            Capsule()
                .fill(
                    store.step == .share
                        ? PapercutPalette.button
                        : PapercutPalette.ring
                )
                .frame(height: 2)

            progressStep(
                number: 2,
                title: "Share",
                active: store.step == .share,
                complete: false
            )
        }
        .frame(maxWidth: 335)
    }

    private func progressStep(
        number: Int,
        title: LocalizedStringResource,
        active: Bool,
        complete: Bool
    ) -> some View {
        HStack(spacing: 7) {
            ZStack {
                Circle()
                    .fill(
                        active || complete
                            ? PapercutPalette.button
                            : PapercutPalette.card
                    )

                if complete {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                } else {
                    Text(verbatim: String(number))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                }
            }
            .foregroundStyle(PapercutPalette.cream)
            .frame(width: 24, height: 24)

            Text(title)
                .font(.system(size: 13, weight: active ? .bold : .semibold))
                .foregroundStyle(
                    active || complete
                        ? PapercutPalette.cream
                        : PapercutPalette.secondaryText
                )
        }
        .fixedSize()
    }

    private var hasDraft: Bool {
        store.step == .share || store.instance.hasDraft
    }
}
