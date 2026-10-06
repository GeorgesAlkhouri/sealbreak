import ComposableArchitecture
import Foundation
import SealbreakCore
import SwiftUI

struct ReplaceShareView: View {
    let store: StoreOf<ReplaceShareFeature>

    @State private var recoveryConfirmed = false

    var body: some View {
        NavigationStack {
            Form {
                Section(LocalizedStringResource("Replace local share", bundle: .module)) {
                    ShareEditor(
                        recoveryConfirmed: $recoveryConfirmed,
                        busy: store.isBusy,
                        onPaste: replace
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
                        recoveryConfirmed = false
                        store.send(.cancelTapped)
                    }
                    .disabled(store.isBusy)
                }
            }
        }
        .clearSensitiveDraftOnPrivacyChange {
            recoveryConfirmed = false
        }
    }

    private func replace(_ share: String) {
        let recovery = recoveryConfirmed
        recoveryConfirmed = false
        store.send(.saveTapped(share: share, recoveryConfirmed: recovery))
    }
}
