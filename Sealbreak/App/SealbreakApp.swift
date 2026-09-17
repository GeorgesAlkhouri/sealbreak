import ComposableArchitecture
import SwiftUI

@main
struct SealbreakApp: App {
    private let store = Store(initialState: AppFeature.State()) {
        AppFeature()
    }

    var body: some Scene {
        WindowGroup {
            AppRootView(store: store)
        }
    }
}
