import Foundation
import SwiftUI

struct ShareEditor: View {
    @Binding var share: String
    @Binding var recoveryConfirmed: Bool

    let saveTitle: LocalizedStringResource
    let busy: Bool
    let onSave: () -> Void

    var body: some View {
        SecureField("One Shamir share", text: $share)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.asciiCapable)
            .privacySensitive()
            .onChange(of: share) { _, value in
                if value.utf8.count > 1024 {
                    share = ""
                }
            }

        Toggle("I have an independent recovery copy", isOn: $recoveryConfirmed)

        Text("Paste is explicit. Existing clipboard/password-manager copies cannot be erased by this app. The share is never displayed or exported after saving.")
            .font(.footnote)
            .foregroundStyle(.secondary)

        Button(saveTitle, action: onSave)
            .disabled(busy || share.isEmpty || !recoveryConfirmed)
    }
}
