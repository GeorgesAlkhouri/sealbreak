import ComposableArchitecture
import SwiftUI

struct SetupView: View {
    let store: StoreOf<SetupFeature>

    @State private var name = "OpenBao"
    @State private var address = ""
    @State private var share = ""
    @State private var recoveryConfirmed = false

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
                    busy: store.isBusy,
                    onSave: save
                )

                Text("Configure the direct HTTPS origin of one node, not a load balancer distributing requests among nodes. The server must be initialized separately.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Recovery and local data") {
                Button("Restore profile from Keychain") {
                    store.send(.restoreProfileTapped)
                }
                .disabled(store.isBusy)

                Button("Remove local data", role: .destructive) {
                    store.send(.removeLocalDataTapped)
                }
                .disabled(store.isBusy)

                Text("Keep an independent recovery copy. Face ID changes, device loss, or passcode removal can make the saved share inaccessible. Deleting the app is not a reliable Keychain wipe.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Result") {
                if store.isBusy {
                    ProgressView(store.activity)
                }
                Text(store.notice)
                    .font(.callout)
            }
        }
        .navigationTitle("Sealbreak")
        .confirmationDialog(
            "Remove the local share?",
            isPresented: confirmationBinding,
            titleVisibility: .visible
        ) {
            Button("I have recovery — remove local data", role: .destructive) {
                clearDraft()
                store.send(.confirmRemoveLocalDataTapped)
            }
        } message: {
            Text("Requires fresh Face ID. This cannot be undone and does not revoke copies elsewhere.")
        }
        .clearSensitiveDraftOnPrivacyChange(clearDraft)
    }

    private var confirmationBinding: Binding<Bool> {
        Binding(
            get: { store.confirmDelete },
            set: { presented in
                if !presented {
                    store.send(.confirmationDismissed)
                }
            }
        )
    }

    private func save() {
        let name = name
        let address = address
        let value = share
        let recovery = recoveryConfirmed
        clearDraft()
        store.send(
            .saveTapped(
                name: name,
                address: address,
                share: value,
                recoveryConfirmed: recovery
            )
        )
    }

    private func clearDraft() {
        share.removeAll(keepingCapacity: false)
        recoveryConfirmed = false
    }
}
