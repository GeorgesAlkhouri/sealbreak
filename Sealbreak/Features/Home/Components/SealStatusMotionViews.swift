import SwiftUI

struct PaperActivityArc: View {
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
