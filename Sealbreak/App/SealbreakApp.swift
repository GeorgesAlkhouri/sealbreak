import SealbreakAppModule
import SwiftUI

@main
struct SealbreakApp: App {
    private let rootView = SealbreakRootView()

    var body: some Scene {
        WindowGroup {
            rootView
        }
    }
}
