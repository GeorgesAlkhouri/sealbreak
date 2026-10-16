import SealbreakCore
import SwiftUI

struct ServerStatusCard: View {
  let state: HomeViewState
  let interactionTrigger: Int

  @ScaledMetric(relativeTo: .largeTitle) private var statusTitleSize: CGFloat = 40

  var body: some View {
    PapercutCard {
      VStack(spacing: 0) {
        Text(verbatim: state.serverName)
          .font(.title2.bold())
          .foregroundStyle(PapercutPalette.cream)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .center)

        Text(verbatim: state.origin)
          .font(.subheadline.weight(.medium))
          .foregroundStyle(PapercutPalette.secondaryText)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .center)
          .padding(.top, 4)
          .padding(.bottom, 18)

        SealStatusIndicator(
          status: state.status,
          interactionTrigger: interactionTrigger
        )
        .padding(.bottom, 10)

        Text(state.status.title)
          .font(.system(size: statusTitleSize, weight: .bold))
          .contentTransition(.opacity)
          .animation(.easeInOut(duration: 0.24), value: state.status)
          .foregroundStyle(SealStatusIndicator(status: state.status).accent)
          .shadow(color: .black.opacity(0.28), radius: 4, y: 4)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .center)

        Text(state.status.primaryDetail)
          .font(.body.weight(.medium))
          .foregroundStyle(PapercutPalette.cream)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .center)
          .padding(.top, 7)

        Text(state.status.secondaryDetail)
          .font(.subheadline)
          .foregroundStyle(PapercutPalette.secondaryText)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .center)
          .padding(.top, 8)
      }
      .multilineTextAlignment(.center)
      .padding(.horizontal, 24)
      .padding(.vertical, 28)
      .frame(minHeight: 460)
    }
    // The card's decorative shapes must not absorb space released by feedback.
    // Let its content grow for Dynamic Type, while preserving its intrinsic height.
    .fixedSize(horizontal: false, vertical: true)
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .combine)
  }
}
