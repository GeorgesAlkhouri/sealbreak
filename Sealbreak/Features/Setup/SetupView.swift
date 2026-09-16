import SwiftUI

@MainActor
struct SetupView: View {
    @ObservedObject var model: AppModel

    @State private var name = "OpenBao"
    @State private var address = ""
    @State private var share = ""
    @State private var recoveryConfirmed = false
    @State private var confirmDelete = false

    var body: some View {
        Form {
            Section("Add one OpenBao node") {
                TextField("Server name", text: $name)
                TextField("OpenBao HTTPS origin", text: $address)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                ShareEditor(
                    share: $share,
                    recoveryConfirmed: $recoveryConfirmed,
                    saveTitle: "Save share with Face ID",
                    busy: model.busy,
                    onSave: save
                )

                Text("Configure the direct HTTPS origin of one node, not a load balancer distributing requests among nodes. The server must be initialized separately.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Recovery and local data") {
                Button("Restore profile from Keychain", action: model.restoreProfile)
                    .disabled(model.busy)

                Button("Remove local data", role: .destructive) {
                    confirmDelete = true
                }
                .disabled(model.busy)

                Text("Keep an independent recovery copy. Face ID changes, device loss, or passcode removal can make the saved share inaccessible. Deleting the app is not a reliable Keychain wipe.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Result") {
                if model.busy {
                    ProgressView(model.activity)
                }
                Text(model.notice)
                    .font(.callout)
            }
        }
        .navigationTitle("Sealbreak")
        .confirmationDialog(
            "Remove the local share?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("I have recovery — remove local data", role: .destructive) {
                clearDraft()
                model.removeLocalData()
            }
        } message: {
            Text("Requires fresh Face ID. This cannot be undone and does not revoke copies elsewhere.")
        }
        .clearSensitiveDraftOnPrivacyChange(clearDraft)
        .onChange(of: model.profile) { _, _ in
            clearDraft()
        }
    }

    private func save() {
        let value = share
        let recovery = recoveryConfirmed
        clearDraft()
        model.importShare(
            name: name,
            address: address,
            input: value,
            recoveryConfirmed: recovery
        )
    }

    private func clearDraft() {
        share.removeAll(keepingCapacity: false)
        recoveryConfirmed = false
    }
}
