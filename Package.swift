// swift-tools-version: 6.0
import PackageDescription

// Compile all non-UI production sources into the host-testable package.
let package = Package(
    name: "SealbreakCore",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "SealbreakCore",
            path: "Sealbreak",
            exclude: [
                "App",
                "Features",
                "DesignSystem",
                "Info.plist",
                "PrivacyInfo.xcprivacy"
            ]
        ),
        .testTarget(name: "SealbreakCoreTests", dependencies: ["SealbreakCore"])
    ],
    swiftLanguageModes: [.v5]
)
