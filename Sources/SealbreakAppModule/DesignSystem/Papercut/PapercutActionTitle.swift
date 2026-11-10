import SwiftUI

/// The centered title of a primary action whose text depends on its state.
///
/// Every title the action can show is laid out on top of the others and only
/// the selected one is visible. A single `Text` whose string changes is
/// re-centered on every change, so a change that interrupts an animated one
/// keeps the in-flight offset and can slide the title over the action's icon.
/// Stacked titles keep the title's geometry independent of the state and
/// reduce a state change to a cross-fade.
struct PapercutActionTitle: View {
  private let titles: [LocalizedStringResource]
  private let selected: LocalizedStringResource

  /// - Parameters:
  ///   - selected: The visible title. It is shown even if `titles` omits it.
  ///   - titles: Every title the action can show, in a stable order.
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
