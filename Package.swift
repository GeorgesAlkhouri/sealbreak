// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "Sealbreak",
    platforms: [
        .iOS("26.0"),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "SealbreakCore",
            targets: ["SealbreakCore"]
        ),
        .library(
            name: "SealbreakAppModule",
            targets: ["SealbreakAppModule"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/pointfreeco/swift-composable-architecture",
            exact: "1.26.2"
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
                "App/SealbreakRootView.swift",
                "Features/Home/HomeView.swift",
                "Features/Home/Components",
                "Features/Welcome/WelcomeView.swift",
                "Features/Setup/SetupView.swift",
                "Features/Setup/Instance/InstanceSetupView.swift",
                "Features/Setup/Share/ShareSetupView.swift",
                "Features/ServerDetails/ServerDetailsView.swift",
                "Features/ShareManagement/ReplaceShareView.swift",
                "Features/ShareManagement/Components",
                "DesignSystem",
                "Infrastructure/Live",
                "Resources",
                "Info.plist",
                "PrivacyInfo.xcprivacy"
            ]
        ),
        .target(
            name: "SealbreakAppModule",
            dependencies: [
                "SealbreakCore",
                .product(
                    name: "ComposableArchitecture",
                    package: "swift-composable-architecture"
                )
            ],
            path: "Sealbreak",
            exclude: [
                "App/SealbreakApp.swift",
                "App/AppFeature.swift",
                "App/PrivacyFeature.swift",
                "Dependencies",
                "Domain",
                "Features/Home/HomeFeature.swift",
                "Features/Home/HomeViewState.swift",
                "Features/Home/SealStatusMotion.swift",
                "Features/Welcome/WelcomeFeature.swift",
                "Features/Setup/SetupFeature.swift",
                "Features/Setup/Instance/InstanceSetupFeature.swift",
                "Features/Setup/Share/ShareSetupFeature.swift",
                "Features/ServerDetails/ServerDetailsFeature.swift",
                "Features/ShareManagement/ReplaceShareFeature.swift",
                "Infrastructure/DNSSECResolver.swift",
                "Infrastructure/KeychainStore.swift",
                "Infrastructure/SealServerClient.swift",
                "Resources",
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
