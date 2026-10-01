// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "Sealbreak",
    platforms: [
        .iOS("26.0"),
        .macOS(.v13)
    ],
    products: [
        .library(name: "SealbreakCore", targets: ["SealbreakCore"]),
        .library(name: "SealbreakAppModule", targets: ["SealbreakAppModule"])
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
