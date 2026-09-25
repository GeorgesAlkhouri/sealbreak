import ComposableArchitecture
import Foundation
import SwiftUI

struct WelcomeView: View {
    let store: StoreOf<WelcomeFeature>

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                PapercutBackground()

                ScrollView {
                    VStack(spacing: 0) {
                        Spacer()
                            .frame(height: max(54, proxy.safeAreaInsets.top + 30))

                        Image("SealbreakShield")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 64, height: 76)
                            .accessibilityHidden(true)

                        Text("Sealbreak")
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            .foregroundStyle(PapercutPalette.cream)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 12)

                        Text("Keep one Shamir unseal share protected on this iPhone.")
                            .font(.body.weight(.medium))
                            .foregroundStyle(PapercutPalette.cream.opacity(0.94))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 16)
                            .frame(maxWidth: 310)

                        compatibilityCopy
                            .font(.subheadline.weight(.medium))
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 12)
                            .frame(maxWidth: 320)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(
                                "Works with OpenBao, Vault, and compatible Shamir seal servers."
                            )

                        if let notice = store.notice {
                            Text(notice)
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(PapercutPalette.cream)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .frame(maxWidth: 330)
                                .background {
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(PapercutPalette.card.opacity(0.92))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                                .stroke(PapercutPalette.ring, lineWidth: 1)
                                        }
                                }
                                .padding(.top, 18)
                        }

                        Spacer(minLength: 34)

                        if store.requiresLocalReset {
                            Button {
                                store.send(.resetLocalDataTapped)
                            } label: {
                                primaryActionLabel(
                                    icon: "trash.fill",
                                    title: store.isResetting
                                        ? "Resetting…"
                                        : "Reset local Sealbreak data"
                                )
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: 335)
                            .disabled(store.isResetting)
                        } else {
                            Button {
                                store.send(.setUpTapped)
                            } label: {
                                primaryActionLabel(
                                    icon: "plus.circle.fill",
                                    title: "Set up Sealbreak"
                                )
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: 335)
                        }

                        Spacer()
                            .frame(height: max(156, proxy.safeAreaInsets.bottom + 130))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: proxy.size.height, alignment: .top)
                    .padding(.horizontal, 24)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .background(PapercutPalette.sky)
        .toolbar(.hidden, for: .navigationBar)
        .confirmationDialog(
            "Reset local Sealbreak data?",
            isPresented: Binding(
                get: { store.confirmReset },
                set: { isPresented in
                    if !isPresented {
                        store.send(.resetConfirmationDismissed)
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("Reset local data", role: .destructive) {
                store.send(.confirmResetLocalDataTapped)
            }

            Button("Cancel", role: .cancel) {
                // The cancel role dismisses the confirmation without deleting data.
            }
        } message: {
            Text(
                "This removes every protected share stored by Sealbreak on this iPhone and all local Sealbreak configuration. You need an independent share copy to set up again."
            )
        }
    }

    private func primaryActionLabel(icon: String, title: LocalizedStringResource) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))

            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(PapercutPalette.cream)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 68)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(PapercutPalette.buttonBack)
                    .offset(x: 2, y: 6)

                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(PapercutPalette.button)
            }
        }
        .shadow(color: .black.opacity(0.34), radius: 9, y: 9)
    }

    private var compatibilityCopy: some View {
        VStack(spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    Text("Works with")
                    compatibilityProduct(icon: "OpenBaoMark", name: "OpenBao")
                    Text("and")
                    compatibilityProduct(icon: "VaultMark", name: "Vault", tint: vaultBrand)
                }
                .fixedSize(horizontal: true, vertical: false)

                VStack(spacing: 6) {
                    Text("Works with")
                    compatibilityProduct(icon: "OpenBaoMark", name: "OpenBao")
                    Text("and")
                    compatibilityProduct(icon: "VaultMark", name: "Vault", tint: vaultBrand)
                }
            }

            Text("and compatible Shamir seal servers.")
        }
        .foregroundStyle(PapercutPalette.secondaryText)
    }

    private func compatibilityProduct(
        icon: String,
        name: String,
        tint: Color? = nil
    ) -> some View {
        HStack(spacing: 4) {
            Image(icon)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .foregroundStyle(tint ?? PapercutPalette.secondaryText)
                .accessibilityHidden(true)

            Text(verbatim: name)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var vaultBrand: Color {
        Color(red: 1, green: 207 / 255, blue: 37 / 255)
    }
}

#Preview("Welcome") {
    NavigationStack {
        WelcomeView(
            store: Store(initialState: WelcomeFeature.State()) {
                WelcomeFeature()
            }
        )
    }
}
