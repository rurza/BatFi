// swift-tools-version: 5.8

import PackageDescription

extension Target.Dependency {
    static let dependencies: Self = .product(name: "Dependencies", package: "swift-dependencies")
    static let secureXPC: Self = .product(name: "SecureXPC", package: "SecureXPC")
    static let defaults: Self = .product(name: "Defaults", package: "Defaults")
    static let menuBuilder: Self = .product(name: "MenuBuilder", package: "MenuBuilder")
    static let settingsKit: Self = .product(name: "SettingsKit", package: "SettingsKit")
    static let asyncAlgorithms: Self = .product(name: "AsyncAlgorithms", package: "swift-async-algorithms")
    static let sparkle: Self = .product(name: "Sparkle", package: "Sparkle")
    static let snapKit: Self = .product(name: "SnapKit", package: "SnapKit")
    static let embeddedPropertyList: Self = .product(name: "EmbeddedPropertyList", package: "EmbeddedPropertyList")
    static let aboutKit: Self = .product(name: "AboutKit", package: "AboutKit")
    static let statusItemArrowKit: Self = .product(name: "StatusItemArrowKit", package: "StatusItemArrowKit")
    static let confetti: Self = .product(name: "ConfettiSwiftUI", package: "ConfettiSwiftUI")
}

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
        .library(name: "ClientsLive", targets: ["ClientsLive"]),
        .library(name: "BatteryIndicator", targets: ["BatteryIndicator"]),
        .library(name: "Onboarding", targets: ["Onboarding"])
    ],
    dependencies: [
        .package(url: "https://github.com/trilemma-dev/SecureXPC", branch: "main"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "0.1.4"),
        .package(url: "https://github.com/trilemma-dev/EmbeddedPropertyList", from: "2.0.0"),
        .package(url: "https://github.com/rurza/SettingsKit.git", branch: "main"),
//        .package(url: "https://github.com/rurza/AboutKit.git", branch: "main"),
        .package(path: "../../AboutKit"),
        .package(url: "https://github.com/sindresorhus/Defaults", branch: "main"),
        .package(url: "https://github.com/j-f1/MenuBuilder", from: "3.0.0"),
        .package(url: "https://github.com/apple/swift-async-algorithms", from: "0.1.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.4.1"),
        .package(url: "https://github.com/SnapKit/SnapKit", branch: "main"),
        .package(url: "https://github.com/rurza/StatusItemArrowKit.git", branch: "main"),
        .package(url: "https://github.com/simibac/ConfettiSwiftUI", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "About",
            dependencies: [
                .aboutKit
            ]
        ),
        .target(
            name: "App",
            dependencies: [
                "About",
                "AppCore",
                "BatteryIndicator",
                "BatteryInfo",
                "Clients",
                "ClientsLive",
                "DefaultsKeys",
                "Notifications",
                "Onboarding",
                "Settings",
                .menuBuilder,
                .statusItemArrowKit
            ]
        ),
        .target(name: "AppCore", dependencies: [
            "AppShared",
            "BatteryInfo",
            "Clients",
            "DefaultsKeys",
            "Settings",
            "Shared",
            .dependencies,
            .asyncAlgorithms,
            .snapKit
        ]),
        .testTarget(name: "AppCoreTests", dependencies: ["AppCore"]),
        .target(name: "AppShared"),
        .target(
            name: "Shared",
            dependencies: [.secureXPC]
        ),
        .target(
            name: "BatteryIndicator",
            dependencies: [
            ]
        ),
        .target(name: "BatteryInfo", dependencies: [
            "AppShared",
            "Clients",
            .asyncAlgorithms,
            .dependencies
        ]),
        .testTarget(name: "BatteryInfoTests", dependencies: ["BatteryInfo"]),
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
                .secureXPC,
                .sparkle
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
                .dependencies
            ]
        ),
        .target(
            name: "Onboarding",
            dependencies: [
                "Clients",
                "DefaultsKeys",
                .confetti,
                .defaults
            ]
        ),
        .target(name: "Server", dependencies: [
            "Shared",
            .embeddedPropertyList,
            .secureXPC
        ]),
        .target(name: "Settings", dependencies: [
            "AppShared",
            "Clients",
            "DefaultsKeys",
            .settingsKit,
            .dependencies
        ])
    ]
)
