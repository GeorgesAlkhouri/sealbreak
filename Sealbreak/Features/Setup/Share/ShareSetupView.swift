import ComposableArchitecture
import SwiftUI

struct ShareSetupView: View {
    let store: StoreOf<ShareSetupFeature>

    @State private var share = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 10) {
                    Text("Protect your share")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(PapercutPalette.cream)
                        .multilineTextAlignment(.center)

                    Text("Store one Shamir share on this iPhone.")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(PapercutPalette.secondaryText)
                        .multilineTextAlignment(.center)
                }

                targetCard

                PapercutCard {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Unseal share")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(PapercutPalette.secondaryText)

                        SecureField(
                            "Paste one Shamir share",
                            text: $share
                        )
                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
                        .foregroundStyle(PapercutPalette.cream)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .privacySensitive()
                        .disabled(store.isBusy)
                        .padding(.horizontal, 14)
                        .frame(height: 52)
                        .background {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(PapercutPalette.sky.opacity(0.72))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(PapercutPalette.ring, lineWidth: 1)
                                }
                        }
                        .onChange(of: share) { _, value in
                            if value.utf8.count > 1024 {
                                share.removeAll(keepingCapacity: false)
                            }
                        }

                        Divider()
                            .overlay(PapercutPalette.ring)

                        securityNote(
                            icon: "lock.iphone",
                            title: "Stored only on this iPhone",
                            detail: "Protected by Face ID and the device-bound Keychain. It is not synchronized through iCloud."
                        )

                        securityNote(
                            icon: "externaldrive.badge.checkmark",
                            title: "Keep an independent recovery copy",
                            detail: "You will need it if this iPhone is lost or Face ID is re-enrolled."
                        )
                    }
                    .padding(24)
                }
                .frame(maxWidth: 335)
                .padding(.horizontal, 6)

                protectButton
                    .frame(maxWidth: 335)
                    .padding(.horizontal, 6)

                if store.isBusy || !store.notice.isEmpty {
                    statusMessage
                        .frame(maxWidth: 325)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 32)
            .padding(.horizontal, 24)
            .padding(.bottom, 140)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .clearSensitiveDraftOnPrivacyChange(clearDraft)
    }

    private var targetCard: some View {
        PapercutCard {
            HStack(spacing: 12) {
                Image(systemName: "server.rack")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(PapercutPalette.unsealed)
                    .frame(width: 32, height: 32)
                    .background {
                        Circle()
                            .fill(PapercutPalette.sky.opacity(0.72))
                    }

                VStack(alignment: .leading, spacing: 3) {
                    Text(store.profile.name)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(PapercutPalette.cream)

                    Text("\(productLabel(store.profile.product)) · \(hostLabel)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(PapercutPalette.secondaryText)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(PapercutPalette.unsealed)
                    .font(.system(size: 18, weight: .semibold))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
        .frame(maxWidth: 335)
        .padding(.horizontal, 6)
    }

    private func securityNote(
        icon: String,
        title: String,
        detail: String
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(PapercutPalette.unsealed)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(PapercutPalette.cream)

                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(PapercutPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var protectButton: some View {
        Button(action: save) {
            HStack(spacing: 10) {
                if store.isBusy {
                    ProgressView()
                        .tint(PapercutPalette.cream)
                } else {
                    Image(systemName: "faceid")
                        .font(.system(size: 21, weight: .semibold))
                }

                Text(store.isBusy ? "Protecting…" : "Protect with Face ID")
                    .font(.system(size: 18, weight: .bold))
            }
            .foregroundStyle(PapercutPalette.cream)
            .frame(maxWidth: .infinity)
            .frame(height: 62)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 21, style: .continuous)
                        .fill(PapercutPalette.buttonBack)
                        .offset(x: 2, y: 5)

                    RoundedRectangle(cornerRadius: 21, style: .continuous)
                        .fill(PapercutPalette.button)
                }
            }
            .shadow(color: .black.opacity(0.30), radius: 8, y: 8)
        }
        .buttonStyle(.plain)
        .disabled(store.isBusy || !isShareLocallyValid)
        .opacity(store.isBusy || isShareLocallyValid ? 1 : 0.5)
    }

    @ViewBuilder
    private var statusMessage: some View {
        if store.isBusy {
            HStack(spacing: 10) {
                ProgressView()
                    .tint(PapercutPalette.cream)

                Text(store.activity)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(PapercutPalette.secondaryText)
            }
        } else {
            Text(store.notice)
                .font(.footnote)
                .foregroundStyle(PapercutPalette.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var isShareLocallyValid: Bool {
        (try? ShareRecord.validateShare(share)) != nil
    }

    private var hostLabel: String {
        URL(string: store.profile.origin)?.host ?? store.profile.origin
    }

    private func productLabel(_ product: ServerProduct) -> String {
        switch product {
        case .openBao:
            return "OpenBao"
        case .vault:
            return "Vault"
        case .generic:
            return "Compatible server"
        }
    }

    private func save() {
        let value = share
        clearDraft()
        store.send(.saveTapped(share: value))
    }

    private func clearDraft() {
        share.removeAll(keepingCapacity: false)
    }
}
