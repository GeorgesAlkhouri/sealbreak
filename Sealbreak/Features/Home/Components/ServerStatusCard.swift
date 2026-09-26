import SwiftUI

struct ServerStatusCard: View {
    let state: HomeViewState
    let onShareStatusTap: () -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var statusTitleSize: CGFloat = 40
    @ScaledMetric(relativeTo: .largeTitle) private var workingStatusTitleSize: CGFloat = 34

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

                Spacer(minLength: 18)

                SealStatusIndicator(status: state.status)

                Spacer(minLength: 10)

                Text(state.status.title)
                    .font(.system(size: currentStatusTitleSize, weight: .bold))
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

                Rectangle()
                    .fill(PapercutPalette.ring.opacity(0.8))
                    .frame(height: 1)
                    .padding(.top, 22)

                Button(action: onShareStatusTap) {
                    HStack(spacing: 9) {
                        Image(systemName: state.shareIsVerified ? "checkmark.seal.fill" : "key.horizontal")
                            .font(.subheadline)
                            .foregroundStyle(state.shareIsVerified ? PapercutPalette.unsealed : PapercutPalette.secondaryText)
                        Text("Share saved")
                            .foregroundStyle(PapercutPalette.cream)
                        Text(verbatim: "·")
                            .foregroundStyle(PapercutPalette.secondaryText)
                        Text(state.shareVerificationLabel)
                            .foregroundStyle(state.shareIsVerified ? PapercutPalette.unsealed : PapercutPalette.secondaryText)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(PapercutPalette.secondaryText)
                    }
                    .font(.caption.weight(.medium))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Open server details")
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 460)
        .accessibilityElement(children: .contain)
    }

    private var currentStatusTitleSize: CGFloat {
        if case .unsealing = state.status {
            return workingStatusTitleSize
        }
        return statusTitleSize
    }
}
