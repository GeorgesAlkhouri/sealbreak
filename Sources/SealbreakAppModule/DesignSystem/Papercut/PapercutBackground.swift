import SwiftUI

struct PapercutBackground: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            PapercutPalette.sky
                .ignoresSafeArea()

            HeaderWaveShape()
                .fill(PapercutPalette.mountainNear)
                .frame(height: 165)
                .shadow(color: .black.opacity(0.25), radius: 7, y: 6)
                .frame(maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea(edges: .top)

            PapercutLandscape()
                .frame(height: 170)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .ignoresSafeArea(edges: .bottom)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
