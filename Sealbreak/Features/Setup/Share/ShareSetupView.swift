import ComposableArchitecture
import SwiftUI
import UIKit

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

                        MaskedShareField(
                            share: $share,
                            busy: store.isBusy
                        )

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
        .disabled(store.isBusy || !ShareImportPreview.isValid(share))
        .opacity(
            store.isBusy || ShareImportPreview.isValid(share)
                ? 1
                : 0.5
        )
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

private struct MaskedShareField: View {
    @Binding var share: String
    let busy: Bool

    @State private var isFocused = false

    var body: some View {
        MaskedShareTextField(
            share: $share,
            isFocused: $isFocused,
            busy: busy
        )
        .privacySensitive()
        .padding(.horizontal, 14)
        .frame(height: 52)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(PapercutPalette.sky.opacity(0.72))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            isFocused
                                ? PapercutPalette.button
                                : PapercutPalette.ring,
                            lineWidth: isFocused ? 1.5 : 1
                        )
                }
        }
        .animation(.easeOut(duration: 0.16), value: isFocused)
    }
}

private struct MaskedShareTextField: UIViewRepresentable {
    @Binding var share: String
    @Binding var isFocused: Bool

    let busy: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField(frame: .zero)
        textField.delegate = context.coordinator
        textField.borderStyle = .none
        textField.backgroundColor = .clear
        textField.font = .monospacedSystemFont(
            ofSize: 16,
            weight: .semibold
        )
        textField.textColor = UIColor(PapercutPalette.cream)
        textField.tintColor = UIColor(PapercutPalette.button)
        textField.keyboardType = .asciiCapable
        textField.returnKeyType = .done
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.spellCheckingType = .no
        textField.smartDashesType = .no
        textField.smartQuotesType = .no
        textField.smartInsertDeleteType = .no
        textField.clearButtonMode = .never
        textField.isSecureTextEntry = true
        textField.attributedPlaceholder = NSAttributedString(
            string: "Paste one Shamir share",
            attributes: [
                .font: UIFont.monospacedSystemFont(
                    ofSize: 16,
                    weight: .semibold
                ),
                .foregroundColor: UIColor(
                    PapercutPalette.secondaryText.opacity(0.7)
                )
            ]
        )
        textField.addTarget(
            context.coordinator,
            action: #selector(Coordinator.editingChanged(_:)),
            for: .editingChanged
        )
        context.coordinator.updateDisplay(textField)
        return textField
    }

    func updateUIView(
        _ textField: UITextField,
        context: Context
    ) {
        context.coordinator.parent = self
        textField.isEnabled = !busy
        context.coordinator.updateDisplay(textField)
    }

    @MainActor
    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: MaskedShareTextField

        private var isEditing = false
        private var collapseAfterChange = false

        init(parent: MaskedShareTextField) {
            self.parent = parent
        }

        func updateDisplay(_ textField: UITextField) {
            guard !isEditing else {
                setText(
                    parent.share,
                    secure: true,
                    in: textField
                )
                return
            }

            if let preview = ShareImportPreview.masked(parent.share) {
                setText(
                    preview,
                    secure: false,
                    in: textField
                )
            } else {
                setText(
                    parent.share,
                    secure: true,
                    in: textField
                )
            }
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            isEditing = true
            parent.isFocused = true
            setText(
                parent.share,
                secure: true,
                in: textField
            )
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            isEditing = false
            parent.isFocused = false
            updateDisplay(textField)
        }

        func textField(
            _ textField: UITextField,
            shouldChangeCharactersIn range: NSRange,
            replacementString string: String
        ) -> Bool {
            guard let current = textField.text,
                  let swiftRange = Range(range, in: current) else {
                return false
            }

            let candidate = current.replacingCharacters(
                in: swiftRange,
                with: string
            )

            guard candidate.utf8.count <= 1024 else {
                parent.share.removeAll(keepingCapacity: false)
                textField.text = ""
                return false
            }

            collapseAfterChange =
                string.utf8.count >= 8
                && ShareImportPreview.masked(candidate) != nil

            return true
        }

        @objc
        func editingChanged(_ textField: UITextField) {
            parent.share = textField.text ?? ""

            if collapseAfterChange {
                collapseAfterChange = false
                textField.resignFirstResponder()
            }
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }

        private func setText(
            _ value: String,
            secure: Bool,
            in textField: UITextField
        ) {
            guard textField.isSecureTextEntry != secure
                    || textField.text != value else {
                return
            }

            textField.isSecureTextEntry = secure
            textField.text = value
        }
    }
}

