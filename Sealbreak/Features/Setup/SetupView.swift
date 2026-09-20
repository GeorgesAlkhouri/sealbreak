import ComposableArchitecture
import SwiftUI

struct SetupView: View {
    let store: StoreOf<SetupFeature>

    @State private var confirmCancel = false
    @ScaledMetric(relativeTo: .caption2) private var stepBadgeSize: CGFloat = 24

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                PapercutBackground()

                ScrollView {
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
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
                .scrollDismissesKeyboard(.interactively)
                // Start each step at the top without retaining the previous scroll offset.
                .id(store.step == .share)
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

            Button("Keep setting up", role: .cancel) {
                // The cancel role dismisses the confirmation dialog without changing setup state.
            }
        } message: {
            Text("Your current setup entries will not be saved.")
        }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                backControl
                Spacer(minLength: 8)
                headerTitle
                Spacer(minLength: 8)
                cancelButton
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    backControl
                    Spacer()
                    cancelButton
                }

                headerTitle
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .foregroundStyle(PapercutPalette.cream)
    }

    @ViewBuilder
    private var backControl: some View {
        if store.step == .share {
            Button {
                store.send(.backTapped)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .bold))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Back")
            .disabled(store.share?.isBusy == true)
        } else {
            Color.clear
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
        }
    }

    private var headerTitle: some View {
        Text("Setup")
            .font(.system(.headline, design: .rounded, weight: .bold))
            .fixedSize()
    }

    private var cancelButton: some View {
        Button("Cancel") {
            if hasDraft {
                confirmCancel = true
            } else {
                store.send(.cancelTapped)
            }
        }
        .font(.callout.weight(.semibold))
        .foregroundStyle(PapercutPalette.secondaryText)
        .fixedSize()
        .frame(minWidth: 44, minHeight: 44)
    }

    private var progressIndicator: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                instanceStep
                    .fixedSize()

                Capsule()
                    .fill(
                        store.step == .share
                            ? PapercutPalette.button
                            : PapercutPalette.ring
                    )
                    .frame(minWidth: 20)
                    .frame(height: 2)
                    .accessibilityHidden(true)

                shareStep
                    .fixedSize()
            }

            VStack(alignment: .leading, spacing: 12) {
                instanceStep
                shareStep
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: 335)
    }

    private var instanceStep: some View {
        progressStep(
            number: 1,
            title: "Instance",
            active: store.step == .instance,
            complete: store.step == .share
        )
    }

    private var shareStep: some View {
        progressStep(
            number: 2,
            title: "Share",
            active: store.step == .share,
            complete: false
        )
    }

    private func progressStep(
        number: Int,
        title: String,
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
                    Text(String(number))
                        .font(.system(.caption2, design: .rounded, weight: .bold))
                }
            }
            .foregroundStyle(PapercutPalette.cream)
            .frame(width: stepBadgeSize, height: stepBadgeSize)
            .accessibilityHidden(true)

            Text(title)
                .font(.caption.weight(active ? .bold : .semibold))
                .foregroundStyle(
                    active || complete
                        ? PapercutPalette.cream
                        : PapercutPalette.secondaryText
                )
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(number) of 2: \(title)")
        .accessibilityValue(progressState(active: active, complete: complete))
    }

    private func progressState(active: Bool, complete: Bool) -> String {
        if complete {
            return "Completed"
        }
        return active ? "Current" : "Not started"
    }

    private var hasDraft: Bool {
        store.step == .share || store.instance.hasDraft
    }
}
