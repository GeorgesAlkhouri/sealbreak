import Foundation
import SwiftUI
import UIKit

struct SharePasteControl: View {
    @Binding var share: String
    @State private var pasteError: LocalizedStringResource?

    let disabled: Bool

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
            } else if share.isEmpty {
                Text("Paste Shamir share")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(PapercutPalette.secondaryText)
            } else {
                Label("Shamir share added", systemImage: "checkmark.circle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(PapercutPalette.unsealed)
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
            try applySharePaste(values.first, to: &share)
            UIPasteboard.general.items = []
        } catch {
            pasteError = normalizedAppFailure(error).resource
        }
    }
}

struct ShareEditor: View {
    @Binding var share: String
    @Binding var recoveryConfirmed: Bool

    let saveTitle: LocalizedStringResource
    let busy: Bool
    let onSave: () -> Void

    var body: some View {
        SharePasteControl(
            share: $share,
            disabled: busy
        )

        Toggle("I have an independent recovery copy", isOn: $recoveryConfirmed)

        Button(saveTitle, action: onSave)
            .disabled(busy || share.isEmpty || !recoveryConfirmed)
    }
}
