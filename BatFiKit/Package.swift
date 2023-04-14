// swift-tools-version: 5.8
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "BatFiKit",
    products: [
        .library(
            name: "BatFiKit",
            type: .dynamic,
            targets: ["BatFiKit"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/trilemma-dev/SecureXPC", from: "0.8.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "BatFiKit",
            dependencies: [
                .product(name: "SecureXPC", package: "SecureXPC")
            ]
        ),
        .testTarget(
            name: "BatFiKitTests",
            dependencies: ["BatFiKit"]),
    ]
)
