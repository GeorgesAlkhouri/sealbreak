import SwiftUI

@MainActor
struct HomeContainer: View {
    @ObservedObject var model: AppModel
    @State private var destination: HomeDestination?
    @State private var confirmation: HomeConfirmation?

    var body: some View {
        HomeView(
            state: HomeViewState(model: model),
            onAction: handle
        )
        .sheet(item: $destination) { destination in
            switch destination {
            case .serverDetails:
                ServerDetailsView(model: model)
            case .replaceShare:
                ReplaceShareView(model: model)
            }
        }
        .confirmationDialog(
            confirmationTitle,
            isPresented: confirmationPresented,
            titleVisibility: .visible
        ) {
            confirmationActions
        } message: {
            Text(confirmationMessage)
        }
    }

    private var confirmationPresented: Binding<Bool> {
        Binding(
            get: { confirmation != nil },
            set: { presented in
                if !presented {
                    confirmation = nil
                }
            }
        )
    }

    private var confirmationTitle: String {
        switch confirmation {
        case .unseal:
            return "Send a share to this target?"
        case .removeLocalData:
            return "Remove the local share?"
        case nil:
            return "Confirm action"
        }
    }

    private var confirmationMessage: String {
        switch confirmation {
        case .unseal:
            return "\(model.profile?.origin ?? "")\nA trusted certificate does not prove the server is uncompromised. Only proceed when you trust this node and any TLS proxy."
        case .removeLocalData:
            return "Requires fresh Face ID. This cannot be undone and does not revoke copies elsewhere. After Face ID changes, removal deletes any remaining old record; it cannot recover that record."
        case nil:
            return ""
        }
    }

    @ViewBuilder
    private var confirmationActions: some View {
        switch confirmation {
        case .unseal:
            Button("Authorize with Face ID") {
                confirmation = nil
                model.unseal()
            }
        case .removeLocalData:
            Button("I have recovery — remove local data", role: .destructive) {
                confirmation = nil
                model.removeLocalData()
            }
        case nil:
            EmptyView()
        }
    }

    private func handle(_ action: HomeAction) {
        switch action {
        case .refreshTapped:
            model.refresh()
        case .unsealTapped:
            confirmation = .unseal
        case .serverDetailsTapped:
            destination = .serverDetails
        case .replaceShareTapped:
            destination = .replaceShare
        case .restoreProfileTapped:
            model.restoreProfile()
        case .removeLocalDataTapped:
            confirmation = .removeLocalData
        }
    }
}
