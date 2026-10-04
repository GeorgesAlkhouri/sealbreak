import ComposableArchitecture
import Foundation
import SealbreakCore
import SwiftUI

struct HomeView: View {
    @Bindable var store: StoreOf<HomeFeature>
    let privacyStore: StoreOf<PrivacyFeature>

    @State private var statusInteractionTrigger = 0

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                PapercutBackground()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        HomeHeader(isBusy: viewState.isBusy) { action in
                            switch action {
                            case .refresh:
                                statusInteractionTrigger += 1
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

                        ServerStatusCard(
                            state: viewState,
                            interactionTrigger: statusInteractionTrigger
                        )
                            .frame(maxWidth: 335)
                            .padding(.horizontal, 29)

                        Spacer(minLength: 26)

                        UnsealButton(state: viewState.primaryAction) {
                            switch viewState.primaryAction {
                            case .unseal:
                                statusInteractionTrigger += 1
                                store.send(.unsealTapped)
                            case .checkStatus:
                                statusInteractionTrigger += 1
                                store.send(.refreshTapped)
                            case .working:
                                break
                            }
                        }
                        .frame(maxWidth: 335)
                        .padding(.horizontal, 29)

                        if let feedback = viewState.feedback {
                            PapercutFeedback(feedback: feedback)
                                .frame(maxWidth: 335)
                                .padding(.horizontal, 29)
                                .padding(.top, 10)
                        }

                        Spacer(minLength: max(118, proxy.safeAreaInsets.bottom + 90))
                    }
                    .padding(.top, 10)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: proxy.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
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
            .interactiveDismissDisabled(detailsStore.isRevealingShare)
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
                Button(LocalizedStringResource("Send one share", bundle: .module), role: .destructive) {
                    store.send(.confirmUnsealTapped)
                }
            case .removeLocalData:
                Button(LocalizedStringResource("Remove local data", bundle: .module), role: .destructive) {
                    store.send(.confirmRemoveLocalDataTapped)
                }
            case nil:
                EmptyView()
            }
        } message: {
            switch store.confirmation {
            case .unseal:
                Text("Face ID will be required. Sealbreak will re-check the target before sending anything.", bundle: .module)
            case .removeLocalData:
                Text("This removes the local Keychain share and display profile. Independent recovery will be required to restore access.", bundle: .module)
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
            feedback: store.feedback
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

    private var confirmationTitle: LocalizedStringResource {
        switch store.confirmation {
        case .unseal:
            return LocalizedStringResource("Send one Shamir share?", bundle: .module)
        case .removeLocalData:
            return LocalizedStringResource("Remove local data?", bundle: .module)
        case nil:
            return LocalizedStringResource("Confirm", bundle: .module)
        }
    }
}

#Preview("Home — Sealed") {
    if let profile = try? ServerProfile(
        id: UUID(),
        name: "Production OpenBao",
        address: "https://bao.example.com:8200",
        product: .openBao
    ) {
        let status = SealStatus(
            type: "shamir",
            initialized: true,
            sealed: true,
            t: 3,
            n: 5,
            progress: 1,
            migration: false,
            recoverySeal: false
        )

        let privacyState: PrivacyFeature.State = {
            var state = PrivacyFeature.State()
            state.phase = .active
            return state
        }()

        NavigationStack {
            HomeView(
                store: Store(
                    initialState: HomeFeature.State(
                        profile: profile,
                        status: status
                    )
                ) {
                    HomeFeature()
                } withDependencies: {
                    $0.sealbreakClient = .unimplemented
                },
                privacyStore: Store(initialState: privacyState) {
                    PrivacyFeature()
                }
            )
        }
    } else {
        Text(verbatim: "Preview fixture unavailable")
    }
}
