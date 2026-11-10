import SwiftUI

// Stack every title so a state change only fades. A single re-centered Text
// slides over the icon when a change interrupts an animated one.
struct PapercutActionTitle: View {
  private let titles: [LocalizedStringResource]
  private let selected: LocalizedStringResource

  init(_ selected: LocalizedStringResource, reserving titles: [LocalizedStringResource]) {
    self.selected = selected
    self.titles = titles.contains(selected) ? titles : titles + [selected]
  }

  var body: some View {
    ZStack {
      ForEach(titles.indices, id: \.self) { index in
        Text(titles[index])
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity)
          .opacity(titles[index] == selected ? 1 : 0)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(selected))
  }
}
