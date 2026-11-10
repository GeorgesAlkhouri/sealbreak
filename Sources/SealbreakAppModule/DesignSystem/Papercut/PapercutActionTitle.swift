import SwiftUI

// Stack every title so a state change only fades. A single re-centered Text
// slides over the icon when a change interrupts an animated one. The stack is
// as tall as its tallest title, which keeps the action's bounds stable.
struct PapercutActionTitle: View {
  private let titles: [LocalizedStringResource]
  private let selectedIndex: Int

  init(_ selected: LocalizedStringResource, reserving titles: [LocalizedStringResource] = []) {
    // An unreserved title would share one slot and slide again.
    assert(titles.isEmpty || titles.contains(selected), "Reserve every title the action can show.")
    var unique: [LocalizedStringResource] = []
    for title in titles + [selected] where !unique.contains(title) {
      unique.append(title)
    }
    self.titles = unique
    self.selectedIndex = unique.firstIndex(of: selected) ?? 0
  }

  var body: some View {
    ZStack {
      ForEach(titles.indices, id: \.self) { index in
        Text(titles[index])
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity)
          .opacity(index == selectedIndex ? 1 : 0)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(titles[selectedIndex]))
  }
}
