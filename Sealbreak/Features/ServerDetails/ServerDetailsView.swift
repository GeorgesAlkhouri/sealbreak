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

                Section("Stored share") {
                    LabeledContent("Share") {
                        Button {
                            store.send(.shareFragmentTapped)
                        } label: {
                            if store.isRevealingShare {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                HStack(spacing: 8) {
                                    if let fragment = store.shareFragment {
                                        Text(verbatim: fragment.displayValue)
                                            .font(.body.monospaced())
                                    } else {
                                        Text("Hidden")
                                            .foregroundStyle(.secondary)
                                    }

                                    Image(
                                        systemName: store.shareFragment == nil
                                            ? "eye"
                                            : "eye.slash"
                                    )
                                    .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(
                            store.isRevealingShare
                                || (store.isBusy && store.shareFragment == nil)
                        )
                        .accessibilityLabel(
                            store.shareFragment == nil
                                ? Text("Show stored share fragment")
                                : Text("Hide stored share fragment")
                        )
                        .accessibilityValue(
                            store.shareFragment.map {
                                Text(verbatim: $0.displayValue)
                            } ?? Text("Hidden")
                        )
                    }
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
                }
            }
            .navigationTitle("Server details")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        store.send(.doneTapped)
                    }
                    .disabled(store.isRevealingShare)
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
