import ComposableArchitecture
import SealbreakCore
import SwiftUI

public struct SealbreakRootView: View {
    private let store: StoreOf<AppFeature>

    public init() {
        store = Store(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.sealbreakClient = .live
        }
    }

    public var body: some View {
        AppRootView(store: store)
    }
}
