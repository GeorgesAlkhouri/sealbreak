import SwiftUI

@main
@MainActor
struct SealbreakApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
        }
    }
}

// SwiftUI has no title + content + footer convenience initializer for Section.
// Keep the call sites readable while delegating to the canonical header/footer form.
extension Section where Parent == Text, Content: View, Footer: View {
    init(
        _ title: String,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.init(
            content: content,
            header: { Text(title) },
            footer: footer
        )
    }
}
