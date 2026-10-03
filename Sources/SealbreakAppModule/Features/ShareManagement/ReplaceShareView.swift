import ComposableArchitecture
import Foundation
import SealbreakCore
import SwiftUI

struct ReplaceShareView: View {
    let store: StoreOf<ReplaceShareFeature>

    @State private var share = ""
    @State private var recoveryConfirmed = false

    var body: some View {
        NavigationStack {
            Form {
                Section(LocalizedStringResource("Replace local share", bundle: .module)) {
                    ShareEditor(
                        share: $share,
                        recoveryConfirmed: $recoveryConfirmed,
                        saveTitle: LocalizedStringResource("Save replacement with Face ID", bundle: .module),
                        busy: store.isBusy,
                        onSave: save
                    )

                    Text("This replaces only the locally stored share. It does not rotate server keys or change the configured target.", bundle: .module)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if store.isBusy || store.feedback != nil {
                    Section(LocalizedStringResource("Result", bundle: .module)) {
                        if store.isBusy, let activity = store.activity {
                            ProgressView(activity)
                        }
                        if let feedback = store.feedback {
                            PapercutFeedback(feedback: feedback)
                        }
                    }
                }
            }
            .navigationTitle(LocalizedStringResource("Local share", bundle: .module))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(LocalizedStringResource("Cancel", bundle: .module)) {
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
