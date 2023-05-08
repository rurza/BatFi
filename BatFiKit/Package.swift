// swift-tools-version: 5.8
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

extension Target.Dependency {
    static let dependencies: Self = .product(name: "Dependencies", package: "swift-dependencies")
    static let secureXPC: Self = .product(name: "SecureXPC", package: "SecureXPC")
    static let defaults: Self = .product(name: "Defaults", package: "Defaults")
    static let menuBuilder: Self = .product(name: "MenuBuilder", package: "MenuBuilder")
    static let settingsKit: Self = .product(name: "SettingsKit", package: "SettingsKit")
}

let package = Package(
    name: "BatFiKit",
    platforms: [.macOS(.v13)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(name: "App", targets: ["App"]),
        .library(name: "AppCore", targets: ["AppCore"]),
        .library(name: "AppShared", targets: ["AppShared"]),
        .library(name: "BatteryInfo", targets: ["BatteryInfo"]),
        .library(name: "Charging", targets: ["Charging"]),
        .library(name: "PowerSource", targets: ["PowerSource"]),
        .library(name: "Shared", targets: ["Shared"]),
        .library(name: "Server", targets: ["Server"]),
        .library(name: "Settings", targets: ["Settings"])
    ],
    dependencies: [
        .package(url: "https://github.com/trilemma-dev/SecureXPC", branch: "executable-path"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "0.1.4"),
        .package(url: "https://github.com/trilemma-dev/EmbeddedPropertyList", from: "2.0.0"),
//        .package(url: "https://github.com/rurza/SettingsKit.git", branch: "main"),
        .package(name: "SettingsKit", path: "../../SettingsKit"),
        .package(url: "https://github.com/sindresorhus/Defaults", branch: "main"),
        .package(url: "https://github.com/j-f1/MenuBuilder", from: "3.0.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(name: "Shared", dependencies: [.secureXPC]),
        .target(
            name: "PowerSource",
            dependencies: [.dependencies, "Shared"]),
        .target(
            name: "Charging",
            dependencies: [
                "Shared",
                .secureXPC,
                .dependencies
            ]
        ),
        .target(name: "BatteryInfo", dependencies: [
            .dependencies,
            "AppShared",
            "Charging",
            "PowerSource"
        ]),
        .testTarget(name: "BatteryInfoTests", dependencies: ["BatteryInfo"]),
        .target(name: "Settings", dependencies: [
            .defaults,
            .settingsKit
        ]),
        .target(name: "Server", dependencies: [
            "Shared",
            .secureXPC,
            .product(name: "EmbeddedPropertyList", package: "EmbeddedPropertyList")
        ]),
        .target(name: "AppShared"),
        .target(name: "AppCore", dependencies: [
            "Charging",
            "Settings",
            "Shared",
            "PowerSource",
            .dependencies
        ]),
        .target(
            name: "App",
            dependencies: [
                "AppCore",
                "BatteryInfo",
                "Settings",
                .menuBuilder,
                .defaults
            ]
        )
    ]
)
