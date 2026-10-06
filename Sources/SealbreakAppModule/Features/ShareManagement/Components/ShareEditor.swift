import Foundation
import SealbreakCore
import SwiftUI
import UIKit

struct SharePasteControl: View {
    @State private var pasteError: LocalizedStringResource?

    let disabled: Bool
    let onPaste: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let pasteError {
                Label {
                    Text(pasteError)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(PapercutPalette.sealed)
            } else {
                Text("Paste Shamir share", bundle: .module)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(PapercutPalette.secondaryText)
            }

            PasteButton(payloadType: String.self) { values in
                importShare(values)
            }
            .labelStyle(.titleAndIcon)
            .buttonBorderShape(.roundedRectangle(radius: 14))
            .tint(PapercutPalette.button)
            .controlSize(.large)
            .disabled(disabled)
            .frame(maxWidth: .infinity)
        }
    }

    private func importShare(_ values: [String]) {
        pasteError = nil

        do {
            var share = try validatedSharePaste(values.first)
            defer {
                share.removeAll(keepingCapacity: false)
            }

            UIPasteboard.general.items = []
            onPaste(share)
        } catch {
            pasteError = normalizedAppFailure(error).feedback.text
        }
    }
}

struct ShareEditor: View {
    @Binding var recoveryConfirmed: Bool

    let busy: Bool
    let onPaste: (String) -> Void

    var body: some View {
        Toggle(LocalizedStringResource("I have an independent recovery copy", bundle: .module), isOn: $recoveryConfirmed)

        SharePasteControl(
            disabled: busy || !recoveryConfirmed,
            onPaste: onPaste
        )
    }
}
