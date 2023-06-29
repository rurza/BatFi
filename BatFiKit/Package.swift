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
    static let l10n: Self = "L10n"
    static let appShared: Self = "AppShared"
    static let clients: Self = "Clients"
    static let defaultsKeys: Self = "DefaultsKeys"
}

let package = Package(
    name: "BatFiKit",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "App", targets: ["App"]),
        .library(name: "AppCore", targets: ["AppCore"]),
        .library(name: "AppShared", targets: ["AppShared"]),
        .library(name: "BatteryIndicator", targets: ["BatteryIndicator"]),
        .library(name: "BatteryInfo", targets: ["BatteryInfo"]),
        .library(name: "ClientsLive", targets: ["ClientsLive"]),
        .library(name: "Onboarding", targets: ["Onboarding"]),
        .library(name: "Server", targets: ["Server"]),
        .library(name: "Settings", targets: ["Settings"]),
        .library(name: "Shared", targets: ["Shared"])
    ],
    dependencies: [
        .package(url: "https://github.com/trilemma-dev/SecureXPC", branch: "main"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "0.1.4"),
        .package(url: "https://github.com/trilemma-dev/EmbeddedPropertyList", from: "2.0.0"),
        .package(url: "https://github.com/rurza/SettingsKit.git", branch: "main"),
        .package(url: "https://github.com/rurza/AboutKit.git", branch: "main"),
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
                .aboutKit,
                .l10n
            ]
        ),
        .target(
            name: "App",
            dependencies: [
                "About",
                "AppCore",
                "BatteryIndicator",
                "BatteryInfo",
                "ClientsLive",
                "Notifications",
                "Onboarding",
                "Settings",
                .clients,
                .defaultsKeys,
                .l10n,
                .menuBuilder,
                .statusItemArrowKit
            ]
        ),
        .target(name: "AppCore", dependencies: [
            "BatteryInfo",
            "Settings",
            "Shared",
            .appShared,
            .clients,
            .defaultsKeys,
            .dependencies,
            .asyncAlgorithms,
            .snapKit
        ]),
        .testTarget(name: "AppCoreTests", dependencies: ["AppCore"]),
        .target(name: "AppShared", dependencies: [.l10n]),
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
            .appShared,
            .asyncAlgorithms,
            .clients,
            .dependencies,
            .l10n
        ]),
        .testTarget(name: "BatteryInfoTests", dependencies: ["BatteryInfo"]),
        .target(
            name: "Clients",
            dependencies: [
                "Shared",
                .appShared,
                .dependencies
            ]
        ),
        .target(
            name: "ClientsLive",
            dependencies: [
                "Shared",
                .appShared,
                .asyncAlgorithms,
                .clients,
                .defaults,
                .defaultsKeys,
                .dependencies,
                .secureXPC,
                .sparkle
            ]
        ),
        .target(name: "DefaultsKeys", dependencies: [.defaults]),
        .target(
            name: "Notifications",
            dependencies: [
                .appShared,
                .asyncAlgorithms,
                .clients,
                .defaultsKeys,
                .dependencies,
                .l10n
            ]
        ),
        .target(
            name: "L10n",
            exclude: ["localize.sh", "swiftgen.yml"]
        ),
        .target(
            name: "Onboarding",
            dependencies: [
                .clients,
                .confetti,
                .defaults,
                .defaultsKeys
            ]
        ),
        .target(name: "Server", dependencies: [
            "Shared",
            .embeddedPropertyList,
            .secureXPC
        ]),
        .target(name: "Settings", dependencies: [
            .appShared,
            .clients,
            .defaultsKeys,
            .dependencies,
            .settingsKit
        ])
    ]
)
