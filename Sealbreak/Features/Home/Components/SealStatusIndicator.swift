import SwiftUI

struct SealStatusIndicator: View {
    let status: HomeViewState.Status
    let isServerActivity: Bool
    let interactionTrigger: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsActivity = false
    @State private var isPressed = false
    @State private var motion: SealStatusMotion

    init(
        status: HomeViewState.Status,
        isServerActivity: Bool = false,
        interactionTrigger: Int = 0
    ) {
        self.status = status
        self.isServerActivity = isServerActivity
        self.interactionTrigger = interactionTrigger
        _motion = State(
            initialValue: SealStatusMotion(phase: status.motionPhase)
        )
    }

    var body: some View {
        ZStack {
            recessedTrack
            statusRing

            if showsActivity {
                PaperActivityArc(
                    accent: activityAccent,
                    reduceMotion: reduceMotion
                )
                .transition(.opacity)
            }

            PapercutResultBurst(
                animationID: motion.animationID,
                accent: accent,
                reduceMotion: reduceMotion
            )

            Circle()
                .fill(PapercutPalette.card)
                .frame(width: 126, height: 126)
                .shadow(color: .black.opacity(0.40), radius: 7, y: 6)

            Image(systemName: icon)
                .font(.system(size: 66, weight: .bold))
                .foregroundStyle(accent)
                .offset(x: iconHorizontalOffset)
                .shadow(color: .black.opacity(0.38), radius: 6, y: 8)
                .contentTransition(.symbolEffect(.replace))
                .animation(
                    .spring(response: 0.34, dampingFraction: 0.72),
                    value: icon
                )
        }
        .frame(width: 170, height: 170)
        .scaleEffect(
            (isPressed && !reduceMotion ? 0.965 : 1)
                * CGFloat(motion.resultScale)
        )
        .offset(y: isPressed && !reduceMotion ? 2 : 0)
        .opacity(isPressed && reduceMotion ? 0.82 : 1)
        .accessibilityHidden(true)
        .task(id: isServerActivity) {
            await updateActivityVisibility()
        }
        .task(id: interactionTrigger) {
            await runPressFeedback()
        }
        .task(id: motion.animationID) {
            await runStatusMotion(for: motion.animationID)
        }
        .onChange(of: status.motionPhase) { _, newPhase in
            motion.transition(to: newPhase)
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

    @ViewBuilder
    private var statusRing: some View {
        switch status.motionPhase {
        case .unknown:
            EmptyView()

        case .sealed:
            Circle()
                .trim(from: 0, to: status.progressFraction)
                .stroke(
                    accent,
                    style: StrokeStyle(lineWidth: 18, lineCap: .round)
                )
                .padding(9)
                .rotationEffect(.degrees(-90))

        case .unsealed:
            PapercutUnsealRingReveal(
                progress: CGFloat(motion.unsealRevealProgress),
                accent: PapercutPalette.unsealed
            )
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
            return 8
        case .unknown, .sealed:
            return 0
        }
    }

    private func updateActivityVisibility() async {
        if isServerActivity {
            do {
                try await Task.sleep(for: .seconds(MotionTiming.activityDelay))
            } catch {
                return
            }

            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: MotionTiming.activityFade)) {
                showsActivity = true
            }
            return
        }

        withAnimation(.easeOut(duration: MotionTiming.activityFade)) {
            showsActivity = false
        }
    }

    private func runPressFeedback() async {
        guard interactionTrigger > 0 else { return }

        withAnimation(.easeOut(duration: MotionTiming.pressDown)) {
            isPressed = true
        }

        do {
            try await Task.sleep(for: .seconds(MotionTiming.pressHold))
        } catch {
            return
        }

        guard !Task.isCancelled else { return }
        withAnimation(.spring(response: 0.24, dampingFraction: 0.68)) {
            isPressed = false
        }
    }

    private func runStatusMotion(
        for animationID: SealStatusMotion.AnimationID
    ) async {
        switch animationID.effect {
        case .none:
            return

        case .unsealReveal:
            await runUnsealReveal(for: animationID)

        case .result:
            await runResultFeedback(for: animationID)
        }
    }

    private func runUnsealReveal(
        for animationID: SealStatusMotion.AnimationID
    ) async {
        if reduceMotion {
            motion.setUnsealRevealProgress(1, for: animationID)
        } else {
            withAnimation(.easeOut(duration: MotionTiming.unsealReveal)) {
                _ = motion.setUnsealRevealProgress(1, for: animationID)
            }

            do {
                try await Task.sleep(
                    for: .seconds(MotionTiming.unsealReveal)
                )
            } catch {
                return
            }
        }

        motion.completeUnsealReveal(for: animationID)
    }

    private func runResultFeedback(
        for animationID: SealStatusMotion.AnimationID
    ) async {
        guard !reduceMotion else { return }

        withAnimation(.easeOut(duration: MotionTiming.resultCompress)) {
            _ = motion.setResultScale(0.96, for: animationID)
        }

        do {
            try await Task.sleep(
                for: .seconds(MotionTiming.resultCompress)
            )
        } catch {
            return
        }

        guard !Task.isCancelled else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.58)) {
            _ = motion.setResultScale(1.045, for: animationID)
        }

        do {
            try await Task.sleep(
                for: .seconds(MotionTiming.resultSettleDelay)
            )
        } catch {
            return
        }

        guard !Task.isCancelled else { return }
        withAnimation(.spring(response: 0.24, dampingFraction: 0.78)) {
            _ = motion.setResultScale(1, for: animationID)
        }
    }
}

private extension HomeViewState.Status {
    var motionPhase: SealStatusMotion.Phase {
        switch self {
        case .unknown:
            return .unknown
        case .sealed:
            return .sealed
        case .unsealed:
            return .unsealed
        }
    }
}

private enum MotionTiming {
    static let activityDelay = 0.16
    static let activityFade = 0.12
    static let pressDown = 0.08
    static let pressHold = 0.09
    static let unsealReveal = 0.46
    static let resultCompress = 0.08
    static let resultSettleDelay = 0.18
}
