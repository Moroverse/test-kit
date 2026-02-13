// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "test-kit",
    platforms: [
        .iOS(.v17),
        .macCatalyst(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "TestKit",
            targets: ["TestKit"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-custom-dump.git", from: "1.3.3"),
        .package(url: "https://github.com/pointfreeco/swift-concurrency-extras.git", from: "1.3.2")
    ],
    targets: [
        .target(
            name: "TestKit",
            dependencies: [
                .product(name: "CustomDump", package: "swift-custom-dump"),
                .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras")
            ],
            linkerSettings: [
                .linkedFramework("Testing")
            ]
        ),
        .testTarget(
            name: "TestKitTests",
            dependencies: [
                "TestKit"
            ]
        )
    ]
)
