import SwiftUI

struct PapercutScreen<Header: View, Content: View>: View {
  private let scrollID: AnyHashable?
  private let header: Header
  private let content: Content

  init(
    scrollID: AnyHashable? = nil,
    @ViewBuilder header: () -> Header,
    @ViewBuilder content: () -> Content
  ) {
    self.scrollID = scrollID
    self.header = header()
    self.content = content()
  }

  var body: some View {
    ZStack {
      PapercutBackground()

      ScrollView {
        content
      }
      .scrollIndicators(.hidden)
      .scrollBounceBehavior(.basedOnSize)
      .scrollClipDisabled()
      .scrollEdgeEffectHidden(for: .top)
      // Recreate only the scroller when a setup step changes.
      .id(scrollID)
      .safeAreaInset(edge: .top, spacing: 0) {
        header
          .padding(.horizontal, 24)
          .padding(.top, 8)
          .padding(.bottom, 56)
          .frame(maxWidth: .infinity)
          .background {
            HeaderWaveShape()
              .fill(PapercutPalette.mountainNear)
              .shadow(color: .black.opacity(0.25), radius: 7, y: 6)
              .contentShape(HeaderWaveShape())
              // Covered scroll controls must not receive taps through the paper.
              .onTapGesture {}
              .accessibilityHidden(true)
              .ignoresSafeArea(edges: .top)
          }
      }
    }
    .background(PapercutPalette.sky)
  }
}
