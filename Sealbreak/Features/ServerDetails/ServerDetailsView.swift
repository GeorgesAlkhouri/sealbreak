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

                Section {
                    LabeledContent("Status") {
                        if store.verification == nil {
                            Text("Not verified")
                        } else {
                            Text("Verified")
                        }
                    }

                    if let verification = store.verification {
                        LabeledContent("Verified by") {
                            if verification.source == .manual {
                                Text("You")
                            } else {
                                Text("Unseal")
                            }
                        }
                        LabeledContent("Date") {
                            Text(verification.at, format: .dateTime.day().month().year().hour().minute())
                        }
                    }

                    if store.verification == nil {
                        Button("Mark as verified") {
                            store.send(.verificationTapped)
                        }
                        .disabled(store.isBusy || store.isSavingVerification)
                    } else {
                        Button("Remove verification") {
                            store.send(.verificationTapped)
                        }
                        .disabled(store.isBusy || store.isSavingVerification)
                    }

                    if store.isSavingVerification {
                        ProgressView()
                    }
                    if let error = store.verificationError {
                        Text(error)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Stored share")
                } footer: {
                    switch store.verification?.source {
                    case .manual:
                        Text("Marked by you after an independent check.")
                    case .unseal:
                        Text("Verified after this server reported unsealed in response to the stored share.")
                    case nil:
                        Text("Compare with an independent copy, or verify by unsealing this server.")
                    }
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
                    .disabled(store.isSavingVerification)
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
