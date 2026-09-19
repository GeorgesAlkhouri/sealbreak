import ComposableArchitecture
import SwiftUI

struct ShareSetupView: View {
    let store: StoreOf<ShareSetupFeature>

    @State private var share = ""
    @State private var recoveryConfirmed = false

    var body: some View {
        Form {
            Section("Protect your share") {
                Text("Connected to \(store.profile.name) · \(store.profile.origin)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                ShareEditor(
                    share: $share,
                    recoveryConfirmed: $recoveryConfirmed,
                    saveTitle: "Save share with Face ID",
                    busy: store.isBusy,
                    onSave: save
                )
            }

            Section("Result") {
                if store.isBusy {
                    ProgressView(store.activity)
                }

                Text(store.notice)
                    .font(.callout)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .tint(PapercutPalette.button)
        .clearSensitiveDraftOnPrivacyChange(clearDraft)
    }

    private func save() {
        let value = share
        let recovery = recoveryConfirmed
        clearDraft()
        store.send(
            .saveTapped(
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
