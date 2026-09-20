import ComposableArchitecture
import SwiftUI

struct HomeView: View {
    @Bindable var store: StoreOf<HomeFeature>
    let privacyStore: StoreOf<PrivacyFeature>

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                PapercutBackground()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        HomeHeader(isBusy: viewState.isBusy) { action in
                            switch action {
                            case .refresh:
                                store.send(.refreshTapped)
                            case .serverDetails:
                                store.send(.serverDetailsTapped)
                            case .replaceShare:
                                store.send(.replaceShareTapped)
                            case .removeLocalData:
                                store.send(.removeLocalDataTapped)
                            }
                        }
                        .padding(.horizontal, 24)

                        Spacer(minLength: 28)

                        ServerStatusCard(state: viewState)
                            .frame(maxWidth: 335)
                            .padding(.horizontal, 29)

                        Spacer(minLength: 26)

                        UnsealButton(state: viewState.primaryAction) {
                            switch viewState.primaryAction {
                            case .unseal:
                                store.send(.unsealTapped)
                            case .checkStatus, .working:
                                store.send(.refreshTapped)
                            }
                        }
                        .frame(maxWidth: 335)
                        .padding(.horizontal, 29)

                        if let notice = viewState.notice {
                            Text(notice)
                                .font(.caption)
                                .foregroundStyle(PapercutPalette.cream.opacity(0.86))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 38)
                                .padding(.top, 10)
                        }

                        Spacer(minLength: max(118, proxy.safeAreaInsets.bottom + 90))
                    }
                    .frame(minHeight: proxy.size.height)
                    .padding(.top, 10)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .background(PapercutPalette.sky)
        .sheet(
            item: $store.scope(state: \.$serverDetails, action: \.serverDetails)
        ) { detailsStore in
            PrivacyCover(store: privacyStore) {
                ServerDetailsView(store: detailsStore)
            }
        }
        .sheet(
            item: $store.scope(state: \.$replaceShare, action: \.replaceShare)
        ) { replacementStore in
            PrivacyCover(store: privacyStore) {
                ReplaceShareView(store: replacementStore)
            }
        }
        .confirmationDialog(
            confirmationTitle,
            isPresented: confirmationBinding,
            titleVisibility: .visible
        ) {
            switch store.confirmation {
            case .unseal:
                Button("Send one share", role: .destructive) {
                    store.send(.confirmUnsealTapped)
                }
            case .removeLocalData:
                Button("Remove local data", role: .destructive) {
                    store.send(.confirmRemoveLocalDataTapped)
                }
            case nil:
                EmptyView()
            }
        } message: {
            switch store.confirmation {
            case .unseal:
                Text("Face ID will be required. Sealbreak will re-check the target before sending anything.")
            case .removeLocalData:
                Text("This removes the local Keychain share and display profile. Independent recovery will be required to restore access.")
            case nil:
                EmptyView()
            }
        }
    }

    private var viewState: HomeViewState {
        HomeViewState(
            profile: store.profile,
            sealStatus: store.status,
            operation: store.operation,
            notice: store.notice
        )
    }

    private var confirmationBinding: Binding<Bool> {
        Binding(
            get: { store.confirmation != nil },
            set: { presented in
                if !presented {
                    store.send(.confirmationDismissed)
                }
            }
        )
    }

    private var confirmationTitle: String {
        switch store.confirmation {
        case .unseal:
            return "Send one Shamir share?"
        case .removeLocalData:
            return "Remove local data?"
        case nil:
            return "Confirm"
        }
    }
}
