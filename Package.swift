// swift-tools-version: 6.0
import PackageDescription

// Compile the SAME model source as the iOS app; no copy, dependency or app refactor.
// Host-only tests do not exercise Face ID, Keychain, UIKit or the network client.
let package = Package(
    name: "SealbreakCore",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "SealbreakCore",
            path: "Sealbreak",
            exclude: [
                "AppModel.swift", "ContentView.swift", "KeychainStore.swift",
                "OpenBaoClient.swift", "SealbreakApp.swift", "Info.plist", "PrivacyInfo.xcprivacy"
            ],
            sources: ["Models.swift"]
        ),
        .testTarget(name: "SealbreakCoreTests", dependencies: ["SealbreakCore"])
    ],
    swiftLanguageModes: [.v5]
)
