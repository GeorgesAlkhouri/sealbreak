import SwiftUI
import UIKit

@MainActor
struct ContentView: View {
    @ObservedObject var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    @State private var name = "OpenBao"
    @State private var address = ""
    @State private var share = ""
    @State private var recoveryConfirmed = false
    @State private var editingShare = false
    @State private var confirmUnseal = false
    @State private var confirmDelete = false
    @State private var captured = UIScreen.main.isCaptured

    private var concealed: Bool {
        scenePhase != .active || captured
    }

    var body: some View {
        ZStack {
            NavigationStack {
                Form {
                    if let profile = model.profile {
                        Section("Target — fixed while a share is stored") {
                            Text(profile.name)
                                .font(.headline)
                            Text(profile.origin)
                                .font(.system(.footnote, design: .monospaced))
                                .textSelection(.enabled)

                            if let status = model.status {
                                LabeledContent("Initialized", value: status.initialized ? "Yes" : "No")
                                LabeledContent("Seal", value: status.sealed ? "Sealed" : "Unsealed")
                                LabeledContent("Type", value: status.type)
                                LabeledContent("Threshold / shares", value: "\(status.t) / \(status.n)")
                                if status.sealed {
                                    LabeledContent("Progress", value: "\(status.progress) / \(status.t)")
                                }
                            } else {
                                Text("Status unknown — check before sending.")
                                    .foregroundStyle(.secondary)
                            }

                            Button("Check status", systemImage: "arrow.clockwise", action: model.refresh)
                                .disabled(model.busy)
                        }

                        Section {
                            Button("Unseal with Face ID", systemImage: "faceid") {
                                confirmUnseal = true
                            }
                            .disabled(!model.canUnseal)
                        } footer: {
                            Text("Sends exactly one locally stored share to the displayed HTTPS origin. No automatic unseal.")
                        }

                        Section("Local share") {
                            Button(editingShare ? "Cancel replacement" : "Replace share") {
                                clearDraft()
                                editingShare.toggle()
                            }
                            .disabled(model.busy)

                            if editingShare {
                                secretEditor(replacing: true)
                            }
                        }
                    } else {
                        Section {
                            TextField("Server name", text: $name)
                            TextField("https://bao.example.com:8200", text: $address)
                                .keyboardType(.URL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            secretEditor(replacing: false)
                        } header: {
                            Text("Add one OpenBao node")
                        } footer: {
                            Text("Configure the direct HTTPS origin of one node, not a load balancer distributing requests among nodes. The server must be initialized separately.")
                        }
                    }

                    Section("Recovery and local data") {
                        Button("Restore profile from Keychain", action: model.restoreProfile)
                            .disabled(model.busy)
                        Button("Remove local data", role: .destructive) {
                            confirmDelete = true
                        }
                        .disabled(model.busy)
                        Text("Keep an independent recovery copy. Face ID changes, device loss, or passcode removal can make the saved share inaccessible. Deleting the app is not a reliable Keychain wipe.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Section("Result") {
                        if model.busy {
                            ProgressView(model.activity)
                        }
                        Text(model.notice)
                            .font(.callout)
                    }
                }
                .navigationTitle("Sealbreak")
                .disabled(captured)
                .confirmationDialog(
                    "Send a share to this target?",
                    isPresented: $confirmUnseal,
                    titleVisibility: .visible
                ) {
                    Button("Authorize with Face ID") {
                        clearDraft()
                        model.unseal()
                    }
                } message: {
                    Text("\(model.profile?.origin ?? "")\nA trusted certificate does not prove the server is uncompromised. Only proceed when you trust this node and any TLS proxy.")
                }
                .confirmationDialog(
                    "Remove the local share?",
                    isPresented: $confirmDelete,
                    titleVisibility: .visible
                ) {
                    Button("I have recovery — remove local data", role: .destructive) {
                        clearDraft()
                        editingShare = false
                        model.removeLocalData()
                    }
                } message: {
                    Text("Requires fresh Face ID. This cannot be undone and does not revoke copies elsewhere. After Face ID changes, removal deletes any remaining old record; it cannot recover that record.")
                }
            }
            if concealed {
                Color(.systemBackground)
                    .ignoresSafeArea()
                VStack(spacing: 12) {
                    Image(systemName: "lock.shield")
                        .font(.largeTitle)
                    Text(captured ? "Stop screen capture to continue" : "Sealbreak locked")
                }
                .accessibilityElement(children: .combine)
            }
        }
        .onAppear {
            if scenePhase == .active, model.profile != nil {
                model.refresh()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                clearDraft()
            }
            if phase == .background {
                model.cancelForPrivacy()
            }
            if phase == .active, model.profile != nil, !model.busy {
                model.refresh()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIScreen.capturedDidChangeNotification)) { _ in
            captured = UIScreen.main.isCaptured
            if captured {
                clearDraft()
                model.cancelForPrivacy()
            }
        }
        .onChange(of: model.profile) { _, _ in
            clearDraft()
            editingShare = false
        }
        .onChange(of: model.busy) { wasBusy, busy in
            if wasBusy && !busy {
                clearDraft()
                editingShare = false
            }
        }
    }

    @ViewBuilder
    private func secretEditor(replacing: Bool) -> some View {
        SecureField("One Shamir share", text: $share)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.asciiCapable)
            .privacySensitive()
            .onChange(of: share) { _, value in
                if value.utf8.count > 1024 {
                    share = ""
                }
            }

        Toggle("I have an independent recovery copy", isOn: $recoveryConfirmed)

        Text("Paste is explicit. Existing clipboard/password-manager copies cannot be erased by this app. The share is never displayed or exported after saving.")
            .font(.footnote)
            .foregroundStyle(.secondary)

        Button(replacing ? "Save replacement with Face ID" : "Save share with Face ID") {
            let value = share
            let recovery = recoveryConfirmed
            clearDraft()
            if replacing {
                model.replaceShare(input: value, recoveryConfirmed: recovery)
            } else {
                model.importShare(
                    name: name,
                    address: address,
                    input: value,
                    recoveryConfirmed: recovery
                )
            }
        }
        .disabled(model.busy || share.isEmpty || !recoveryConfirmed)
    }

    private func clearDraft() {
        share.removeAll(keepingCapacity: false)
        recoveryConfirmed = false
    }
}
