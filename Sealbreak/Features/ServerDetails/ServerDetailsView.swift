import SwiftUI

@MainActor
struct ServerDetailsView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if let profile = model.profile {
                    Section("Target") {
                        LabeledContent("Name", value: profile.name)
                        LabeledContent("Origin", value: profile.origin)
                    }
                }

                Section("Seal status") {
                    if let status = model.status {
                        LabeledContent("Initialized", value: status.initialized ? "Yes" : "No")
                        LabeledContent("Seal", value: status.sealed ? "Sealed" : "Unsealed")
                        LabeledContent("Type", value: status.type)
                        LabeledContent("Threshold / shares", value: "\(status.t) / \(status.n)")
                        LabeledContent("Progress", value: "\(status.progress) / \(status.t)")
                    } else {
                        Text("Status unknown — check before sending.")
                            .foregroundStyle(.secondary)
                    }

                    Button("Check status", systemImage: "arrow.clockwise", action: model.refresh)
                        .disabled(model.busy)
                }

                Section("Result") {
                    if model.busy {
                        ProgressView(model.activity)
                    }
                    Text(model.notice)
                        .font(.callout)
                }
            }
            .navigationTitle("Server details")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
