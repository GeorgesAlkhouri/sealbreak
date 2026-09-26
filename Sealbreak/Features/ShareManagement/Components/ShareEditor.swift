import Foundation
import SwiftUI
import UIKit

struct ShareEditor: View {
    @Binding var share: String
    @Binding var recoveryConfirmed: Bool

    let saveTitle: LocalizedStringResource
    let busy: Bool
    let onSave: () -> Void

    var body: some View {
        if !share.isEmpty {
            Label("Shamir share added", systemImage: "checkmark.circle.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(PapercutPalette.unsealed)
        }

        PasteButton(payloadType: String.self) { values in
            pasteShare(values)
        }
        .labelStyle(.titleAndIcon)
        .buttonBorderShape(.roundedRectangle(radius: 14))
        .tint(PapercutPalette.button)
        .controlSize(.large)
        .disabled(busy)

        Toggle("I have an independent recovery copy", isOn: $recoveryConfirmed)

        Button(saveTitle, action: onSave)
            .disabled(busy || share.isEmpty || !recoveryConfirmed)
    }

    private func pasteShare(_ values: [String]) {
        guard let candidate = values.first,
              let validated = try? ShareRecord.validateShare(candidate) else {
            return
        }

        share.removeAll(keepingCapacity: false)
        share = validated
        UIPasteboard.general.items = []
    }
}
