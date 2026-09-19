import ComposableArchitecture
import SwiftUI
import UIKit

struct InstanceSetupView: View {
    let store: StoreOf<InstanceSetupFeature>

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 10) {
                    Text("Connect your instance")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(PapercutPalette.cream)
                        .multilineTextAlignment(.center)

                    Text("Enter the direct HTTPS address of one server node.")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(PapercutPalette.secondaryText)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 310)
                }

                PapercutCard {
                    VStack(alignment: .leading, spacing: 18) {
                        setupField(
                            title: "Name",
                            prompt: "Server",
                            text: nameBinding,
                            keyboardType: .default
                        )

                        setupField(
                            title: "Server address",
                            prompt: "https://server.example.com:8200",
                            text: addressBinding,
                            keyboardType: .URL
                        )

                        if store.isCheckingConnection
                            || store.dnssecStatus != nil
                            || store.checkedProfile != nil
                            || store.notice != nil {
                            Divider()
                                .overlay(PapercutPalette.ring)

                            connectionStatus
                        }
                    }
                    .padding(24)
                }
                .frame(maxWidth: 335)
                .padding(.horizontal, 6)

                primaryButton
                    .frame(maxWidth: 335)
                    .padding(.horizontal, 6)

                Text("Sealbreak checks the server using normal iOS certificate validation. DNSSEC is reported separately when the hostname can be validated.")
                    .font(.caption)
                    .foregroundStyle(PapercutPalette.secondaryText.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 325)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 32)
            .padding(.horizontal, 24)
            .padding(.bottom, 140)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder
    private var connectionStatus: some View {
        VStack(alignment: .leading, spacing: 12) {
            if store.isCheckingConnection {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(PapercutPalette.cream)

                    Text("Checking connection…")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(PapercutPalette.cream)
                }
            }

            if store.checkedProfile != nil {
                statusRow(
                    icon: "checkmark.circle.fill",
                    text: "HTTPS certificate valid",
                    color: PapercutPalette.unsealed
                )

                statusRow(
                    icon: "checkmark.circle.fill",
                    text: "Server reachable",
                    color: PapercutPalette.unsealed
                )
            }

            if let dnssecStatus = store.dnssecStatus {
                dnssecRow(dnssecStatus)
            }

            if let profile = store.checkedProfile {
                statusRow(
                    icon: "checkmark.circle.fill",
                    text: productLabel(profile.product),
                    color: PapercutPalette.unsealed
                )
            }

            if let notice = store.notice {
                Text(notice)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(PapercutPalette.cream)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
    }

    @ViewBuilder
    private func dnssecRow(_ status: DNSSECStatus) -> some View {
        switch status {
        case .secure:
            statusRow(
                icon: "checkmark.circle.fill",
                text: "DNSSEC validated",
                color: PapercutPalette.unsealed
            )
        case .insecure:
            statusRow(
                icon: "info.circle.fill",
                text: "DNSSEC not secured",
                color: PapercutPalette.secondaryText
            )
        case .bogus:
            statusRow(
                icon: "xmark.circle.fill",
                text: "DNSSEC validation failed",
                color: PapercutPalette.sealed
            )
        case .indeterminate:
            statusRow(
                icon: "questionmark.circle.fill",
                text: "DNSSEC status indeterminate",
                color: PapercutPalette.secondaryText
            )
        case .notApplicable:
            statusRow(
                icon: "minus.circle.fill",
                text: "DNSSEC not applicable",
                color: PapercutPalette.secondaryText
            )
        case .unavailable:
            statusRow(
                icon: "questionmark.circle.fill",
                text: "DNSSEC could not be checked",
                color: PapercutPalette.secondaryText
            )
        }
    }

    private func statusRow(
        icon: String,
        text: String,
        color: Color
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.system(size: 17, weight: .semibold))

            Text(text)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(PapercutPalette.cream)
        }
    }

    private var primaryButton: some View {
        Button {
            if store.canContinue {
                store.send(.continueTapped)
            } else {
                store.send(.checkConnectionTapped)
            }
        } label: {
            HStack(spacing: 10) {
                if store.isCheckingConnection {
                    ProgressView()
                        .tint(PapercutPalette.cream)
                } else {
                    Image(
                        systemName: store.canContinue
                            ? "arrow.right.circle.fill"
                            : "checkmark.shield.fill"
                    )
                    .font(.system(size: 20, weight: .semibold))
                }

                Text(
                    store.isCheckingConnection
                        ? "Checking…"
                        : store.canContinue
                            ? "Continue"
                            : "Check connection"
                )
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
        .disabled(
            store.isCheckingConnection
                || (!store.canContinue && !store.canCheckConnection)
        )
        .opacity(
            store.isCheckingConnection
                || store.canContinue
                || store.canCheckConnection
                ? 1
                : 0.5
        )
    }

    private func setupField(
        title: String,
        prompt: String,
        text: Binding<String>,
        keyboardType: UIKeyboardType
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(PapercutPalette.secondaryText)

            TextField(
                "",
                text: text,
                prompt: Text(prompt)
                    .foregroundStyle(PapercutPalette.secondaryText.opacity(0.7))
            )
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(PapercutPalette.cream)
            .keyboardType(keyboardType)
            .textInputAutocapitalization(
                keyboardType == .URL ? .never : .words
            )
            .autocorrectionDisabled(keyboardType == .URL)
            .disabled(store.isCheckingConnection)
            .padding(.horizontal, 14)
            .frame(height: 50)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(PapercutPalette.sky.opacity(0.72))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(PapercutPalette.ring, lineWidth: 1)
                    }
            }
        }
    }

    private var nameBinding: Binding<String> {
        Binding(
            get: { store.name },
            set: { store.send(.nameChanged($0)) }
        )
    }

    private var addressBinding: Binding<String> {
        Binding(
            get: { store.address },
            set: { store.send(.addressChanged($0)) }
        )
    }

    private func productLabel(_ product: ServerProduct) -> String {
        switch product {
        case .openBao:
            return "OpenBao detected"
        case .vault:
            return "Vault detected"
        case .generic:
            return "Generic server response"
        }
    }
}
