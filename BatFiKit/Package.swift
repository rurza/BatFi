// swift-tools-version: 5.8
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "BatFiKit",
    platforms: [.macOS(.v13)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "Shared",
            targets: ["Shared"]),
        .library(
            name: "Charging",
            targets: ["Charging"]),
        .library(name: "App", targets: ["App"]),
        .library(name: "Server", targets: ["Server"])
    ],
    dependencies: [
        .package(name: "SecureXPC", path: "../SecureXPC"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "0.1.4"),
        .package(url: "https://github.com/trilemma-dev/EmbeddedPropertyList", from: "2.0.0"),
        .package(url: "https://github.com/rurza/SettingsKit.git", branch: "main"),
        .package(url: "https://github.com/sindresorhus/Defaults", branch: "main"),
        .package(url: "https://github.com/j-f1/MenuBuilder", from: "3.0.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(name: "Shared", dependencies: [.product(name: "SecureXPC", package: "SecureXPC")]),
        .target(
            name: "Charging",
            dependencies: [
                "Shared",
                .product(name: "SecureXPC", package: "SecureXPC"),
                .product(name: "Dependencies", package: "swift-dependencies")
            ]
        ),
        .target(name: "Server", dependencies: [
            "Shared",
            .product(name: "SecureXPC", package: "SecureXPC"),
            .product(name: "EmbeddedPropertyList", package: "EmbeddedPropertyList")
        ]),
        .target(name: "App", dependencies: [
            "Shared",
            "Charging",
            .product(name: "SecureXPC", package: "SecureXPC"),
            .product(name: "MenuBuilder", package: "MenuBuilder"),
            .product(name: "Defaults", package: "Defaults"),
            .product(name: "SettingsKit", package: "SettingsKit")
        ])
    ]
)
