// swift-tools-version: 5.9

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
    static let identifiedCollections: Self = .product(name: "IdentifiedCollections", package: "swift-identified-collections")
    static let l10n: Self = "L10n"
    static let appShared: Self = "AppShared"
    static let clients: Self = "Clients"
    static let defaultsKeys: Self = "DefaultsKeys"
    static let persistence: Self = "Persistence"
    static let shared: Self = "Shared"
    static let powerCharts: Self = "PowerCharts"
    static let powerInfo: Self = "PowerInfo"
    static let settings: Self = "Settings"
    static let highEnergyUsage: Self = "HighEnergyUsage"
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
        .package(url: "https://github.com/simibac/ConfettiSwiftUI", from: "1.0.0"),
        .package(url: "https://github.com/pointfreeco/swift-identified-collections", from: "1.0.0")
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
                .clients,
                .defaultsKeys,
                .l10n,
                .menuBuilder,
                .settings,
                .statusItemArrowKit
            ]
        ),
        .target(name: "AppCore", dependencies: [
            "BatteryInfo",
            .appShared,
            .asyncAlgorithms,
            .clients,
            .defaultsKeys,
            .dependencies,
            .highEnergyUsage,
            .l10n,
            .powerCharts,
            .powerInfo,
            .settings,
            .shared,
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
            .l10n,
        ]),
        .testTarget(name: "BatteryInfoTests", dependencies: ["BatteryInfo"]),
        .target(
            name: "Clients",
            dependencies: [
                .appShared,
                .dependencies,
                .shared
            ]
        ),
        .target(
            name: "ClientsLive",
            dependencies: [
                .appShared,
                .asyncAlgorithms,
                .clients,
                .defaults,
                .defaultsKeys,
                .dependencies,
                .persistence,
                .secureXPC,
                .shared,
                .sparkle
            ]
        ),
        .target(name: "DefaultsKeys", dependencies: [.defaults]),
        .target(
            name: "HighEnergyUsage",
            dependencies: [
                .asyncAlgorithms,
                .appShared,
                .clients,
                .dependencies,
                .defaults,
                .defaultsKeys,
                .l10n,
                .shared
            ]
        ),
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
            name: "L10n"
        ),
        .target(
            name: "Onboarding",
            dependencies: [
                .appShared,
                .clients,
                .confetti,
                .defaults,
                .defaultsKeys,
                .l10n
            ]
        ),
        .target(
            name: "Persistence",
            dependencies: [
                .appShared,
                .dependencies,
                .shared
            ]
        ),
        .target(
            name: "PowerCharts",
            dependencies: [
                .appShared,
                .clients,
                .dependencies,
                .l10n,
                .persistence,
                .identifiedCollections
            ]
        ),
        .target(name: "PowerInfo", dependencies: [
            .appShared,
            .clients,
            .dependencies,
            .l10n,
            .shared
        ]),
        .target(name: "Server", dependencies: [
            .embeddedPropertyList,
            .secureXPC,
            .shared
        ]),
        .target(name: "Settings", dependencies: [
            .appShared,
            .clients,
            .defaultsKeys,
            .dependencies,
            .l10n,
            .settingsKit
        ])
    ]
)
