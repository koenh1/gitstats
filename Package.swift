// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "GitStats",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "GitStats", targets: ["GitStats"]),
    ],
    targets: [
        .target(
            name: "GitKit",
            dependencies: []
        ),
        .target(
            name: "ChartEngine",
            dependencies: []
        ),
        .executableTarget(
            name: "GitStats",
            dependencies: ["GitKit", "ChartEngine"],
            resources: [
                .copy("Resources/AppIcon.png")
            ]
        ),
        .testTarget(
            name: "GitKitTests",
            dependencies: ["GitKit", "ChartEngine"],
            exclude: ["test-repo", "create_test_repo.sh"]
        ),
    ]
)
