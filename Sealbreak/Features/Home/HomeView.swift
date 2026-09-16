import SwiftUI

struct HomeView: View {
    let state: HomeViewState
    let onAction: (HomeAction) -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                PapercutBackground()

                VStack(spacing: 0) {
                    HomeHeader(isBusy: state.isBusy, onAction: onAction)
                        .padding(.horizontal, 24)

                    Spacer(minLength: 28)

                    ServerStatusCard(state: state)
                        .frame(maxWidth: 335)
                        .padding(.horizontal, 29)

                    Spacer(minLength: 26)

                    UnsealButton(state: state.primaryAction) {
                        onAction(primaryAction)
                    }
                    .frame(maxWidth: 335)
                    .padding(.horizontal, 29)

                    if let notice = state.notice {
                        Text(notice)
                            .font(.caption)
                            .foregroundStyle(PapercutPalette.cream.opacity(0.86))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .padding(.horizontal, 38)
                            .padding(.top, 10)
                    }

                    Spacer(minLength: max(118, proxy.safeAreaInsets.bottom + 90))
                }
                .padding(.top, 10)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .background(PapercutPalette.sky)
    }

    private var primaryAction: HomeAction {
        switch state.primaryAction {
        case .unseal:
            .unsealTapped
        case .checkStatus, .working:
            .refreshTapped
        }
    }
}
