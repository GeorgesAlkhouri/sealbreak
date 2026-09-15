// swift-tools-version: 6.0
import PackageDescription

// Compile the same non-UI behavior sources as the iOS app.
// Additional platform-backed production sources are intentionally not part of
// the host test target yet, but are not treated as coverage exclusions.
let package = Package(
    name: "SealbreakCore",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "SealbreakCore",
            path: "Sealbreak",
            exclude: [
                "ContentView.swift", "SealbreakApp.swift",
                "Info.plist", "PrivacyInfo.xcprivacy"
            ],
            sources: ["Models.swift", "AppModel.swift"]
        ),
        .testTarget(name: "SealbreakCoreTests", dependencies: ["SealbreakCore"])
    ],
    swiftLanguageModes: [.v5]
)
