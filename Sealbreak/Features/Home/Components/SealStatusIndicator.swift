import SwiftUI

struct SealStatusIndicator: View {
    let status: HomeViewState.Status
    let isServerActivity: Bool
    let interactionTrigger: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsActivity = false
    @State private var isPressed = false
    @State private var resultScale: CGFloat = 1
    @State private var resultTrigger = 0
    @State private var unsealRevealTrigger = 0
    @State private var unsealRevealProgress: CGFloat

    init(
        status: HomeViewState.Status,
        isServerActivity: Bool = false,
        interactionTrigger: Int = 0
    ) {
        self.status = status
        self.isServerActivity = isServerActivity
        self.interactionTrigger = interactionTrigger
        _unsealRevealProgress = State(
            initialValue: status.isUnsealed ? 1 : 0
        )
    }

    var body: some View {
        ZStack {
            recessedTrack

            if status.isUnsealed {
                PapercutUnsealRingReveal(
                    progress: unsealRevealProgress,
                    accent: PapercutPalette.unsealed
                )
            } else if statusPhase != .unknown {
                Circle()
                    .trim(from: 0, to: status.progressFraction)
                    .stroke(
                        accent,
                        style: StrokeStyle(lineWidth: 18, lineCap: .round)
                    )
                    .padding(9)
                    .rotationEffect(.degrees(-90))
            }

            if showsActivity {
                PaperActivityArc(
                    accent: activityAccent,
                    reduceMotion: reduceMotion
                )
                .transition(.opacity)
            }

            PapercutResultBurst(
                trigger: resultTrigger,
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
            (reduceMotion ? 1 : (isPressed ? 0.965 : 1)) * resultScale
        )
        .offset(y: reduceMotion ? 0 : (isPressed ? 2 : 0))
        .opacity(isPressed && reduceMotion ? 0.82 : 1)
        .accessibilityHidden(true)
        .task(id: isServerActivity) {
            await updateActivityVisibility()
        }
        .task(id: interactionTrigger) {
            await runPressFeedback()
        }
        .task(id: resultTrigger) {
            await runResultFeedback()
        }
        .task(id: unsealRevealTrigger) {
            await runUnsealRingReveal()
        }
        .onChange(of: statusPhase) { oldPhase, newPhase in
            if oldPhase == .unknown {
                if newPhase == .unsealed {
                    unsealRevealProgress = 1
                }
                return
            }

            guard newPhase.isResolved,
                  oldPhase != newPhase
            else {
                return
            }

            if oldPhase == .sealed, newPhase == .unsealed {
                unsealRevealProgress = 0
                unsealRevealTrigger += 1
            } else {
                unsealRevealProgress = 0
                resultTrigger += 1
            }
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
            return 8
        case .unknown, .sealed:
            return 0
        }
    }

    private var statusPhase: StatusPhase {
        switch status {
        case .unknown:
            return .unknown
        case .sealed:
            return .sealed
        case .unsealed:
            return .unsealed
        }
    }

    private func updateActivityVisibility() async {
        if isServerActivity {
            do {
                try await Task.sleep(for: .milliseconds(160))
            } catch {
                return
            }

            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.12)) {
                showsActivity = true
            }
            return
        }

        withAnimation(.easeOut(duration: 0.12)) {
            showsActivity = false
        }
    }

    private func runPressFeedback() async {
        guard interactionTrigger > 0 else { return }

        withAnimation(.easeOut(duration: 0.08)) {
            isPressed = true
        }

        do {
            try await Task.sleep(for: .milliseconds(90))
        } catch {
            return
        }

        guard !Task.isCancelled else { return }
        withAnimation(.spring(response: 0.24, dampingFraction: 0.68)) {
            isPressed = false
        }
    }

    private func runUnsealRingReveal() async {
        guard unsealRevealTrigger > 0 else { return }

        if reduceMotion {
            unsealRevealProgress = 1
        } else {
            withAnimation(.easeOut(duration: 0.46)) {
                unsealRevealProgress = 1
            }

            do {
                try await Task.sleep(for: .milliseconds(460))
            } catch {
                return
            }
        }

        guard !Task.isCancelled else { return }
        resultTrigger += 1
    }

    private func runResultFeedback() async {
        guard resultTrigger > 0, !reduceMotion else { return }

        withAnimation(.easeOut(duration: 0.08)) {
            resultScale = 0.96
        }

        do {
            try await Task.sleep(for: .milliseconds(80))
        } catch {
            return
        }

        withAnimation(.spring(response: 0.28, dampingFraction: 0.58)) {
            resultScale = 1.045
        }

        do {
            try await Task.sleep(for: .milliseconds(180))
        } catch {
            return
        }

        guard !Task.isCancelled else { return }
        withAnimation(.spring(response: 0.24, dampingFraction: 0.78)) {
            resultScale = 1
        }
    }

    private enum StatusPhase: Equatable {
        case unknown
        case sealed
        case unsealed

        var isResolved: Bool {
            self != .unknown
        }
    }
}

private extension HomeViewState.Status {
    var isUnsealed: Bool {
        if case .unsealed = self {
            return true
        }
        return false
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
                : .linear(duration: 0.8).repeatForever(autoreverses: false),
            value: animates
        )
    }
}

private struct PapercutUnsealRingReveal: View {
    let progress: CGFloat
    let accent: Color

    private var lineWidth: CGFloat {
        18 * progress
    }

    private var diameter: CGFloat {
        // Keep the inner edge fixed at the cutout radius while the green
        // paper layer grows only outward until it fills the whole channel.
        134 + lineWidth
    }

    var body: some View {
        Circle()
            .stroke(
                accent,
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
            .frame(width: diameter, height: diameter)
            .shadow(color: accent.opacity(0.16), radius: 5)
    }
}

private struct PapercutResultBurst: View {
    let trigger: Int
    let accent: Color
    let reduceMotion: Bool

    @State private var progress: CGFloat = 1

    var body: some View {
        ZStack {
            Circle()
                .stroke(
                    accent.opacity(reduceMotion ? 0.24 : 0.30),
                    lineWidth: reduceMotion ? 8 : 11
                )
                .frame(width: 174, height: 174)
                .offset(y: reduceMotion ? 0 : 3)
                .shadow(
                    color: .black.opacity(reduceMotion ? 0.18 : 0.30),
                    radius: 4,
                    y: 3
                )

            Circle()
                .stroke(
                    accent.opacity(reduceMotion ? 0.46 : 0.72),
                    lineWidth: reduceMotion ? 5 : 7
                )
                .frame(width: 174, height: 174)
        }
        .scaleEffect(reduceMotion ? 1 : 0.94 + (0.22 * progress))
        .opacity(trigger == 0 ? 0 : 1 - progress)
        .task(id: trigger) {
            guard trigger > 0 else { return }

            progress = 0
            withAnimation(
                .easeOut(duration: reduceMotion ? 0.28 : 0.48)
            ) {
                progress = 1
            }
        }
    }
}
