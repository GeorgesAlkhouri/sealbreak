import SwiftUI

@MainActor
struct ReplaceShareView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var share = ""
    @State private var recoveryConfirmed = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Replace local share") {
                    ShareEditor(
                        share: $share,
                        recoveryConfirmed: $recoveryConfirmed,
                        saveTitle: "Save replacement with Face ID",
                        busy: model.busy,
                        onSave: save
                    )

                    Text("This replaces only the locally stored share. It does not rotate OpenBao keys or change the configured target.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Local share")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        clearDraft()
                        dismiss()
                    }
                }
            }
        }
        .clearSensitiveDraftOnPrivacyChange(clearDraft)
        .onChange(of: model.busy) { wasBusy, busy in
            if wasBusy && !busy {
                clearDraft()
                dismiss()
            }
        }
    }

    private func save() {
        let value = share
        let recovery = recoveryConfirmed
        clearDraft()
        model.replaceShare(input: value, recoveryConfirmed: recovery)
    }

    private func clearDraft() {
        share.removeAll(keepingCapacity: false)
        recoveryConfirmed = false
    }
}
