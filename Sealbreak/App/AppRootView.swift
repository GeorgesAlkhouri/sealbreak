import SwiftUI
import UIKit

@MainActor
struct AppRootView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        PrivacyGate(model: model) {
            NavigationStack {
                if model.profile == nil {
                    SetupView(model: model)
                } else {
                    HomeContainer(model: model)
                }
            }
        }
    }
}
