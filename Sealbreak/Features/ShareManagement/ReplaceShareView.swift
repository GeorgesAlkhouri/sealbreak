import ComposableArchitecture
import SwiftUI

struct ReplaceShareView: View {
    let store: StoreOf<ReplaceShareFeature>

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
                        busy: store.isBusy,
                        onSave: save
                    )

                    Text("This replaces only the locally stored share. It does not rotate server keys or change the configured target.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if store.isBusy || !store.notice.isEmpty {
                    Section("Result") {
                        if store.isBusy {
                            ProgressView(store.activity)
                        }
                        if !store.notice.isEmpty {
                            Text(store.notice)
                                .font(.callout)
                        }
                    }
                }
            }
            .navigationTitle("Local share")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        clearDraft()
                        store.send(.cancelTapped)
                    }
                    .disabled(store.isBusy)
                }
            }
        }
        .clearSensitiveDraftOnPrivacyChange(clearDraft)
    }

    private func save() {
        let value = share
        let recovery = recoveryConfirmed
        clearDraft()
        store.send(.saveTapped(share: value, recoveryConfirmed: recovery))
    }

    private func clearDraft() {
        share.removeAll(keepingCapacity: false)
        recoveryConfirmed = false
    }
}
