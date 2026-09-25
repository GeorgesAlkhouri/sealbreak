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
