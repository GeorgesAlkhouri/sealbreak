import SwiftUI

struct PapercutBackground: View {
  var body: some View {
    ZStack(alignment: .bottom) {
      PapercutPalette.sky
        .ignoresSafeArea()

      PapercutLandscape()
        .frame(height: 170)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .ignoresSafeArea(edges: .bottom)
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}
