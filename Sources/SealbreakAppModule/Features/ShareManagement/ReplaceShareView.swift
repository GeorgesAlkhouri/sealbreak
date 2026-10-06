import ComposableArchitecture
import Foundation
import SealbreakCore
import SwiftUI

struct ReplaceShareView: View {
    let store: StoreOf<ReplaceShareFeature>

    var body: some View {
        NavigationStack {
            Form {
                Section(LocalizedStringResource("Replace local share", bundle: .module)) {
                    Text("This replaces only the locally stored share. It does not rotate server keys or change the configured target.", bundle: .module)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    SharePasteControl(
                        disabled: store.isBusy,
                        onPaste: handlePaste
                    )
                    .padding(.bottom, 18)
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
                        store.send(.cancelTapped)
                    }
                    .disabled(store.isBusy)
                }
            }
        }
    }

    private func handlePaste(_ result: Result<String, AppFailure>) {
        switch result {
        case .success(let share):
            store.send(.saveTapped(share: share))
        case .failure(let failure):
            store.send(.pasteFailed(failure))
        }
    }
}
