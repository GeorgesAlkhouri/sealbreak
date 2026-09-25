import ComposableArchitecture
import Foundation
import SwiftUI

struct ShareSetupView: View {
    let store: StoreOf<ShareSetupFeature>

    @State private var share = ""

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 10) {
                Text("Protect your share")
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .foregroundStyle(PapercutPalette.cream)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Store one Shamir share on this iPhone.")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(PapercutPalette.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            targetCard

            PapercutCard {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Unseal share")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(PapercutPalette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    SecureField(
                        "",
                        text: $share,
                        prompt: Text("Paste one Shamir share")
                            .foregroundStyle(PapercutPalette.secondaryText)
                    )
                    .accessibilityLabel("Unseal share")
                    .font(.system(.callout, design: .monospaced, weight: .semibold))
                    .foregroundStyle(PapercutPalette.cream)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .privacySensitive()
                    .disabled(store.isBusy)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(minHeight: 52)
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

            statusMessage
                .frame(maxWidth: 325)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 32)
        .padding(.horizontal, 24)
        .padding(.bottom, 140)
        .clearSensitiveDraftOnPrivacyChange(clearDraft)
    }

    private var targetCard: some View {
        PapercutCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "server.rack")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(PapercutPalette.unsealed)
                    .frame(width: 32, height: 32)
                    .background {
                        Circle()
                            .fill(PapercutPalette.sky.opacity(0.72))
                    }

                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: store.profile.name)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(PapercutPalette.cream)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("\(Text(productLabel(store.profile.product)))\(Text(verbatim: \" · \(hostLabel)\"))")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(PapercutPalette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

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
        title: LocalizedStringResource,
        detail: LocalizedStringResource
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(PapercutPalette.unsealed)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(PapercutPalette.cream)
                    .fixedSize(horizontal: false, vertical: true)

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

                Text(protectButtonTitle)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .papercutPrimaryButtonAppearance()
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

                if let activity = store.activity {
                    Text(activity)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(PapercutPalette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else {
            Text(store.notice)
                .font(.footnote)
                .foregroundStyle(PapercutPalette.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var protectButtonTitle: LocalizedStringResource {
        store.isBusy ? "Protecting…" : "Protect with Face ID"
    }

    private var isShareLocallyValid: Bool {
        (try? ShareRecord.validateShare(share)) != nil
    }

    private var hostLabel: String {
        URL(string: store.profile.origin)?.host ?? store.profile.origin
    }

    private func productLabel(_ product: ServerProduct) -> LocalizedStringResource {
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
