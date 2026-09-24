import SwiftUI

struct ServerStatusCard: View {
    let state: HomeViewState

    var body: some View {
        PapercutCard {
            VStack(spacing: 0) {
                Text(verbatim: state.serverName)
                    .font(.system(size: 25, weight: .bold))
                    .foregroundStyle(PapercutPalette.cream)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(maxWidth: .infinity, alignment: .center)

                Text(verbatim: state.origin)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(PapercutPalette.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 4)

                Spacer(minLength: 18)

                SealStatusIndicator(status: state.status)

                Spacer(minLength: 10)

                Text(state.status.title)
                    .font(.system(size: state.status.prefersCompactTitle ? 34 : 40, weight: .bold))
                    .foregroundStyle(SealStatusIndicator(status: state.status).accent)
                    .shadow(color: .black.opacity(0.28), radius: 4, y: 4)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(maxWidth: .infinity, alignment: .center)

                Text(state.status.primaryDetail)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(PapercutPalette.cream)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 7)

                Text(state.status.secondaryDetail)
                    .font(.system(size: 15))
                    .foregroundStyle(PapercutPalette.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 8)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
        }
        .frame(height: 460)
        .accessibilityElement(children: .combine)
    }
}
