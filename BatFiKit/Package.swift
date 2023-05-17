// swift-tools-version: 5.8

import PackageDescription

let package = Package(
    name: "BatFiKit",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "App", targets: ["App"]),
        .library(name: "AppCore", targets: ["AppCore"]),
        .library(name: "AppShared", targets: ["AppShared"]),
        .library(name: "BatteryInfo", targets: ["BatteryInfo"]),
        .library(name: "Shared", targets: ["Shared"]),
        .library(name: "Server", targets: ["Server"]),
        .library(name: "Settings", targets: ["Settings"]),
        .library(name: "ClientsLive", targets: ["ClientsLive"])
    ],
    dependencies: [
        .package(url: "https://github.com/trilemma-dev/SecureXPC", branch: "main"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "0.1.4"),
        .package(url: "https://github.com/trilemma-dev/EmbeddedPropertyList", from: "2.0.0"),
        .package(url: "https://github.com/rurza/SettingsKit.git", branch: "main"),
        .package(url: "https://github.com/rurza/AboutKit.git", branch: "main"),
        .package(url: "https://github.com/sindresorhus/Defaults", branch: "main"),
        .package(url: "https://github.com/j-f1/MenuBuilder", from: "3.0.0"),
        .package(url: "https://github.com/apple/swift-async-algorithms", from: "0.1.0")
    ],
    targets: [
        .target(name: "Shared", dependencies: [.secureXPC]),
        .target(
            name: "Clients",
            dependencies: [
                "AppShared",
                "Shared",
                .dependencies
            ]
        ),
        .target(
            name: "ClientsLive",
            dependencies: [
                "AppShared",
                "Clients",
                "DefaultsKeys",
                "Shared",
                .asyncAlgorithms,
                .defaults,
                .dependencies,
                .secureXPC
            ]
        ),
        .target(name: "BatteryInfo", dependencies: [
            "AppShared",
            "Clients",
            .dependencies
        ]),
        .testTarget(name: "BatteryInfoTests", dependencies: ["BatteryInfo"]),
        .target(name: "Settings", dependencies: [
            "Clients",
            "DefaultsKeys",
            .settingsKit
        ]),
        .target(name: "Server", dependencies: [
            "Shared",
            .product(name: "EmbeddedPropertyList", package: "EmbeddedPropertyList"),
            .secureXPC
        ]),
        .target(name: "AppShared"),
        .target(name: "AppCore", dependencies: [
            "AppShared",
            "Clients",
            "Settings",
            "Shared",
            .dependencies,
            .asyncAlgorithms
        ]),
        .testTarget(name: "AppCoreTests", dependencies: ["AppCore"]),
        .target(
            name: "App",
            dependencies: [
                .product(name: "AboutKit", package: "AboutKit"),
                "AppCore",
                "Clients",
                "ClientsLive",
                "BatteryInfo",
                "Settings",
                "Notifications",
                .menuBuilder
            ]
        ),
        .target(name: "DefaultsKeys", dependencies: [.defaults]),
        .target(
            name: "Notifications",
            dependencies: [
                "AppShared",
                "Clients",
                "DefaultsKeys",
                .asyncAlgorithms,
                .defaults,
                .dependencies
            ]
        )
    ]
)

extension Target.Dependency {
    static let dependencies: Self = .product(name: "Dependencies", package: "swift-dependencies")
    static let secureXPC: Self = .product(name: "SecureXPC", package: "SecureXPC")
    static let defaults: Self = .product(name: "Defaults", package: "Defaults")
    static let menuBuilder: Self = .product(name: "MenuBuilder", package: "MenuBuilder")
    static let settingsKit: Self = .product(name: "SettingsKit", package: "SettingsKit")
    static let asyncAlgorithms: Self = .product(name: "AsyncAlgorithms", package: "swift-async-algorithms")
}
