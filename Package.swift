// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "SealbreakCore",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(
            url: "https://github.com/pointfreeco/swift-composable-architecture",
            exact: "1.26.1"
        )
    ],
    targets: [
        .target(
            name: "SealbreakCore",
            dependencies: [
                .product(
                    name: "ComposableArchitecture",
                    package: "swift-composable-architecture"
                )
            ],
            path: "Sealbreak",
            exclude: [
                "App/SealbreakApp.swift",
                "App/AppRootView.swift",
                "App/PrivacyGate.swift",
                "App/SensitiveDraftGuard.swift",
                "Features/Home/HomeView.swift",
                "Features/Home/Components",
                "Features/Setup/SetupView.swift",
                "Features/ServerDetails/ServerDetailsView.swift",
                "Features/ShareManagement/ReplaceShareView.swift",
                "Features/ShareManagement/Components",
                "DesignSystem",
                "Info.plist",
                "PrivacyInfo.xcprivacy"
            ]
        ),
        .testTarget(
            name: "SealbreakCoreTests",
            dependencies: [
                "SealbreakCore",
                .product(
                    name: "ComposableArchitecture",
                    package: "swift-composable-architecture"
                )
            ],
            path: "Tests/SealbreakCoreTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
