import ComposableArchitecture
import Foundation
import SealbreakCore
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
            LocalizedStringResource("Discard setup?", bundle: .module),
            isPresented: $confirmCancel,
            titleVisibility: .visible
        ) {
            Button(LocalizedStringResource("Discard setup", bundle: .module), role: .destructive) {
                store.send(.cancelTapped)
            }
            .disabled(store.blocksSetupExit)

            Button(LocalizedStringResource("Keep setting up", bundle: .module), role: .cancel) {
                // The cancel role dismisses the confirmation dialog without changing setup state.
            }
        } message: {
            Text("Your current setup entries will not be saved.", bundle: .module)
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
            .accessibilityLabel(LocalizedStringResource("Back", bundle: .module))
            .disabled(store.blocksSetupExit)
        } else {
            Color.clear
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
        }
    }

    private var headerTitle: some View {
        Text("Setup", bundle: .module)
            .font(.system(.headline, design: .rounded, weight: .bold))
            .fixedSize()
    }

    private var cancelButton: some View {
        Button(LocalizedStringResource("Cancel", bundle: .module)) {
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
        .disabled(store.blocksSetupExit)
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
            title: LocalizedStringResource("Instance", bundle: .module),
            active: store.step == .instance,
            complete: store.step == .share
        )
    }

    private var shareStep: some View {
        progressStep(
            number: 2,
            title: LocalizedStringResource("Share", bundle: .module),
            active: store.step == .share,
            complete: false
        )
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
        .accessibilityLabel(Text("Step \(number) of 2: \(title)", bundle: .module))
        .accessibilityValue(progressState(active: active, complete: complete))
    }

    private func progressState(active: Bool, complete: Bool) -> LocalizedStringResource {
        if complete {
            return LocalizedStringResource("Completed", bundle: .module)
        }
        return active
            ? LocalizedStringResource("Current", bundle: .module)
            : LocalizedStringResource("Not started", bundle: .module)
    }

    private var hasDraft: Bool {
        store.step == .share || store.instance.hasDraft
    }
}

#Preview("Setup — Instance") {
    let state: SetupFeature.State = {
        var state = SetupFeature.State()
        state.instance.name = "Production OpenBao"
        state.instance.address = "https://bao.example.com:8200"
        return state
    }()

    NavigationStack {
        SetupView(
            store: Store(initialState: state) {
                SetupFeature()
            } withDependencies: {
                $0.sealbreakClient = .unimplemented
            }
        )
    }
}

#Preview("Setup — Share") {
    if let profile = try? ServerProfile(
        id: UUID(),
        name: "Production OpenBao",
        address: "https://bao.example.com:8200",
        product: .openBao
    ) {
        let state: SetupFeature.State = {
            var state = SetupFeature.State()
            state.step = .share
            state.instance.name = profile.name
            state.instance.address = profile.origin
            state.instance.checkedProfile = profile
            state.instance.dnssecStatus = .secure
            state.share = ShareSetupFeature.State(profile: profile)
            return state
        }()

        NavigationStack {
            SetupView(
                store: Store(initialState: state) {
                    SetupFeature()
                } withDependencies: {
                    $0.sealbreakClient = .unimplemented
                }
            )
        }
    } else {
        Text(verbatim: "Preview fixture unavailable")
    }
}
