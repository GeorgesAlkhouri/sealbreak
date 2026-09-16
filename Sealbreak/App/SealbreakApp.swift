import SwiftUI

@main
@MainActor
struct SealbreakApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            AppRootView(model: model)
        }
    }
}
