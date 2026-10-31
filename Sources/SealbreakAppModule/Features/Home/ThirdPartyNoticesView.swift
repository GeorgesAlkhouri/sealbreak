import Foundation
import SwiftUI

struct ThirdPartyNoticesView: View {
  @Environment(\.dismiss) private var dismiss

  private let notices = Self.bundledNotices()

  var body: some View {
    NavigationStack {
      ScrollView {
        Text(verbatim: notices)
          .font(.footnote.monospaced())
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding()
      }
      .navigationTitle(LocalizedStringResource("Third-party notices", bundle: .module))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button(LocalizedStringResource("Done", bundle: .module)) {
            dismiss()
          }
        }
      }
    }
  }

  // The app target owns the file, so it lives in the main bundle rather than in Bundle.module.
  static func bundledNotices(in bundle: Bundle = .main) -> String {
    bundle.url(forResource: "THIRD_PARTY_NOTICES", withExtension: "md")
      .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
  }
}
