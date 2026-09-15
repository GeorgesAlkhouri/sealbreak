// swift-tools-version: 6.0
import PackageDescription

// Compile the same non-UI behavior sources as the iOS app.
// UIKit-backed live services remain conditionally compiled out on the host.
let package = Package(
    name: "SealbreakCore",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "SealbreakCore",
            path: "Sealbreak",
            exclude: [
                "ContentView.swift", "KeychainStore.swift", "OpenBaoClient.swift",
                "SealbreakApp.swift", "Info.plist", "PrivacyInfo.xcprivacy"
            ],
            sources: ["Models.swift", "AppServices.swift", "AppModel.swift"]
        ),
        .testTarget(name: "SealbreakCoreTests", dependencies: ["SealbreakCore"])
    ],
    swiftLanguageModes: [.v5]
)
