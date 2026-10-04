import ComposableArchitecture
import Foundation
import SealbreakCore
import SwiftUI
import UIKit

struct InstanceSetupView: View {
    let store: StoreOf<InstanceSetupFeature>

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 10) {
                Text("Connect your instance", bundle: .module)
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .foregroundStyle(PapercutPalette.cream)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Enter the direct HTTPS address of one server node.", bundle: .module)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(PapercutPalette.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 310)
            }

            PapercutCard {
                VStack(alignment: .leading, spacing: 18) {
                    setupField(
                        title: LocalizedStringResource("Name", bundle: .module),
                        prompt: LocalizedStringResource("Server", bundle: .module),
                        text: nameBinding,
                        keyboardType: .default,
                        error: store.nameValidationError
                    )

                    setupField(
                        title: LocalizedStringResource("Server address", bundle: .module),
                        prompt: LocalizedStringResource("HTTPS origin with optional port", bundle: .module),
                        text: addressBinding,
                        keyboardType: .URL,
                        error: store.addressValidationError
                    )

                    if store.isCheckingConnection
                        || store.dnssecStatus != nil
                        || store.checkedProfile != nil
                        || store.feedback != nil {
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

            Text("Sealbreak checks the server using normal iOS certificate validation. DNSSEC is reported separately when the hostname can be validated.", bundle: .module)
                .font(.caption)
                .foregroundStyle(PapercutPalette.secondaryText.opacity(0.9))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 325)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 32)
        .padding(.horizontal, 24)
        .padding(.bottom, 140)
    }

    @ViewBuilder
    private var connectionStatus: some View {
        VStack(alignment: .leading, spacing: 12) {
            if store.isCheckingConnection {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(PapercutPalette.cream)

                    Text("Checking connection…", bundle: .module)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PapercutPalette.cream)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if store.checkedProfile != nil {
                statusRow(
                    icon: "checkmark.circle.fill",
                    text: LocalizedStringResource("HTTPS certificate valid", bundle: .module),
                    color: PapercutPalette.unsealed
                )

                statusRow(
                    icon: "checkmark.circle.fill",
                    text: LocalizedStringResource("Server reachable", bundle: .module),
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

            if let feedback = store.feedback {
                PapercutFeedback(feedback: feedback)
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
                text: LocalizedStringResource("DNSSEC validated", bundle: .module),
                color: PapercutPalette.unsealed
            )
        case .insecure:
            statusRow(
                icon: "info.circle.fill",
                text: LocalizedStringResource("DNSSEC not secured", bundle: .module),
                color: PapercutPalette.secondaryText
            )
        case .bogus:
            statusRow(
                icon: "xmark.circle.fill",
                text: LocalizedStringResource("DNSSEC validation failed", bundle: .module),
                color: PapercutPalette.sealed
            )
        case .indeterminate:
            statusRow(
                icon: "questionmark.circle.fill",
                text: LocalizedStringResource("DNSSEC status indeterminate", bundle: .module),
                color: PapercutPalette.secondaryText
            )
        case .notApplicable:
            statusRow(
                icon: "minus.circle.fill",
                text: LocalizedStringResource("DNSSEC not applicable", bundle: .module),
                color: PapercutPalette.secondaryText
            )
        case .unavailable:
            statusRow(
                icon: "questionmark.circle.fill",
                text: LocalizedStringResource("DNSSEC could not be checked", bundle: .module),
                color: PapercutPalette.secondaryText
            )
        }
    }

    private func statusRow(
        icon: String,
        text: LocalizedStringResource,
        color: Color
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.system(size: 17, weight: .semibold))

            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PapercutPalette.cream)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var primaryButtonTitle: LocalizedStringResource {
        if store.canContinue {
            return LocalizedStringResource("Continue", bundle: .module)
        }
        return LocalizedStringResource("Check connection", bundle: .module)
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
                Image(
                    systemName: store.canContinue
                        ? "arrow.right.circle.fill"
                        : "checkmark.shield.fill"
                )
                .font(.system(size: 20, weight: .semibold))

                Text(primaryButtonTitle)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .papercutPrimaryButtonAppearance()
        }
        .buttonStyle(.plain)
        .accessibilityValue(
            store.isCheckingConnection
                ? LocalizedStringResource("Checking connection…", bundle: .module)
                : LocalizedStringResource("", bundle: .module)
        )
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
        title: LocalizedStringResource,
        prompt: LocalizedStringResource,
        text: Binding<String>,
        keyboardType: UIKeyboardType,
        error: LocalizedStringResource? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(PapercutPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            TextField(
                LocalizedStringResource("", bundle: .module),
                text: text,
                prompt: Text(prompt)
                    .foregroundStyle(PapercutPalette.secondaryText.opacity(0.7))
            )
            .font(.callout.weight(.medium))
            .foregroundStyle(PapercutPalette.cream)
            .accessibilityLabel(title)
            .keyboardType(keyboardType)
            .textInputAutocapitalization(
                keyboardType == .URL ? .never : .words
            )
            .autocorrectionDisabled(keyboardType == .URL)
            .disabled(store.isCheckingConnection)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(minHeight: 50)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(PapercutPalette.sky.opacity(0.72))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(PapercutPalette.ring, lineWidth: 1)
                    }
            }

            if let error {
                Label {
                    Text(error)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(PapercutPalette.sealed)
                .fixedSize(horizontal: false, vertical: true)
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

    private func productLabel(_ product: ServerProduct) -> LocalizedStringResource {
        switch product {
        case .openBao:
            return LocalizedStringResource("OpenBao detected", bundle: .module)
        case .vault:
            return LocalizedStringResource("Vault detected", bundle: .module)
        case .generic:
            return LocalizedStringResource("Generic server response", bundle: .module)
        }
    }
}
