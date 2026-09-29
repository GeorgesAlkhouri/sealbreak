import SwiftUI

struct SealStatusIndicator: View {
    let status: HomeViewState.Status
    let isServerActivity: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsActivity = false
    @State private var activityBecameVisibleAt: ContinuousClock.Instant?

    init(
        status: HomeViewState.Status,
        isServerActivity: Bool = false
    ) {
        self.status = status
        self.isServerActivity = isServerActivity
    }

    var body: some View {
        ZStack {
            recessedTrack

            Circle()
                .trim(from: 0, to: status.progressFraction)
                .stroke(
                    accent,
                    style: StrokeStyle(lineWidth: 18, lineCap: .round)
                )
                .padding(9)
                .rotationEffect(.degrees(-90))
                .opacity(showsActivity ? 0.16 : 1)
                .animation(.easeOut(duration: 0.14), value: showsActivity)

            if showsActivity {
                PaperActivityArc(
                    accent: activityAccent,
                    reduceMotion: reduceMotion
                )
                .transition(.opacity)
            }

            Circle()
                .fill(PapercutPalette.card)
                .frame(width: 126, height: 126)
                .shadow(color: .black.opacity(0.40), radius: 7, y: 6)

            Image(systemName: icon)
                .font(.system(size: 66, weight: .bold))
                .foregroundStyle(accent)
                .offset(x: iconHorizontalOffset)
                .shadow(color: .black.opacity(0.38), radius: 6, y: 8)
        }
        .frame(width: 170, height: 170)
        .accessibilityHidden(true)
        .task(id: isServerActivity) {
            await updateActivityVisibility()
        }
    }

    var accent: Color {
        switch status {
        case .unknown:
            return PapercutPalette.secondaryText
        case .sealed:
            return PapercutPalette.sealed
        case .unsealed:
            return PapercutPalette.unsealed
        }
    }

    private var activityAccent: Color {
        switch status {
        case .unknown:
            return PapercutPalette.button
        case .sealed, .unsealed:
            return accent
        }
    }

    private var recessedTrack: some View {
        ZStack {
            Circle()
                .fill(PapercutPalette.cardBack2)
                .shadow(color: .black.opacity(0.48), radius: 7, y: 6)

            Circle()
                .stroke(.black.opacity(0.28), lineWidth: 5)
                .blur(radius: 2)
                .offset(y: 2)

            Circle()
                .stroke(PapercutPalette.ring.opacity(0.40), lineWidth: 1)
                .offset(y: -1)

            Circle()
                .stroke(PapercutPalette.ring.opacity(0.34), lineWidth: 18)
                .padding(9)
        }
    }

    private var icon: String {
        switch status {
        case .unknown:
            return "questionmark.circle"
        case .sealed:
            return "lock.fill"
        case .unsealed:
            return "lock.open.fill"
        }
    }

    private var iconHorizontalOffset: CGFloat {
        switch status {
        case .unsealed:
            // SF Symbols centers the complete open-lock silhouette. Moving it
            // slightly right centers the visually dominant lock body in the ring.
            return 8
        case .unknown, .sealed:
            return 0
        }
    }

    private func updateActivityVisibility() async {
        let clock = ContinuousClock()

        if isServerActivity {
            activityBecameVisibleAt = clock.now
            guard !showsActivity else { return }

            withAnimation(.easeOut(duration: 0.12)) {
                showsActivity = true
            }
            return
        }

        guard showsActivity else {
            activityBecameVisibleAt = nil
            return
        }

        if let activityBecameVisibleAt {
            let earliestDismissal = activityBecameVisibleAt.advanced(by: .seconds(3))
            if clock.now < earliestDismissal {
                do {
                    try await clock.sleep(until: earliestDismissal)
                } catch {
                    return
                }
            }
        }

        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.16)) {
            showsActivity = false
        }
        activityBecameVisibleAt = nil
    }
}

private struct PaperActivityArc: View {
    let accent: Color
    let reduceMotion: Bool

    @State private var animates = false

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: 0.22)
                .stroke(
                    accent.opacity(0.42),
                    style: StrokeStyle(lineWidth: 20, lineCap: .round)
                )
                .padding(8)
                .rotationEffect(.degrees(-90))
                .offset(y: 3)
                .shadow(color: .black.opacity(0.34), radius: 4, y: 4)

            Circle()
                .trim(from: 0, to: 0.22)
                .stroke(
                    accent,
                    style: StrokeStyle(lineWidth: 18, lineCap: .round)
                )
                .padding(9)
                .rotationEffect(.degrees(-90))
                .shadow(color: accent.opacity(0.16), radius: 5)
        }
        .rotationEffect(
            .degrees(reduceMotion ? -35 : (animates ? 360 : 0))
        )
        .opacity(reduceMotion ? (animates ? 0.62 : 1) : 1)
        .onAppear {
            animates = true
        }
        .animation(
            reduceMotion
                ? .easeInOut(duration: 0.85).repeatForever(autoreverses: true)
                : .linear(duration: 1.4).repeatForever(autoreverses: false),
            value: animates
        )
    }
}
