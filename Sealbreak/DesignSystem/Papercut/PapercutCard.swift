import SwiftUI

struct PapercutCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(PapercutPalette.cardBack2)
                .offset(x: 8, y: 11)
                .shadow(color: .black.opacity(0.30), radius: 9, y: 8)

            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(PapercutPalette.cardBack1)
                .offset(x: 4, y: 6)
                .shadow(color: .black.opacity(0.24), radius: 7, y: 5)

            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(PapercutPalette.card)
                .shadow(color: .black.opacity(0.36), radius: 11, y: 10)

            content
        }
    }
}

struct PapercutFeedback: View {
    let feedback: AppFeedback

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(accent)
                .accessibilityHidden(true)

            Text(feedback.text)
                .font(.footnote.weight(.medium))
                .foregroundStyle(PapercutPalette.cream)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(PapercutPalette.card.opacity(0.92))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(accent.opacity(0.55), lineWidth: 1)
                }
        }
        .accessibilityElement(children: .combine)
    }

    private var icon: String {
        switch feedback.level {
        case .info:
            "info.circle.fill"
        case .success:
            "checkmark.circle.fill"
        case .warning:
            "exclamationmark.triangle.fill"
        case .error:
            "xmark.circle.fill"
        }
    }

    private var accent: Color {
        switch feedback.level {
        case .info:
            PapercutPalette.secondaryText
        case .success:
            PapercutPalette.unsealed
        case .warning:
            PapercutPalette.sun
        case .error:
            PapercutPalette.sealed
        }
    }
}

extension View {
    func papercutPrimaryButtonAppearance() -> some View {
        foregroundStyle(PapercutPalette.cream)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 62)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 21, style: .continuous)
                        .fill(PapercutPalette.buttonBack)
                        .offset(x: 2, y: 5)

                    RoundedRectangle(cornerRadius: 21, style: .continuous)
                        .fill(PapercutPalette.button)
                }
            }
            .shadow(color: .black.opacity(0.30), radius: 8, y: 8)
    }
}
