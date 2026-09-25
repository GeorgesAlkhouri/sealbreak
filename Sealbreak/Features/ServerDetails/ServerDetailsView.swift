import ComposableArchitecture
import Foundation
import SwiftUI

struct ServerDetailsView: View {
    let store: StoreOf<ServerDetailsFeature>

    var body: some View {
        NavigationStack {
            Form {
                Section("Target") {
                    LabeledContent("Name", value: store.profile.name)
                    LabeledContent("Origin", value: store.profile.origin)
                }

                Section("Seal status") {
                    if let status = store.status {
                        LabeledContent("Initialized") {
                            Text(booleanLabel(status.initialized))
                        }
                        LabeledContent("Seal") {
                            Text(sealLabel(status.sealed))
                        }
                        LabeledContent("Type", value: status.type)
                        LabeledContent("Threshold / shares", value: "\(status.t) / \(status.n)")
                        LabeledContent("Progress", value: "\(status.progress) / \(status.t)")
                    } else {
                        Text("Status unknown — check before sending.")
                            .foregroundStyle(.secondary)
                    }

                    Button("Check status", systemImage: "arrow.clockwise") {
                        store.send(.refreshTapped)
                    }
                    .disabled(store.isBusy)
                }

                Section("Result") {
                    if store.isBusy, let activity = store.activity {
                        ProgressView(activity)
                    }
                    Text(store.notice)
                        .font(.callout)
                }
            }
            .navigationTitle("Server details")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        store.send(.doneTapped)
                    }
                }
            }
        }
    }

    private func booleanLabel(_ value: Bool) -> LocalizedStringResource {
        value ? "Yes" : "No"
    }

    private func sealLabel(_ sealed: Bool) -> LocalizedStringResource {
        sealed ? "Sealed" : "Unsealed"
    }
}
