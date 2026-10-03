import ComposableArchitecture
import Foundation
import SealbreakCore
import SwiftUI

struct ServerDetailsView: View {
    let store: StoreOf<ServerDetailsFeature>

    var body: some View {
        NavigationStack {
            Form {
                Section(LocalizedStringResource("Target", bundle: .module)) {
                    LabeledContent(LocalizedStringResource("Name", bundle: .module), value: store.profile.name)
                    LabeledContent(LocalizedStringResource("Origin", bundle: .module), value: store.profile.origin)
                }

                Section(LocalizedStringResource("Stored share", bundle: .module)) {
                    LabeledContent(LocalizedStringResource("Share", bundle: .module)) {
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
                                        Text("Hidden", bundle: .module)
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
                                ? Text("Show stored share fragment", bundle: .module)
                                : Text("Hide stored share fragment", bundle: .module)
                        )
                        .accessibilityValue(
                            store.shareFragment.map {
                                Text(verbatim: $0.displayValue)
                            } ?? Text("Hidden", bundle: .module)
                        )
                    }
                }

                Section(LocalizedStringResource("Seal status", bundle: .module)) {
                    if let status = store.status {
                        LabeledContent(LocalizedStringResource("Initialized", bundle: .module)) {
                            Text(booleanLabel(status.initialized))
                        }
                        LabeledContent(LocalizedStringResource("Seal", bundle: .module)) {
                            Text(sealLabel(status.sealed))
                        }
                        LabeledContent(LocalizedStringResource("Type", bundle: .module), value: status.type)
                        LabeledContent(LocalizedStringResource("Threshold / shares", bundle: .module), value: String(localized: "\(status.t) / \(status.n)", bundle: .module))
                        if status.sealed {
                            LabeledContent(LocalizedStringResource("Unseal progress", bundle: .module), value: String(localized: "\(status.progress) / \(status.t)", bundle: .module))
                        }
                    } else {
                        Text("Status unknown — check before sending.", bundle: .module)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(LocalizedStringResource("Server details", bundle: .module))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(LocalizedStringResource("Done", bundle: .module)) {
                        store.send(.doneTapped)
                    }
                    .disabled(store.isRevealingShare)
                }
            }
        }
    }

    private func booleanLabel(_ value: Bool) -> LocalizedStringResource {
        value ? LocalizedStringResource("Yes", bundle: .module) : LocalizedStringResource("No", bundle: .module)
    }

    private func sealLabel(_ sealed: Bool) -> LocalizedStringResource {
        sealed ? LocalizedStringResource("Sealed", bundle: .module) : LocalizedStringResource("Unsealed", bundle: .module)
    }
}
