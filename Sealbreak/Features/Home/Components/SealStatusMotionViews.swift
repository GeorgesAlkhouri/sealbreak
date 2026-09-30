import SwiftUI

struct PapercutUnsealRingReveal: View {
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

struct PapercutResultBurst: View {
    let animationID: SealStatusMotion.AnimationID
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
        .opacity(animationID.effect == .result ? 1 - progress : 0)
        .task(id: animationID) {
            guard animationID.effect == .result else {
                progress = 1
                return
            }

            progress = 0
            withAnimation(
                .easeOut(duration: reduceMotion ? 0.28 : 0.48)
            ) {
                progress = 1
            }
        }
    }
}
