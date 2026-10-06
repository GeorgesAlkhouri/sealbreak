import Foundation
import SealbreakCore
import SwiftUI
import UIKit

struct SharePasteControl: View {
    let disabled: Bool
    let onPaste: (Result<String, AppFailure>) -> Void

    var body: some View {
        PasteButton(payloadType: String.self) { values in
            importShare(values)
        }
        .labelStyle(.titleAndIcon)
        .font(.headline)
        .papercutPrimaryButtonAppearance()
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
    }

    private func importShare(_ values: [String]) {
        do {
            var share = try validatedSharePaste(values.first)
            defer {
                share.removeAll(keepingCapacity: false)
            }

            UIPasteboard.general.items = []
            onPaste(.success(share))
        } catch {
            onPaste(.failure(normalizedAppFailure(error)))
        }
    }
}
