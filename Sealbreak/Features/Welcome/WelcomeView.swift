import ComposableArchitecture
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
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(PapercutPalette.cream)
                            .padding(.top, 12)

                        Text("Keep one Shamir unseal share protected on this iPhone.")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(PapercutPalette.cream.opacity(0.94))
                            .multilineTextAlignment(.center)
                            .padding(.top, 16)
                            .frame(maxWidth: 310)

                        compatibilityCopy
                            .font(.system(size: 15, weight: .medium))
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .padding(.top, 12)
                            .frame(maxWidth: 320)
                            .accessibilityLabel(
                                "Works with OpenBao, Vault, and compatible Shamir seal servers."
                            )

                        if let notice = store.notice {
                            Text(notice)
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(PapercutPalette.cream)
                                .multilineTextAlignment(.center)
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

                        VStack(spacing: 14) {
                            Button {
                                store.send(.setUpTapped)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 22, weight: .semibold))

                                    Text("Set up Sealbreak")
                                        .font(.system(size: 19, weight: .bold))
                                }
                                .foregroundStyle(PapercutPalette.cream)
                                .frame(maxWidth: .infinity)
                                .frame(height: 68)
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
                            .buttonStyle(.plain)

                            Button {
                                store.send(.restoreTapped)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "key.fill")
                                    Text("Restore existing setup")
                                        .fontWeight(.semibold)
                                }
                                .font(.system(size: 17))
                                .foregroundStyle(PapercutPalette.cream)
                                .frame(maxWidth: .infinity)
                                .frame(height: 54)
                                .background {
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .fill(PapercutPalette.card)
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                                .stroke(PapercutPalette.ring, lineWidth: 1)
                                        }
                                }
                                .shadow(color: .black.opacity(0.24), radius: 6, y: 6)
                            }
                            .buttonStyle(.plain)
                        }
                        .frame(maxWidth: 335)

                        Spacer()
                            .frame(height: max(156, proxy.safeAreaInsets.bottom + 130))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: proxy.size.height, alignment: .top)
                    .padding(.horizontal, 24)
                }
                .scrollIndicators(.hidden)
            }
        }
        .background(PapercutPalette.sky)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var compatibilityCopy: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Text("Works with")
                compatibilityProduct(icon: "OpenBaoMark", name: "OpenBao")
                Text("and")
                compatibilityProduct(icon: "VaultMark", name: "Vault", tint: vaultBrand)
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

            Text(name)
        }
    }

    private var vaultBrand: Color {
        Color(red: 1, green: 207 / 255, blue: 37 / 255)
    }
}

#Preview {
    NavigationStack {
        WelcomeView(
            store: Store(initialState: WelcomeFeature.State()) {
                WelcomeFeature()
            }
        )
    }
}
